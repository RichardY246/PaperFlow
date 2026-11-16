import SwiftUI
import PhotosUI
import ImageIO

/// 系统相册选择器只交付用户选中的照片，不需要读取整个相册。
struct AvatarPhotoPicker: View {
    @Binding var photo: Data?
    var symbol: String
    var size: CGFloat = 76
    @State private var selection: PhotosPickerItem?
    @State private var image: SelectedAvatar?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $selection, matching: .images) {
                VStack(spacing: 10) {
                    Avatar(size: size, symbol: symbol, photo: photo)
                    Text(loading ? "正在读取照片…" : "从相册更换头像").flowFont(.body)
                }
            }.disabled(loading).accessibilityIdentifier("choose-avatar-photo")
            if photo != nil { Button("恢复默认头像") { photo = nil }.flowFont(.body) }
        }.frame(maxWidth: .infinity)
            .task(id: selection) {
                guard let selection else { return }
                loading = true
                defer { loading = false }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 2048
                          ] as CFDictionary) else {
                        throw ServiceError.message("这张照片无法读取，请换一张。")
                    }
                    try Task.checkCancellation()
                    image = SelectedAvatar(image: UIImage(cgImage: thumbnail))
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription; self.selection = nil }
            }
            .sheet(item: $image, onDismiss: { selection = nil }) { selected in AvatarCropView(image: selected.image) { photo = $0 } }
            .alert("照片未能载入", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) { }
            } message: { Text(error ?? "") }
    }
}

private struct SelectedAvatar: Identifiable { let id = UUID(); let image: UIImage }

/// 预览与最终裁剪采用同一套缩放和偏移，避免“预览正常，保存后偏了”。
struct AvatarCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    var onSave: (Data) -> Void
    @State private var zoom: CGFloat = 1
    @State private var position = CGSize.zero
    @GestureState private var dragging = CGSize.zero
    @State private var error = false
    private let side: CGFloat = 280
    private var scale: CGFloat { max(side / image.size.width, side / image.size.height) * zoom }
    private func bounded(_ offset: CGSize) -> CGSize {
        let x = max(0, (image.size.width * scale - side) / 2)
        let y = max(0, (image.size.height * scale - side) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text("拖动照片，调整头像位置").flowFont(.body)
                let offset = bounded(CGSize(width: position.width + dragging.width, height: position.height + dragging.height))
                Image(uiImage: image).resizable().frame(width: image.size.width * scale, height: image.size.height * scale)
                    .offset(offset).frame(width: side, height: side).clipped()
                    .overlay { Circle().strokeBorder(.white, lineWidth: 3).padding(1) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture().updating($dragging) { value, state, _ in state = value.translation }
                        .onEnded { value in position = bounded(CGSize(width: position.width + value.translation.width, height: position.height + value.translation.height)) })
                HStack { Image(systemName: "minus.magnifyingglass"); Slider(value: $zoom, in: 1...4); Image(systemName: "plus.magnifyingglass") }
                    .padding(.horizontal, 28).accessibilityLabel("头像缩放")
                Spacer()
            }.padding(.top, 32).navigationTitle("裁剪头像").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("使用照片") { save() }.accessibilityIdentifier("save-avatar-crop") }
                }
                .onChange(of: zoom) { _, _ in position = bounded(position) }
                .alert("照片保存失败，请换一张照片。", isPresented: $error) { Button("知道了", role: .cancel) { } }
        }
    }
    private func save() {
        let offset = bounded(position)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let output = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
            let factor: CGFloat = 512 / side
            let width = image.size.width * scale * factor, height = image.size.height * scale * factor
            image.draw(in: CGRect(x: (512 - width) / 2 + offset.width * factor, y: (512 - height) / 2 + offset.height * factor, width: width, height: height))
        }
        guard let data = output.jpegData(compressionQuality: 0.85) else { error = true; return }
        onSave(data); dismiss()
    }
}
