import Foundation
import PDFKit
import CryptoKit

/// PDF 单独作为文件保存；原文文件名使用散列，避免在线 ID 中的斜杠影响路径。
@MainActor
enum PaperFileService {
    static func clearCache() {
        try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: "PaperFlow/PDFs"))
    }
    nonisolated static func cachedURL(_ paper: Paper,directory:URL? = nil) -> URL {
        cachedURL(id:paper.id,directory:directory)
    }
    nonisolated static func cachedURL(id: String,directory:URL? = nil) -> URL {
        let name = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return (directory ?? URL.documentsDirectory.appending(path: "PaperFlow/PDFs", directoryHint: .isDirectory)).appending(path: name + ".pdf")
    }
    static func localURL(_ paper: Paper,directory:URL? = nil) -> URL? {
        let cached = cachedURL(paper,directory:directory)
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }
    struct Download:Sendable { var file:URL; var remoteURL:String? }
    static func download(_ paper:Paper) async throws -> URL { try await downloadVerified(paper).file }
    /// 只把 PDFKit 确认有效的文件放入缓存；HTML 登录页不会冒充 PDF。
    private static var jobs:[String:Task<Download,Error>] = [:]
    static func downloadVerified(_ paper:Paper,session:URLSession = .shared,maxAttempts:Int = 4,timeout:TimeInterval = 25,directory:URL? = nil) async throws -> Download {
        let key = (directory?.path ?? "device")+"|"+paper.id
        if let job = jobs[key] { return try await job.value }
        let job = Task { try await performDownload(paper,session:session,maxAttempts:maxAttempts,timeout:timeout,directory:directory) }
        jobs[key] = job;defer { jobs[key] = nil };return try await job.value
    }
    private static func performDownload(_ paper:Paper,session:URLSession = .shared,maxAttempts:Int = 4,timeout:TimeInterval = 25,directory:URL? = nil) async throws -> Download {
        if let local = localURL(paper,directory:directory), await validPDF(local) { return Download(file:local,remoteURL:paper.verifiedPDFURL) }
        var queue = FullTextLinks.candidates(paper), seen:Set<String> = [], failures:[String] = []
        guard !queue.isEmpty else { throw ServiceError.message("没有可直接下载的开放版本，可继续查找或通过机构访问。") }
        // 每篇候选版本共用等待预算，避免失效链接逐个等待完整超时。
        let deadline = Date().addingTimeInterval(timeout)
        var attempts = 0
        while !queue.isEmpty && attempts < maxAttempts {
            try Task.checkCancellation()
            guard deadline.timeIntervalSinceNow > 1 else { break }
            let url = queue.removeFirst(); guard seen.insert(url.absoluteString).inserted else { continue }; attempts += 1
            do {
                var request = URLRequest(url:url); request.timeoutInterval = max(1,min(12,deadline.timeIntervalSinceNow))
                request.setValue("PaperFlow/1.6",forHTTPHeaderField:"User-Agent")
                let (temporary,response) = try await session.download(for:request)
                defer { try? FileManager.default.removeItem(at:temporary) }
                try Task.checkCancellation()
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { throw ServiceError.message([401:"需要账号授权",403:"网站限制访问",429:"来源请求受限"][code] ?? "来源返回 \(code)") }
                let size = (try? temporary.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
                guard size < 60_000_000 else { throw ServiceError.message("文件较大，请通过官网阅读或手动导入。") }
                if await validPDF(temporary) {
                    let destination = cachedURL(paper,directory:directory)
                    try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
                    if FileManager.default.fileExists(atPath:destination.path) { try FileManager.default.removeItem(at:destination) }
                    try FileManager.default.moveItem(at:temporary,to:destination)
                    return Download(file:destination,remoteURL:response.url?.absoluteString ?? url.absoluteString)
                }
                if size < 2_000_000, let html = try? String(contentsOf:temporary,encoding:.utf8) {
                    let links = FullTextLinks.pdfURLs(in:html,base:response.url ?? url).filter { !seen.contains($0.absoluteString) }
                    queue.insert(contentsOf:links.prefix(3),at:0)
                }
                failures.append((url.host ?? "来源") + "：返回网页，未取得开放 PDF")
            } catch {
                if Task.isCancelled { throw CancellationError() }
                failures.append((url.host ?? "来源") + "：" + error.localizedDescription)
            }
        }
        throw ServiceError.message("这些版本暂时无法下载。\n" + failures.prefix(3).joined(separator:"\n") + "\n可以打开官网或通过机构登录后导入 PDF。")
    }
    nonisolated static func importPDF(_ source:URL,for paper:Paper,directory:URL? = nil) throws -> URL {
        guard let document = PDFDocument(url:source),document.pageCount > 0 else { throw ServiceError.message("选择的文件不是有效 PDF。") }
        let destination = cachedURL(paper,directory:directory)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        let data = try Data(contentsOf:source); try data.write(to:destination,options:.atomic)
        return destination
    }
    private static func validPDF(_ url:URL) async -> Bool {
        await Task.detached(priority:.utility) { (PDFDocument(url:url)?.pageCount ?? 0) > 0 }.value
    }
    static func readingSource(_ paper: Paper) -> ReadingSource? {
        if let abstract = paper.abstractText, !abstract.isEmpty {
            return ReadingSource(label: "文献摘要", text: String(abstract.prefix(16000)), page: nil)
        }
        if let url = localURL(paper), let page = PDFDocument(url: url)?.page(at: 0), let text = page.string, !text.isEmpty {
            return ReadingSource(label: "PDF 第 1 页（含摘要）", text: String(text.prefix(16000)), page: 1)
        }
        return nil
    }
}
