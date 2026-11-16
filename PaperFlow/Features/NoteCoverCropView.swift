import SwiftUI
import UIKit
import ImageIO

enum NotePhotoService {
    nonisolated static func prepare(_ data:Data) async -> Data? {
        await Task.detached(priority:.userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData,nil),let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
            return UIImage(cgImage:cg).jpegData(compressionQuality:0.85)
        }.value
    }
}

struct NoteCoverTarget: Identifiable {
    var id = UUID()
    var index:Int
    var data:Data
}

/// 只保存裁切后的封面副本，笔记原照片仍可完整查看。
struct NoteCoverCropView: View {
    @Environment(\.dismiss) private var dismiss
    let target:NoteCoverTarget
    var onSave:(Data,Int) -> Void
    @State private var image:UIImage?
    @State private var zoom = 1.0
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var start:CGSize?
    var body: some View {
        NavigationStack {
            VStack(spacing:22) {
                if let image {
                    GeometryReader { geo in
                        let rect = drawingRect(image.size,canvas:geo.size)
                        Image(uiImage:image).resizable().frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
                            .frame(width:geo.size.width,height:geo.size.height).clipped().contentShape(Rectangle())
                            .gesture(DragGesture().onChanged { value in
                                if start == nil { start = CGSize(width:x,height:y) }
                                let dx = max(0,(rect.width-geo.size.width)/2),dy = max(0,(rect.height-geo.size.height)/2)
                                x = min(1,max(-1,(start?.width ?? 0)+(dx > 0 ? value.translation.width/dx : 0)))
                                y = min(1,max(-1,(start?.height ?? 0)+(dy > 0 ? value.translation.height/dy : 0)))
                            }.onEnded { _ in start = nil })
                    }.aspectRatio(4.0/3.0,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:18))
                    Text("拖动调整位置，滑动调整大小。原照片保持完整。").flowFont(.body)
                    HStack { Image(systemName:"minus.magnifyingglass");Slider(value:$zoom,in:1...3);Image(systemName:"plus.magnifyingglass") }
                    Button("居中显示") { zoom = 1;x = 0;y = 0 }
                } else { ProgressView() }
                Spacer()
            }.padding(20).navigationTitle("调整笔记封面").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("使用封面") {
                        guard let image else { return }
                        let size = CGSize(width:1200,height:900)
                        let format = UIGraphicsImageRendererFormat();format.scale = 1;format.opaque = true
                        let output = UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:drawingRect(image.size,canvas:size)) }
                        if let data = output.jpegData(compressionQuality:0.88) { onSave(data,target.index);dismiss() }
                    }.disabled(image == nil) }
                }
                .task { image = await ImageLoader.shared.load(key:target.id.uuidString,data:target.data) }
        }.flowFont(.body)
    }
    private func drawingRect(_ size:CGSize,canvas:CGSize) -> CGRect {
        let scale = max(canvas.width/size.width,canvas.height/size.height)*zoom
        let width = size.width*scale,height = size.height*scale
        return CGRect(x:(canvas.width-width)/2+x*max(0,(width-canvas.width)/2),y:(canvas.height-height)/2+y*max(0,(height-canvas.height)/2),width:width,height:height)
    }
}
