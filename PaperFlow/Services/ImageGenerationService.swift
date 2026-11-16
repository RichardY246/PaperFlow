import Foundation
import ImageIO
import UniformTypeIdentifiers

/// POST 与图片下载分开：下载返回的 URL 时绝不携带 API Key。
actor ImageGenerationService {
    static let shared = ImageGenerationService()
    private let session:URLSession
    private let downloads:URLSession
    init(session:URLSession? = nil,downloads:URLSession? = nil) {
        self.session = session ?? URLSession(configuration:.ephemeral,delegate:NoAPIRedirects(),delegateQueue:nil)
        self.downloads = downloads ?? URLSession(configuration:.ephemeral)
    }
    deinit { session.invalidateAndCancel(); downloads.invalidateAndCancel() }
    nonisolated struct Rejection: LocalizedError {
        var errorDescription:String? = "智谱拒绝了生图请求，请检查密钥权限、余额或调用频率。"
        var code:String?
        var httpStatus:Int?
    }
    func generate(prompt:String,key:String) async throws -> String {
        var request = URLRequest(url:ImageConfiguration.endpoint)
        request.httpMethod = "POST";request.timeoutInterval = 180
        request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject:["model":ImageConfiguration.model,"prompt":String(prompt.prefix(1000)),"size":ImageConfiguration.size,"quality":"hd"])
        // 不设置 watermark_enabled，保留服务商默认水印。
        let (data,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse else { throw ImageCoverError.uncertain }
        let object = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        if (400..<500).contains(http.statusCode) {
            let code = (object?["error"] as? [String:Any])?["code"].map { String(describing:$0) } ?? ""
            let messages = ["1113":"智谱账户余额不足或没有可用资源包。App 内模拟充值不会增加智谱余额。","1311":"此密钥没有 GLM-Image 权限。","1315":"编程套餐密钥不能用于生图，请关联智谱通用 API 密钥。","1302":"生图请求过快，请稍后手动重试。"]
            // HTTP 429 也可能表示余额不足；以服务代码区分，不能一概当作限流。
            let safeCode = !code.isEmpty && code.count <= 12 && code.allSatisfy({$0.isASCII && $0.isNumber}) ? code : nil
            throw Rejection(errorDescription:messages[code] ?? "生图请求被拒绝（\(http.statusCode)），请检查密钥、模型权限或余额。",code:safeCode,httpStatus:http.statusCode)
        }
        guard (200..<300).contains(http.statusCode),let images = object?["data"] as? [[String:Any]],let text = images.first?["url"] as? String,
              let url = URL(string:text),url.scheme == "https",url.host != nil,url.user == nil,url.password == nil else { throw ImageCoverError.uncertain }
        return text
    }
    /// 图片处理在 actor 上执行，避免大图解码阻塞主线程。下载失败仍保留远端地址。
    func download(_ address:String,id:String,directory:URL? = nil) async throws -> URL {
        guard let url = URL(string:address),url.scheme == "https",url.host != nil,url.user == nil,url.password == nil else { throw ImageCoverError.message("生成图片的下载地址无效。") }
        var request = URLRequest(url:url);request.timeoutInterval = 60
        let (file,response) = try await downloads.download(for:request)
        defer { try? FileManager.default.removeItem(at:file) }
        let bytes = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
        guard let http = response as? HTTPURLResponse,(200..<300).contains(http.statusCode),bytes <= 25_000_000,
              let source = CGImageSourceCreateWithURL(file as CFURL,nil),let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,height > 0,width <= 8192,height <= 8192,
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1536,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { throw ImageCoverError.message("生成结果已保存，但图片下载或解码失败。可重试下载，不会重新生图。") }
        let folder = directory ?? Self.directory
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let target = Self.file(id,directory:folder),temporary = folder.appending(path:UUID().uuidString+".jpg")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL,UTType.jpeg.identifier as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { try? FileManager.default.removeItem(at:temporary);throw CocoaError(.fileWriteUnknown) }
        _ = try FileManager.default.replaceItemAtIfPresent(target,with:temporary)
        return target
    }
    nonisolated static var directory:URL { URL.documentsDirectory.appending(path:"PaperFlow/GeneratedCovers") }
    nonisolated static func file(_ id:String,directory:URL? = nil) -> URL { (directory ?? Self.directory).appending(path:id+".jpg") }
}

private extension FileManager {
    nonisolated func replaceItemAtIfPresent(_ target:URL,with source:URL) throws -> URL {
        if fileExists(atPath:target.path) { _ = try replaceItemAt(target,withItemAt:source) }
        else { try moveItem(at:source,to:target) }
        return target
    }
}
