// 本机论坛演示：图文发布、照片选择、关联资料搜索和草稿管理。
import SwiftUI
import PhotosUI
import UIKit

struct PostGallery: View {
    var post: UserPost
    var height: CGFloat?
    private var indices:[Int] { let original = Array(0..<post.imageCount);return post.coverImage == nil ? original : [-1] + (height == nil && post.coverSource == "photo" ? original.filter { $0 != post.coverIndex } : original) }
    @State private var index = 0
    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(indices.enumerated()),id:\.offset) { slot,index in
                Group { if index == -1 { PostThumbnail(post:post) } else { PostImage(post:post,index:index) } }.padding(.bottom,indices.count > 1 ? 26 : 0).tag(slot)
            }
        }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: height).aspectRatio(height == nil ? 4.0/3.0 : nil,contentMode:.fit)
            .background(Color.paperBackground)
            .overlay(alignment: .bottom) {
                if indices.count > 1 {
                    Text("\(index + 1) / \(indices.count)").flowFont(.subheadline, weight: .semibold).padding(.horizontal, 12).padding(.vertical, 6).background(.regularMaterial, in: Capsule()).padding(.bottom, 8)
                }
            }
    }
}

struct PostDetailView: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    var postID: String
    @State private var editing = false
    @State private var deleting = false
    @State private var fullImages = false
    var body: some View {
        Group {
            if let post = store.post(postID) {
                ContentDetailPage(key:"post:" + postID,title:post.title) {
                    if post.imageCount > 0 || post.coverImage != nil {
                        PostGallery(post:post).clipShape(RoundedRectangle(cornerRadius:18)).onTapGesture { fullImages = true }.accessibilityLabel("查看图片，可左右滑动")
                    } else { PostThumbnail(post:post).clipShape(RoundedRectangle(cornerRadius:18)) }
                } identity: {
                    EntityLinkRow(key:"user:" + (post.isMine ? store.state.nickname : post.author),symbol:"person.fill",showFollow:!post.isMine)
                    ForEach(store.journalIDs(for:post).sorted(),id:\.self) { journal in EntityLinkRow(key:"journal:" + journal,symbol:"books.vertical.fill") }
                    ForEach(store.topics(for:post).sorted(),id:\.self) { topic in EntityLinkRow(key:"topic:" + topic,symbol:"number") }
                } article: {
                    if let credits = post.imageCredits { ForEach(Array(Set(credits.filter { !$0.isEmpty })).sorted(),id:\.self) { credit in Text(credit).flowFont(.subheadline).foregroundStyle(.secondary) } }
                    Text(post.body).flowFont(.body).lineSpacing(7).textSelection(.enabled)
                    Text(Date(timeIntervalSince1970:post.timestamp).formatted(date:.abbreviated,time:.shortened)).flowFont(.subheadline).foregroundStyle(.secondary)
                } related: {
                    let links = post.links.filter { !$0.hasPrefix("topic:") && !$0.hasPrefix("journal:") }
                    ForEach(links,id:\.self) { key in EntityLinkRow(key:key,symbol:key.hasPrefix("author:") ? "person.fill" : key.hasPrefix("journal:") ? "books.vertical.fill" : "doc.text.fill") }
                }
                .toolbar {
                    if post.isMine { ToolbarItem(placement:.topBarTrailing) { Menu { Button("编辑") { editing = true }; Button("删除帖子",role:.destructive) { deleting = true } } label: { Image(systemName:"ellipsis") } } }
                }
                .sheet(isPresented:$editing) { ComposerView(post:post) { _ in editing = false } }
                .fullScreenCover(isPresented:$fullImages) { NavigationStack { GeometryReader { geo in PostGallery(post:post,height:geo.size.height) }.navigationTitle("图片").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { fullImages = false } } } } }
                .confirmationDialog("删除这条帖子？",isPresented:$deleting,titleVisibility:.visible) { Button("删除帖子",role:.destructive) { store.deletePost(postID); dismiss() } }
            } else { EmptyHint(title:"帖子已移除",message:"返回后继续发现其他内容。") }
        }
    }
}

struct ComposerView: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var draft: UserPost
    @State private var photos: [PhotosPickerItem] = []
    @State private var associating = false
    @State private var cancelPrompt = false
    @State private var imageError: String?
    @State private var loadingPhotos = false
    @State private var excerptPicking = false
    @State private var consumedExcerpt = false
    @State private var cropping:NoteCoverTarget?
    @State private var generationRevision:String?
    var onSaved: (String?) -> Void
    init(post: UserPost? = nil, onSaved: @escaping (String?) -> Void) {
        _draft = State(initialValue: post ?? UserPost())
        self.onSaved = onSaved
    }
    private var valid: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack {
            Form {
                Section { Button("从论文截取配图") { excerptPicking = true } }
                ReadableSection("图文内容") {
                    TextField("写一个标题", text: $draft.title).flowFont(.headline).accessibilityLabel("帖子标题")
                    TextEditor(text: $draft.body).frame(minHeight: 180).accessibilityLabel("帖子正文")
                    if draft.body.isEmpty { Text("分享阅读心得、研究问题或新的灵感。").flowFont(.subheadline).foregroundStyle(.secondary) }
                }
                ReadableSection("封面 · 4:3 横版") {
                    PostThumbnail(post:draft).clipShape(RoundedRectangle(cornerRadius:14))
                    Text("点击下方任意图片设为封面，原始配图不会被裁切。").foregroundStyle(.secondary)
                    if draft.coverImage != nil {
                        Button("恢复第一张配图作为封面") { draft.coverImage = nil;draft.coverSource = nil;draft.coverIndex = nil;draft.mediaRevision = UUID().uuidString }
                    }
                    ImageGenerationControl(input:store.postImageInput(draft),onStart:{ generationRevision = draft.mediaRevision }) { url in
                        Task {
                            if let data = await Task.detached(priority:.utility,operation:{try? Data(contentsOf:url)}).value {
                                guard url.deletingPathExtension().lastPathComponent == store.postImageInput(draft).cacheID,generationRevision == draft.mediaRevision else {
                                    imageError = "生成期间内容或照片已修改，结果已缓存，可再次点击选择。";return
                                }
                                draft.coverImage = data;draft.coverSource = "ai";draft.coverIndex = nil;draft.mediaRevision = UUID().uuidString
                            }
                        }
                    }
                }
                ReadableSection("图片 · 最多 4 张") {
                    if !draft.images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(draft.images.indices, id: \.self) { index in
                                    if draft.images.indices.contains(index) {
                                        VStack {
                                            PostImage(post:draft,index:index).frame(width: 90, height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                            Button("设为封面") { cropping = NoteCoverTarget(index:index,data:draft.images[index]) }.flowFont(.subheadline).buttonStyle(.borderless)
                                            Button("移除") {
                                                draft.images.remove(at:index)
                                                if let selected = draft.coverIndex {
                                                    if selected == index { draft.coverImage = nil;draft.coverSource = nil;draft.coverIndex = nil }
                                                    else if selected > index { draft.coverIndex = selected-1 }
                                                }
                                                draft.mediaRevision = UUID().uuidString
                                                if draft.imageCredits?.indices.contains(index) == true { draft.imageCredits?.remove(at:index) }
                                            }.flowFont(.subheadline).buttonStyle(.borderless)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $photos, maxSelectionCount: max(1, 4 - draft.images.count), matching: .images) {
                        Label("从相册添加图片", systemImage: "photo.badge.plus")
                    }.disabled(draft.images.count >= 4 || loadingPhotos)
                    if loadingPhotos { ProgressView("正在添加图片…") }
                    if let imageError { Text(imageError).flowFont(.subheadline).foregroundStyle(.red) }
                }
                ReadableSection("关联资料") {
                    ForEach(draft.links, id: \.self) { key in
                        HStack { Text(store.label(key)).flowFont(.subheadline); Spacer(); Button { draft.links.removeAll { $0 == key } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless) }
                    }
                    Button { associating = true } label: { Label("搜索关联资料", systemImage: "magnifyingglass") }
                }
                Section {
                    Button("保存为草稿") { save(isDraft: true) }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingPhotos)
                }
                Section { Text("发布内容仅保存在这台手机。").flowFont(.body).foregroundStyle(.secondary) }
            }
            .navigationTitle(draft.isDraft ? "继续编辑草稿" : "发布图文").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { if draft.title.isEmpty && draft.body.isEmpty && draft.images.isEmpty && draft.coverImage == nil { dismiss() } else { cancelPrompt = true } } }
                ToolbarItem(placement: .confirmationAction) { Button("发布") { save(isDraft: false) }.fontWeight(.semibold).disabled(!valid || loadingPhotos) }
            }
            .interactiveDismissDisabled(!draft.title.isEmpty || !draft.body.isEmpty || !draft.images.isEmpty || draft.coverImage != nil || loadingPhotos)
            .onAppear {
                if !consumedExcerpt, let image = store.pendingExcerpt, let id = store.excerptPaperID { appendExcerpt(id,image); consumedExcerpt = true; store.pendingExcerpt = nil; store.excerptPaperID = nil }
            }
            .sheet(item:$cropping) { target in NoteCoverCropView(target:target) { data,index in draft.coverImage = data;draft.coverIndex = index;draft.coverSource = "photo";draft.mediaRevision = UUID().uuidString } }
            .sheet(isPresented:$excerptPicking) { PaperExcerptPicker { id,asset in appendExcerpt(id,asset) } }
            .sheet(isPresented: $associating) { AssociationPicker(selection: $draft.links) }
            .confirmationDialog("保留这次编辑吗？", isPresented: $cancelPrompt, titleVisibility: .visible) {
                Button("保存为草稿") { save(isDraft: true) }.disabled(draft.title.isEmpty)
                Button("放弃本次编辑", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) { }
            }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty && !loadingPhotos else { return }
                loadingPhotos = true
                Task {
                    defer { loadingPhotos = false }
                    imageError = nil
                    for item in items.prefix(max(0, 4 - draft.images.count)) {
                        do {
                            guard let data = try await item.loadTransferable(type:Data.self),let compressed = await NotePhotoService.prepare(data) else { imageError = "有一张图片无法读取，请换一张。";continue }
                            if draft.images.count < 4 { draft.images.append(compressed);syncCredits();draft.imageCredits?[draft.images.count-1] = "";draft.mediaRevision = UUID().uuidString }
                        } catch { imageError = "图片加载失败，可以重试。" }
                    }
                    photos = []
                }
            }
        }
    }
    private func syncCredits() {
        var values = draft.imageCredits ?? []; while values.count < draft.images.count { values.append("") }; draft.imageCredits = values
    }
    private func appendExcerpt(_ id:String,_ asset:CoverAsset) {
        guard draft.images.count < 4 else { return }; draft.images.append(asset.image); syncCredits()
        draft.imageCredits?[draft.images.count - 1] = (store.paper(id)?.title ?? id) + " · " + asset.caption
        draft.links = Array(Set(draft.links + ["paper:" + id])); store.recordEvent("note_excerpt")
    }
    private func save(isDraft: Bool) {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.author = store.state.nickname; draft.isMine = true; draft.isDraft = isDraft
        draft.timestamp = Date().timeIntervalSince1970
        store.savePost(draft)
        let id = draft.id
        dismiss(); onSaved(isDraft ? nil : id)
    }
}

struct AssociationPicker: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    @Binding var selection: [String]
    @State private var query = ""
    private var results: [FeedItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return store.content(query: query, includeEntities: true).filter { if case .post = $0 { return false }; return true }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("论文、学者、主题或期刊", text: $query).flowFont(.body).submitLabel(.search) }
                    Text("只搜索本机资料，包括已检索或下载的在线论文；这里不直接联网检索。").flowFont(.body).foregroundStyle(.secondary)
                }
                if !selection.isEmpty {
                    Section { ForEach(selection, id: \.self) { key in row(key, title: store.label(key)) } } header: { Text("已关联").flowFont(.headline) }
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入关键词查找资料，例如 RAG、交互设计或 Nature。").flowFont(.body).foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("本机没有找到相关资料，可先在统一搜索中检索并打开，再回来关联。").flowFont(.body).foregroundStyle(.secondary)
                } else if results.contains(where: { !selection.contains($0.id) }) {
                    Section {
                        ForEach(results.filter { !selection.contains($0.id) }) { item in row(item.id, title: store.label(item.id)) }
                    } header: { Text("搜索结果").flowFont(.headline) }
                }
            }.scrollDismissesKeyboard(.interactively)
                .navigationTitle("搜索关联资料").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func row(_ key: String, title: String) -> some View {
        Button {
            if selection.contains(key) { selection.removeAll { $0 == key } } else { selection.append(key) }
        } label: { HStack { Text(title).flowFont(.body).foregroundStyle(.primary); Spacer(); Image(systemName: selection.contains(key) ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(Color.flow) }.frame(minHeight: 44) }
    }
}
