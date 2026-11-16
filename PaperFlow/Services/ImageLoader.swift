import Foundation
import UIKit
import SwiftUI
import ImageIO

/// 卡片只拿解码后的缩略图；不在 SwiftUI body 中同步读取磁盘或解码大图。
@MainActor final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString,UIImage>()
    private var jobs:[String:Task<UIImage?,Never>] = [:]
    init() { cache.totalCostLimit = 40*1024*1024 }
    func clear() { cache.removeAllObjects() }
    func load(key:String,url:URL? = nil,data:Data? = nil) async -> UIImage? {
        if let image = cache.object(forKey:key as NSString) { return image }
        if let job = jobs[key] { return await job.value }
        let job = Task { @MainActor in
            let image = await Task.detached(priority:.utility) { () -> UIImage? in
                guard let bytes = data ?? url.flatMap({try? Data(contentsOf:$0)}),let source = CGImageSourceCreateWithData(bytes as CFData,nil),let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:900,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
                return UIImage(cgImage:cg).preparingForDisplay() ?? UIImage(cgImage:cg)
            }.value
            return image
        }
        jobs[key] = job;let result = await job.value;jobs[key] = nil
        if let result { cache.setObject(result,forKey:key as NSString,cost:Int(result.size.width*result.scale*result.size.height*result.scale*4)) };return result
    }
}
struct LoadedFigure:SwiftUI.View {
    var paperID:String
    var figureID:String
    var revision:Int = 0
    @SwiftUI.State private var image:UIImage?
    var body:some SwiftUI.View {
        SwiftUI.Group { if let image { SwiftUI.Image(uiImage:image).resizable().scaledToFit() } else { SwiftUI.ProgressView() } }
            .task(id:paperID+figureID+String(revision)) { image = await ImageLoader.shared.load(key:paperID+figureID+String(revision),url:PaperArtwork.candidateURL(paperID,figure:figureID)) }.onDisappear { image = nil }
    }
}
