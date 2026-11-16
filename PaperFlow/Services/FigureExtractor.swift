import Foundation
import PDFKit
import CryptoKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// 扫描图注，再按图注锚点取图。没有可信图注时不截取任意正文区域。
enum FigureExtractor {
    nonisolated static func folder(_ id:String,directory:URL? = nil) -> URL { (directory ?? URL.documentsDirectory.appending(path:"PaperFlow/Figures")).appending(path:PaperIdentity.stableID("fig",id)) }
    nonisolated static func imageURL(_ id:String,candidate:String,directory:URL? = nil) -> URL { folder(id,directory:directory).appending(path:PaperIdentity.stableID("image",candidate) + ".jpg") }
    nonisolated static func list(paper:Paper,url:URL) async -> [FigureCandidate] {
        await Task.detached(priority:.utility) {
            guard let document = PDFDocument(url:url) else { return [] }
            let regex = try! NSRegularExpression(pattern:#"(?im)^[\t ]*((?:Figure|Fig\.?|图)\s*\d+[a-z]?)[\t ]*[.:：|][^\n]*"#)
            var found:[FigureCandidate] = [], labels:Set<String> = []
            for index in 0..<min(document.pageCount,60) {
                if Task.isCancelled { break }
                guard let page = document.page(at:index),let text = page.string else { continue }
                for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)) {
                    guard let range = Range(match.range,in:text), let labelRange = Range(match.range(at:1),in:text) else { continue }
                    let label = String(text[labelRange]).trimmingCharacters(in:.whitespacesAndNewlines)
                    let labelKey = label.lowercased().replacingOccurrences(of:" ",with:"")
                    guard labels.insert(labelKey).inserted else { continue }
                    let first = String(text[range]).trimmingCharacters(in:.whitespacesAndNewlines)
                    // 排除正文中单独引用 Figure 2 的句子；图注至少包含说明文字。
                    guard first.count > label.count + 8 else { continue }
                    guard let selection = page.selection(for:match.range) else { continue }
                    let bounds = page.bounds(for:.mediaBox), anchor = selection.bounds(for:page)
                    let caption = captionText(text: text, match: match, page: page)
                    let x = max(0,min(1,(anchor.minX - bounds.minX)/bounds.width))
                    let y = max(0,min(1,1 - (anchor.maxY - bounds.minY)/bounds.height))
                    let width = min(1,anchor.width/bounds.width)
                    let score = FigureRanking.score(caption:caption,title:paper.title,abstract:paper.abstractText ?? "",page:index+1,label:label)
                    found.append(FigureCandidate(id:"p\(index+1)-" + labelKey,page:index+1,label:label,caption:caption,anchorX:x,anchorY:y,anchorWidth:width,score:score))
                }
            }
            return Array(FigureRanking.ordered(found).prefix(24))
        }.value
    }
    nonisolated static func render(paperID:String,candidates:[FigureCandidate],ids:[String],url:URL,directory:URL? = nil,title:String = "") async {
        await Task.detached(priority:.utility) {
            guard let document = PDFDocument(url:url) else { return }
            let destination = folder(paperID,directory:directory)
            try? FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            var rendered = candidates
            for id in ids.prefix(3) {
                if Task.isCancelled { return }
                guard let figure = candidates.first(where:{$0.id == id}), let page = document.page(at:figure.page-1) else { continue }
                let thumbnail = page.thumbnail(of:CGSize(width:1400,height:1900),for:.mediaBox)
                #if canImport(UIKit)
                guard let cg = thumbnail.cgImage else { continue }
                #else
                guard let cg = thumbnail.cgImage(forProposedRect:nil,context:nil,hints:nil) else { continue }
                #endif
                let region = crop(figure:figure,all:candidates,cg:cg,page:page,title:title)
                guard let image = cg.cropping(to:region) else { continue }
                if let index = rendered.firstIndex(where:{$0.id == id}) {
                    rendered[index].bounds = [region.minX/Double(cg.width),region.minY/Double(cg.height),region.width/Double(cg.width),region.height/Double(cg.height)]
                    let pageBounds = page.bounds(for:.mediaBox)
                    let pdfBox = CGRect(x:pageBounds.minX+region.minX/Double(cg.width)*pageBounds.width,y:pageBounds.maxY-region.maxY/Double(cg.height)*pageBounds.height,width:region.width/Double(cg.width)*pageBounds.width,height:region.height/Double(cg.height)*pageBounds.height)
                    let text = page.selection(for:pdfBox)?.string ?? ""
                    let prose = text.components(separatedBy:.newlines).filter { $0.count > 22 && $0.split(whereSeparator:{$0.isWhitespace}).filter { $0.contains(where:{$0.isLetter}) }.count >= 4 }
                    rendered[index].quality = prose.count >= 6 ? "suspect" : "ok"
                }
                #if canImport(UIKit)
                let data = UIImage(cgImage:image).jpegData(compressionQuality:0.9)
                #else
                let data = NSBitmapImageRep(cgImage:image).representation(using:.jpeg,properties:[.compressionFactor:0.9])
                #endif
                if let data { try? data.write(to:imageURL(paperID,candidate:id,directory:directory),options:.atomic) }
            }
            try? JSONEncoder().encode(rendered).write(to:destination.appending(path:"candidates.json"),options:.atomic)
        }.value
    }
    private nonisolated static func crop(figure:FigureCandidate,all:[FigureCandidate],cg:CGImage,page:PDFPage,title:String) -> CGRect {
        let width = Double(cg.width),height = Double(cg.height)
        // 短而居中的图注也可能对应通栏图；不能仅凭图注宽度截掉右半边。
        let crossesCenter = figure.anchorX < 0.48 && figure.anchorX + figure.anchorWidth > 0.52
        let fullWidth = figure.anchorWidth > 0.35 || crossesCenter
        let left = fullWidth ? (figure.anchorWidth > 0.55 ? max(0.04,figure.anchorX-0.02) : 0.08) : figure.anchorX < 0.45 ? 0.04 : 0.51
        let right = fullWidth ? (figure.anchorWidth > 0.55 ? min(0.96,figure.anchorX+figure.anchorWidth+0.02) : 0.92) : figure.anchorX < 0.45 ? 0.49 : 0.96
        let captionY = figure.anchorY
        let prior = all.filter { $0.page == figure.page && $0.id != figure.id && $0.anchorY < captionY && (fullWidth || abs($0.anchorX - figure.anchorX) < 0.35) }.map(\.anchorY).max() ?? 0.03
        let bodyEnd = bodyBoundary(page:page,left:left,right:right,before:captionY)
        let pageBounds = page.bounds(for:.mediaBox)
        let headerEnd = (page.selection(for:pageBounds)?.selectionsByLine() ?? []).filter { selection in
            guard !title.isEmpty,let text = selection.string else { return false }
            let r = selection.bounds(for:page)
            return 1-r.maxY/pageBounds.height < 0.12 && PaperIdentity.normalized(text).contains(PaperIdentity.normalized(title))
        }.map { 1-$0.bounds(for:page).minY/pageBounds.height }.max() ?? 0
        let top = min(captionY-0.06,max(prior + 0.02,bodyEnd + 0.008,headerEnd+0.008))
        let box = CGRect(x:left * width,y:top * height,width:(right-left) * width,height:max(0.06,captionY-top-0.006) * height).intersection(CGRect(x:0,y:0,width:width,height:height)).integral
        return trimWhitespace(cg:cg,box:box)
    }
    /// 用连续长正文行定位插图上方的段落。图内短标签不当成正文；不限制大图高度。
    private nonisolated static func bodyBoundary(page:PDFPage,left:Double,right:Double,before:Double) -> Double {
        let bounds = page.bounds(for:.mediaBox)
        let lines = (page.selection(for:bounds)?.selectionsByLine() ?? []).compactMap { selection -> (CGRect,String)? in
            guard let text = selection.string else { return nil }
            let r = selection.bounds(for:page)
            let box = CGRect(x:(r.minX-bounds.minX)/bounds.width,y:1-(r.maxY-bounds.minY)/bounds.height,width:r.width/bounds.width,height:r.height/bounds.height)
            let region = CGRect(x:left,y:0,width:right-left,height:before)
            guard box.maxY < before-0.018,box.height < 0.035,box.width > 0,box.intersection(region).width/box.width > 0.8 else { return nil }
            return (box,text)
        }.sorted { $0.0.minY < $1.0.minY }
        func isBody(_ line:(CGRect,String)) -> Bool {
            line.0.width > (right-left)*0.6 && line.1.count >= 50 && line.1.split { !$0.isLetter }.filter { $0.count > 1 }.count >= 8
        }
        var end = 0.03
        for (index,line) in lines.enumerated() where isBody(line) {
            let nearby = lines.enumerated().contains { other in other.offset != index && isBody(other.element) && abs(other.element.0.minY-line.0.minY) < 0.035 && abs(other.element.0.minY-line.0.minY) > 0.006 && abs(other.element.0.minX-line.0.minX) < 0.04 }
            guard nearby else { continue };end = max(end,line.0.maxY)
            // 段落末行常较短，只接纳紧挨正文且字号/高度相近的一行。
            if lines.indices.contains(index+1) {
                let next = lines[index+1]
                if next.0.minY-line.0.maxY < 0.014 && abs(next.0.minX-line.0.minX) < 0.04 && abs(next.0.height-line.0.height) < 0.003 { end = max(end,next.0.maxY) }
            }
        }
        return end
    }
    /// 裁切后只去掉外缘空白，保留同一图中的所有子图、箭头和文字。
    private nonisolated static func trimWhitespace(cg:CGImage,box:CGRect) -> CGRect {
        guard let part = cg.cropping(to:box) else { return box }
        let w = part.width,h = part.height
        var pixels = [UInt8](repeating:255,count:w*h*4)
        let context = CGContext(data:&pixels,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context else { return box }; context.draw(part,in:CGRect(x:0,y:0,width:w,height:h))
        var minX = w,minY = h,maxX = 0,maxY = 0
        for y in 0..<h { for x in 0..<w {
            let i = (y*w+x)*4
            if min(pixels[i],pixels[i+1],pixels[i+2]) < 225 && pixels[i+3] > 128 {
                minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
            }
        } }
        guard maxX > minX && maxY > minY else { return box }
        // 位图数据与 CGImage 裁切同以顶边为起点。
        return CGRect(x:box.minX + Double(minX)-8,y:box.minY + Double(minY)-8,width:Double(maxX-minX+17),height:Double(maxY-minY+17)).intersection(box).integral
    }
    private nonisolated static func captionText(text:String,match:NSTextCheckingResult,page:PDFPage) -> String {
        let source = text as NSString
        let tail = source.substring(from:match.range.location).prefix(1200)
        var offset = match.range.location,parts:[String] = []
        var previous:CGRect?,captionSize:CGFloat?
        for line in tail.components(separatedBy:"\n").prefix(9) {
            let length = (line as NSString).length
            defer { offset += length + 1 }
            let clean = line.trimmingCharacters(in:.whitespaces)
            if !parts.isEmpty && (clean.isEmpty || clean.range(of:#"^(Figure|Fig\.?|Table|References|\d+(?:\.\d+)*[.\t ])"#,options:[.regularExpression,.caseInsensitive]) != nil) { break }
            guard length > 0,offset+length <= source.length,let selection = page.selection(for:NSRange(location:offset,length:length)) else { break }
            let attributes = selection.attributedString
            #if canImport(UIKit)
            let font = attributes.flatMap { $0.length > 0 ? $0.attribute(.font,at:0,effectiveRange:nil) as? UIFont : nil }
            #else
            let font = attributes.flatMap { $0.length > 0 ? $0.attribute(.font,at:0,effectiveRange:nil) as? NSFont : nil }
            #endif
            let bounds = selection.bounds(for:page)
            if let size = captionSize,let font,abs(font.pointSize-size) > 0.45 { break }
            if let previous,let size = captionSize,previous.minY-bounds.maxY > size * 0.9 { break }
            if captionSize == nil { captionSize = font?.pointSize }
            previous = bounds;parts.append(clean)
        }
        return String(parts.joined(separator:" ").prefix(800))
    }
}
