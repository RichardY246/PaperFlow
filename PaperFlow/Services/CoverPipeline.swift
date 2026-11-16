import Foundation
import PDFKit
import SwiftSoup
import ImageIO
import Vision
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

nonisolated struct CoverRecord:Codable,Sendable {
    var candidates:[FigureCandidate]
    var selected:String?
    var checkedAt = Date().timeIntervalSince1970
    var method:String
    var reason:String
    var failed:Bool
    var hadPDF:Bool?
    var version = 3
}

/// 同一论文共用任务，所有提图串行；离开卡片不丢弃正在生成的可复用缓存。
actor CoverPipeline {
    static let shared = CoverPipeline()
    private var jobs:[String:Task<CoverRecord,Never>] = [:]
    private var tail:Task<Void,Never>?
    private var clients:[String:Set<UUID>] = [:]
    private var running:Set<String> = []
    private let directory:URL?
    private let allowNetwork:Bool
    init(directory:URL? = nil,allowNetwork:Bool = true) { self.directory = directory;self.allowNetwork = allowNetwork }
    nonisolated func folder(_ id:String) -> URL { FigureExtractor.folder(id,directory:directory) }
    nonisolated static func read(_ folder:URL) -> CoverRecord? {
        (try? Data(contentsOf:folder.appending(path:"cover-v3.json"))).flatMap { try? JSONDecoder().decode(CoverRecord.self,from:$0) }
    }
    func clear() async {
        let previous = tail,directory = directory
        let barrier = Task {
            await previous?.value
            await Task.detached(priority:.utility) {
                if let directory { try? FileManager.default.removeItem(at:directory) }
                else { for path in ["PaperFlow/Covers","PaperFlow/Figures"] { try? FileManager.default.removeItem(at:URL.documentsDirectory.appending(path:path)) } }
            }.value
        }
        tail = barrier;await barrier.value
    }
    func prepare(paper:Paper,pdf:URL?,force:Bool = false) async -> CoverRecord {
        let token = UUID();clients[paper.id,default:[]].insert(token)
        if let job = jobs[paper.id] { return await result(job,id:paper.id,token:token) }
        let folder = folder(paper.id), previous = tail, allowNetwork = allowNetwork
        let job = Task<CoverRecord,Never> {
            await previous?.value
            guard !Task.isCancelled else { return CoverRecord(candidates:[],selected:nil,method:"已取消",reason:"",failed:true) }
            running.insert(paper.id)
            return await Task.detached(priority:.utility) {
                if !force,let saved = Self.read(folder),!(saved.hadPDF != true && pdf != nil),(!saved.failed || Date().timeIntervalSince1970-saved.checkedAt < 86400),saved.selected == nil || FileManager.default.fileExists(atPath:folder.appending(path:saved.selected!+".jpg").path) {
                    try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:folder.path)
                    return saved
                }
                return await Self.extract(paper:paper,pdf:pdf,folder:folder,allowNetwork:allowNetwork)
            }.value
        }
        jobs[paper.id] = job;tail = Task { _ = await job.value }
        let value = await result(job,id:paper.id,token:token);jobs[paper.id] = nil;running.remove(paper.id);return value
    }
    private func result(_ job:Task<CoverRecord,Never>,id:String,token:UUID) async -> CoverRecord {
        let value = await withTaskCancellationHandler { await job.value } onCancel: { Task { await self.release(id,token:token) } }
        release(id,token:token);return value
    }
    private func release(_ id:String,token:UUID) {
        clients[id]?.remove(token)
        if clients[id]?.isEmpty == true { clients[id] = nil;if !running.contains(id) { jobs[id]?.cancel() } }
    }
    nonisolated static func image(_ record:CoverRecord,folder:URL) -> URL? { guard !record.failed else { return nil };return record.selected.map { folder.appending(path:$0+".jpg") } }
    nonisolated static func htmlCandidates(_ html:String,base:URL) throws -> [(String,String,String)] {
        let document = try SwiftSoup.parse(html,base.absoluteString)
        var result:[(String,String,String)] = [],seen:Set<String> = []
        for figure in try document.select("figure, .ltx_figure, .fig") {
            if try figure.className().lowercased().contains("table") { continue }
            let caption = try figure.select("figcaption, .ltx_caption, .caption").text()
            guard !caption.isEmpty,let img = try figure.select("img").first() else { continue }
            let address = try img.attr("src").isEmpty ? img.attr("data-src") : img.attr("src")
            guard let url = URL(string:address,relativeTo:base)?.absoluteURL,PaperIdentity.webURL(url.absoluteString) != nil,seen.insert(url.absoluteString).inserted else { continue }
            let label = caption.range(of:#"^(?:Figure|Fig\.?|图)\s*\d+[a-z]?"#,options:[.regularExpression,.caseInsensitive]).map { String(caption[$0]) } ?? "论文插图 \(result.count+1)"
            result.append((url.absoluteString,String(caption.prefix(800)),label))
            if result.count >= 12 { break }
        };return result
    }
    nonisolated private static func fetch(_ url:URL) async throws -> (Data,URL) {
        var request = URLRequest(url:url);request.timeoutInterval = 10
        request.setValue("PaperFlow/1.7 (academic reader)",forHTTPHeaderField:"User-Agent")
        let (file,response) = try await URLSession.shared.download(for:request)
        defer { try? FileManager.default.removeItem(at:file) }
        let size = (try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? Int.max
        guard (response as? HTTPURLResponse)?.statusCode == 200,size < 15_000_000 else { throw URLError(.badServerResponse) }
        return (try Data(contentsOf:file),response.url ?? url)
    }
    nonisolated private static func extract(paper:Paper,pdf:URL?,folder:URL,allowNetwork:Bool) async -> CoverRecord {
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var candidates:[FigureCandidate] = []
        var pages:[String] = []
        if let id = PaperIdentity.arxiv(paper.sourceURL) { pages.append("https://arxiv.org/html/"+id) }
        if let html = paper.openHTMLURL { pages.append(html) }
        if paper.sourceURL.contains("PMC"),let range = paper.sourceURL.range(of:#"PMC\d+"#,options:.regularExpression) { pages.insert("https://pmc.ncbi.nlm.nih.gov/articles/"+paper.sourceURL[range]+"/",at:0) }
        if pages.isEmpty && !paper.sourceURL.contains("doi.org") { pages.append(paper.sourceURL) }
        for address in (allowNetwork ? Array(NSOrderedSet(array:pages)) : []).prefix(2) {
            guard let address = address as? String,let url = URL(string:address),let (data,base) = try? await fetch(url),let html = String(data:data,encoding:.utf8),let found = try? htmlCandidates(html,base:base) else { continue }
            for (index,item) in found.prefix(6).enumerated() {
                guard let url = URL(string:item.0),let (data,_) = try? await fetch(url),let scored = assessed(data,checkText:false) else { continue }
                let id = "html-"+PaperIdentity.stableID("img",item.0)
                try? scored.0.write(to:folder.appending(path:id+".jpg"),options:.atomic)
                candidates.append(FigureCandidate(id:id,page:0,label:item.2,caption:item.1,anchorX:0,anchorY:0,anchorWidth:1,score:FigureRanking.score(caption:item.1,title:paper.title,abstract:paper.abstractText ?? "",page:index+1,label:item.2)+scored.1,sourceURL:item.0,quality:"ok"))
            }
            if !candidates.isEmpty { break }
        }
        let pdf:URL? = if let pdf { pdf } else if candidates.isEmpty && allowNetwork { try? await PaperFileService.download(paper) } else { nil }
        if candidates.isEmpty,let pdf {
            let all = await FigureExtractor.list(paper:paper,url:pdf)
            let selected = Array(FigureRanking.ordered(all).prefix(6))
            // 分批渲染，避免缓存无关的所有页面。
            for start in stride(from:0,to:selected.count,by:3) {
                let batch = Array(selected[start..<min(start+3,selected.count)])
                await FigureExtractor.render(paperID:paper.id,candidates:all,ids:batch.map(\.id),url:pdf,directory:folder.deletingLastPathComponent(),title:paper.title)
                for var candidate in batch {
                    let source = FigureExtractor.imageURL(paper.id,candidate:candidate.id,directory:folder.deletingLastPathComponent())
                    guard let data = try? Data(contentsOf:source),let scored = assessed(data,checkText:true) else { continue }
                    try? scored.0.write(to:folder.appending(path:candidate.id+".jpg"),options:.atomic)
                    if let data = try? Data(contentsOf:folder.appending(path:"candidates.json")),let extracted = try? JSONDecoder().decode([FigureCandidate].self,from:data) { candidate.bounds = extracted.first(where:{$0.id == candidate.id})?.bounds;candidate.quality = extracted.first(where:{$0.id == candidate.id})?.quality }
                    guard candidate.quality != "suspect" else { continue }
                    candidate.score += scored.1;candidate.sourceURL = paper.sourceURL;candidate.quality = "ok"
                    candidates.append(candidate)
                }
            }
        }
        candidates = Array(FigureRanking.ordered(candidates).prefix(3))
        let failed = candidates.isEmpty
        let record = CoverRecord(candidates:candidates,selected:candidates.first?.id,method:failed ? "等待 AI 示意图" : "原图与图注选图",reason:failed ? "没有找到可靠原图；由独立生图任务处理，不阻塞正文。" : "结合图注相关性、完整度、清晰度和卡片比例排序。",failed:failed,hadPDF:pdf != nil)
        try? JSONEncoder().encode(record).write(to:folder.appending(path:"cover-v3.json"),options:.atomic)
        trimCache(folder.deletingLastPathComponent(),keeping:folder)
        return record
    }
    /// 自动图缓存按论文目录淘汰，用户手动图片在 Media 中，不在清理范围。
    nonisolated private static func trimCache(_ directory:URL,keeping:URL) {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
        let entries = folders.map { folder -> (URL,Int,Date) in
            let files = (fm.enumerator(at:folder,includingPropertiesForKeys:[.fileSizeKey])?.allObjects as? [URL]) ?? []
            let size = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
            return (folder,size,(try? folder.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0+$1.1 }
        for entry in entries where total > 300*1024*1024 && entry.0 != keeping { try? fm.removeItem(at:entry.0);total -= entry.1 }
    }
    /// 解码为展示大小；密集正文裁片直接拒绝，不冒充合格论文插图。
    nonisolated static func assessed(_ data:Data,checkText:Bool) -> (Data,Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],let width = properties[kCGImagePropertyPixelWidth] as? Int,let height = properties[kCGImagePropertyPixelHeight] as? Int,width >= 160,height >= 80,width*height >= 40000,
              let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1100,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        if checkText {
            let request = VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages = ["en-US"];request.minimumTextHeight = 0.008
            try? VNImageRequestHandler(cgImage:cg).perform([request])
            let paragraphs = (request.results ?? []).filter { ($0.topCandidates(1).first?.string.count ?? 0) > 45 }
            if paragraphs.count >= 4 { return nil }
        }
        let aspect = Double(width)/Double(height)
        let fit = aspect >= 0.7 && aspect <= 2.2 ? 3.0 : 0.0
        let output = NSMutableData();guard let destination = CGImageDestinationCreateWithData(output,"public.jpeg" as CFString,1,nil) else { return nil }
        CGImageDestinationAddImage(destination,cg,[kCGImageDestinationLossyCompressionQuality:0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil };return (output as Data,fit)
    }
}
