import Foundation
import PDFKit
import UIKit
import Vision
import CryptoKit
import CoreImage
import Observation

@MainActor @Observable private final class ArtworkState { var records:[String:CoverRecord] = [:] }

/// 核心图来自真实图注选择，保留图号和页码；用户仍可重新框选。
enum PaperArtwork {
    static func clearCache() { records = [:];ImageLoader.shared.clear();Task { await CoverPipeline.shared.clear() } }
    private static let state = ArtworkState()
    private static var records:[String:CoverRecord] { get { state.records } set { state.records = newValue } }
    static func credit(_ id:String) -> String? {
        guard let record = records[id],!record.failed,let figure = record.candidates.first(where:{$0.id == record.selected}) else { return nil }
        return figure.label + (figure.page > 0 ? " · PDF 第 \(figure.page) 页" : " · 原文网页图片")
    }
    nonisolated static func cacheURL(_ id:String) -> URL { FigureExtractor.folder(id).appending(path:"display.jpg") }
    static func choice(_ id:String) -> FigureChoice? {
        guard let record = records[id] else { return nil }
        return FigureChoice(ids:record.failed ? [] : record.candidates.map(\.id),reason:record.failed ? "未找到可靠原图，可使用 AI 示意图。" : record.reason,method:record.failed ? "无可靠原图" : record.method,version:3)
    }
    static func candidates(_ id:String) -> [FigureCandidate] { records[id].map { $0.failed ? [] : $0.candidates } ?? [] }
    static func candidateURL(_ id:String,figure:String) -> URL { FigureExtractor.folder(id).appending(path:figure+".jpg") }
    static func prepare(paper:Paper,url:URL?,reading:GeneratedReading? = nil,candidates supplied:[FigureCandidate]? = nil,force:Bool = false) async {
        let record = await CoverPipeline.shared.prepare(paper:paper,pdf:url,force:force)
        guard !Task.isCancelled else { return }
        records[paper.id] = record
    }
    static func hasOriginal(_ id:String) -> Bool { records[id]?.failed == false && records[id]?.selected != nil }
    static func automaticURL(_ id:String) -> URL? {
        guard let record = records[id] else { return nil }
        return CoverPipeline.image(record,folder:FigureExtractor.folder(id))
    }
    static func pageImage(url:URL,page:Int) async -> UIImage? {
        let bytes = await Task.detached(priority:.userInitiated) { PDFDocument(url:url)?.page(at:max(0,page - 1))?.thumbnail(of:CGSize(width:1400,height:1900),for:.mediaBox).jpegData(compressionQuality:0.9) }.value
        return bytes.flatMap { UIImage(data:$0) }
    }
    static func brighten(_ data:Data) async -> Data? {
        await Task.detached(priority:.utility) {
            guard let source = CIImage(data:data) else { return nil }
            let output = source.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:0.08,kCIInputContrastKey:1.08,kCIInputSaturationKey:1.0]).applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:0.3])
            guard let cg = CIContext().createCGImage(output,from:source.extent) else { return nil }
            return UIImage(cgImage:cg).jpegData(compressionQuality:0.9)
        }.value
    }
    static func pageText(url:URL,page:Int) async -> String {
        await Task.detached(priority:.utility) {
            guard let document = PDFDocument(url:url), let source = document.page(at:max(0,page - 1)) else { return "" }
            if let text = source.string, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return text }
            guard let image = source.thumbnail(of:CGSize(width:1600,height:2200),for:.mediaBox).cgImage else { return "" }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US","zh-Hans"]
            try? VNImageRequestHandler(cgImage:image).perform([request])
            return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n") ?? ""
        }.value
    }
}
