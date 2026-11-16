import SwiftUI
import PDFKit
import PhotosUI

/// 原图使用自身比例，不裁切、不补边；只有 AI 生成图和占位区域使用 4:3。
struct PaperCover: View {
    @Environment(AppStore.self) private var store
    var paper:Paper
    @State private var automatic:UIImage?
    @State private var ownImage:UIImage?
    @State private var generated = false
    @State private var preparing = false
    @State private var loadError:String?
    private var input:ImageCoverInput { store.paperImageInput(paper) }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            if let image = ownImage ?? automatic {
                if generated && ownImage == nil {
                    Image(uiImage:image).resizable().aspectRatio(4.0/3.0,contentMode:.fit).frame(maxWidth:.infinity)
                } else {
                    // 不给原图套固定高度；宽图和竖图均完整占据自己的实际高度。
                    Image(uiImage:image).resizable().aspectRatio(image.size.width/image.size.height,contentMode:.fit).frame(maxWidth:.infinity)
                }
            } else {
                Color(.secondarySystemBackground).aspectRatio(4.0/3.0,contentMode:.fit).overlay {
                    if preparing || store.imageActivity.contains(input.cacheID) { ProgressView().tint(.flow) }
                    else { Image(systemName:"photo").flowFont(.title).foregroundStyle(.tertiary) }
                }
            }
            if generated && ownImage == nil && automatic != nil { Text("AI 示意图").flowFont(.subheadline).foregroundStyle(.secondary).padding(.horizontal,8) }
            if ownImage == nil && automatic == nil && !preparing,let hint = store.state.imageGenerations[input.cacheID]?.failureHint ?? loadError {
                Text(hint).flowFont(.subheadline).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal,8)
            }
        }
        .task(id:paper.id + String(store.state.eventCounts["cover_change"] ?? 0) + String(store.state.eventCounts["cover_restore"] ?? 0) + String(store.state.eventCounts["cover_retry"] ?? 0) + String(store.configurationRevision) + String(store.state.imageConfiguration.automatic)) { await load() }
        .onChange(of:store.state.imageGenerations[input.cacheID]?.status) { _,status in if status == "ready" { Task { await loadGenerated() } } }
        .onDisappear { automatic = nil;ownImage = nil }
    }
    private func load() async {
        preparing = true;loadError = nil;defer { preparing = false }
        if let own = store.state.covers[paper.id] {
            ownImage = await ImageLoader.shared.load(key:paper.id+"own"+String(store.state.eventCounts["cover_change"] ?? 0),data:own.image);return
        }
        ownImage = nil
        await PaperArtwork.prepare(paper:paper,url:PaperFileService.localURL(paper))
        guard !Task.isCancelled else { return }
        if let url = PaperArtwork.automaticURL(paper.id) {
            generated = false;automatic = await ImageLoader.shared.load(key:url.path+String(store.state.eventCounts["cover_retry"] ?? 0),url:url);return
        }
        await loadGenerated()
        if automatic == nil,store.state.imageConfiguration.automatic,store.state.imageGenerations[input.cacheID] == nil,store.imageKeyAvailable,(!store.isDemo || store.imageBudget.remaining > 0) {
            do { _ = try await store.generateImage(input) }
            catch { loadError = error.localizedDescription }
            if !Task.isCancelled { await loadGenerated() }
        }
    }
    private func loadGenerated() async {
        // 原图或手选图出现后，迟到的生成结果只缓存，不抢占展示。
        guard store.state.covers[paper.id] == nil,!PaperArtwork.hasOriginal(paper.id) else { return }
        generated = true
        automatic = await ImageLoader.shared.load(key:input.cacheID,url:store.generatedImageURL(input))
    }
}
struct OverviewPager: View {
    @Environment(AppStore.self) private var store
    var paper:Paper
    var reading:GeneratedReading
    @State private var index = 0
    var body: some View {
        let cards = reading.cards ?? []
        if !cards.isEmpty {
            VStack(alignment:.leading,spacing:10) {
                HStack { Text("文献概览").flowFont(.headline); Spacer(); Text("\(index + 1) / \(cards.count)").flowFont(.subheadline) }
                TabView(selection:$index) {
                    ForEach(Array(cards.enumerated()),id:\.offset) { i,card in
                        ScrollView {
                            VStack(alignment:.leading,spacing:16) {
                                Text(card.title).flowFont(.title3,weight:.semibold)
                                Text(card.text).flowFont(.body).lineSpacing(6)
                                if let evidence = card.evidence, !evidence.isEmpty {
                                    DisclosureGroup("查看原文依据") { Text(evidence).flowFont(.body).textSelection(.enabled); Button("打开对应原文") { store.go(.readerPage(paper.id,card.page ?? 1)) } }
                                }
                                if i == 2, let asset = store.state.covers[paper.id], let image = UIImage(data:asset.image) { Image(uiImage:image).resizable().scaledToFit(); Text(asset.caption).flowFont(.subheadline) }
                            }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                        }.background(Color.flow.opacity(0.05),in:RoundedRectangle(cornerRadius:16)).tag(i)
                    }
                }.tabViewStyle(.page(indexDisplayMode:.never)).frame(height:300)
            }
        }
    }
}
struct ExcerptEditor: View {
    @Environment(\.dismiss) private var dismiss
    var image:UIImage
    var page:Int
    var dismissAfterSave = true
    var onSave:(CoverAsset) -> Void
    @State private var rect = CGRect(x:0,y:0,width:1,height:1)
    @State private var start:CGPoint?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("拖动框选原图区域，可保留整页。预览即为保存效果。").flowFont(.body)
                    Image(uiImage:image).resizable().scaledToFit().overlay {
                        GeometryReader { geo in
                            Rectangle().stroke(Color.flow,lineWidth:2).background(Color.flow.opacity(0.06)).frame(width:rect.width * geo.size.width,height:rect.height * geo.size.height).position(x:rect.midX * geo.size.width,y:rect.midY * geo.size.height)
                                .frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance:1).onChanged { value in
                                    if start == nil { start = value.startLocation }
                                    let a = start ?? value.startLocation, b = value.location
                                    rect = CGRect(x:max(0,min(a.x,b.x)/geo.size.width),y:max(0,min(a.y,b.y)/geo.size.height),width:min(1,abs(a.x-b.x)/geo.size.width),height:min(1,abs(a.y-b.y)/geo.size.height))
                                }.onEnded { _ in start = nil })
                        }
                    }
                    Button("使用整页") { rect = CGRect(x:0,y:0,width:1,height:1) }
                    if let preview = cropped {
                        Text("卡片预览").flowFont(.headline)
                        Image(uiImage:preview).resizable().scaledToFit().frame(maxWidth:.infinity)
                    }
                }.padding(18)
            }.navigationTitle("截取原文图片").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement:.confirmationAction) { Button("使用图片") { if let data = cropped?.jpegData(compressionQuality:0.85) { onSave(CoverAsset(image:data,page:page,caption:"论文原文 · PDF 第 \(page) 页",manual:true)); if dismissAfterSave { dismiss() } } }.disabled(rect.width < 0.02 || rect.height < 0.02) } }
        }
    }
    private var cropped:UIImage? {
        guard let cg = image.cgImage else { return nil }
        let area = CGRect(x:rect.minX * CGFloat(cg.width),y:rect.minY * CGFloat(cg.height),width:rect.width * CGFloat(cg.width),height:rect.height * CGFloat(cg.height)).intersection(CGRect(x:0,y:0,width:cg.width,height:cg.height)).integral
        return cg.cropping(to:area).map { UIImage(cgImage:$0) }
    }
}
struct PaperExcerptPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onSave:(String,CoverAsset) -> Void
    var body: some View {
        NavigationStack {
            List { ForEach(store.papers) { paper in NavigationLink(paper.title) { ExcerptPreparation(paper:paper) { asset in onSave(paper.id,asset); dismiss() } } } }
                .navigationTitle("从已获取文献取图").toolbar { Button("取消") { dismiss() } }
        }
    }
}
struct ExcerptPreparation: View {
    var paper:Paper
    var onSave:(CoverAsset) -> Void
    @State private var url:URL?
    @State private var page = 1
    @State private var image:UIImage?
    @State private var error = ""
    var body: some View {
        VStack(spacing:18) {
            if let image { ExcerptEditor(image:image,page:page,onSave:onSave) }
            else { ProgressView(); if !error.isEmpty { Text(error).flowFont(.body) } }
            if let url, let count = PDFDocument(url:url)?.pageCount { Stepper("第 \(page) / \(count) 页",value:$page,in:1...max(1,count)).padding() }
        }.task { do { let file = try await PaperFileService.download(paper); url = file; image = await PaperArtwork.pageImage(url:file,page:page) } catch { self.error = error.localizedDescription } }
            .task(id:page) { if let url { let result = await PaperArtwork.pageImage(url:url,page:page); if !Task.isCancelled { image = result } } }
    }
}

/// 封面只影响本人设备；论文身份与原始文件保持独立。
struct CoverPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var paper:Paper
    @State private var photo:PhotosPickerItem?
    @State private var uploaded:UIImage?
    @State private var fromPaper = false
    @State private var error = ""
    @State private var processing = false
    @State private var rankedFigures:[FigureCandidate] = []
    @State private var automaticAsset:CoverAsset?
    @State private var generating = false
    @State private var request:Task<Void,Never>?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    PaperCover(paper:paper)
                    Text("仅修改你在这台手机上看到的封面。").flowFont(.body).foregroundStyle(.secondary)
                }
                Section("核心图候选") {
                    if rankedFigures.isEmpty { Text("尚未识别到可靠图注，可选择原文页框选。").flowFont(.body) }
                    ForEach(rankedFigures) { figure in
                        VStack(alignment:.leading,spacing:10) {
                            if figure.quality == "ok" || figure.quality == "fallback" {
                                LoadedFigure(paperID:paper.id,figureID:figure.id,revision:store.state.eventCounts["cover_retry"] ?? 0)
                                Text(figure.label + (figure.page > 0 ? " · PDF 第 \(figure.page) 页" : " · 原文网页图片")).flowFont(.headline)
                                DisclosureGroup("图注") { Text(figure.caption).flowFont(.body) }
                                if let source = figure.sourceURL,let url = URL(string:source) { Link("打开原图来源",destination:url).flowFont(.body) }
                                Button("使用这张图") { Task {
                                    let url = PaperArtwork.candidateURL(paper.id,figure:figure.id)
                                    if let data = await Task.detached(priority:.utility,operation:{try? Data(contentsOf:url)}).value { store.setCover(CoverAsset(image:data,page:figure.page,caption:figure.label + (figure.page > 0 ? " · PDF 第 \(figure.page) 页" : " · 原文网页图片"),manual:true),for:paper.id) }
                                } }
                                if figure.page > 0 { Button("对照原文整页") { dismiss(); store.go(.readerPage(paper.id,figure.page)) } }
                            }
                        }
                    }
                    if let choice = PaperArtwork.choice(paper.id) { Text(choice.method + "：" + choice.reason).flowFont(.body).foregroundStyle(.secondary) }
                    Button(generating ? "正在重新提图…" : "重新提取封面") { regenerate() }.disabled(generating)
                    Text("优先使用网页原图，再尝试 PDF 图表；没有合适原图时使用 AI 示意图。重新提图不调用付费模型。").flowFont(.body).foregroundStyle(.secondary)
                }
                Section("AI 示意图") { ImageGenerationControl(input:store.paperImageInput(paper),hasOriginal:PaperArtwork.hasOriginal(paper.id)) }
                Button("选择原文页或截取插图") { fromPaper = true }
                PhotosPicker(selection:$photo,matching:.images) { Label("从相册上传",systemImage:"photo") }
                Section("样式") {
                    Button(processing ? "正在处理…" : "提亮与清晰度优化") { if var asset = currentAsset { processing = true; Task { if let result = await PaperArtwork.brighten(asset.image) { if asset.originalImage == nil { asset.originalImage = asset.image }; asset.image = result; store.setCover(asset,for:paper.id) }; processing = false } } }.disabled(processing || currentAsset == nil)
                    if let asset = currentAsset, asset.originalImage != nil { Button("恢复未优化的图片") { var copy = asset; copy.image = asset.originalImage!; copy.originalImage = nil; store.setCover(copy,for:paper.id) } }
                    Text("黑边可用原文框选工具裁去；保留坐标轴、图例和图号。").flowFont(.body).foregroundStyle(.secondary)
                }
                Button("恢复自动封面") { store.state.covers[paper.id] = nil; store.recordEvent("cover_restore"); dismiss() }
                if !error.isEmpty { Text(error).flowFont(.body) }
            }.navigationTitle("文献封面").toolbar { Button("完成") { dismiss() } }
                .sheet(isPresented:$fromPaper) { ExcerptPreparation(paper:paper) { asset in store.setCover(asset,for:paper.id); fromPaper = false; dismiss() } }
                .sheet(isPresented:Binding(get:{uploaded != nil},set:{if !$0 { uploaded = nil }})) {
                    if let uploaded { ExcerptEditor(image:uploaded,page:0) { asset in var own = asset; own.caption = "本人上传的封面，非论文原始图表"; store.setCover(own,for:paper.id); self.uploaded = nil; dismiss() } }
                }
                .onChange(of:photo) { _,item in Task { do { if let data = try await item?.loadTransferable(type:Data.self), let image = UIImage(data:data) { let ratio = min(1,1600 / max(image.size.width,image.size.height)); let size = CGSize(width:image.size.width * ratio,height:image.size.height * ratio); uploaded = UIGraphicsImageRenderer(size:size).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) } } } catch { self.error = "图片读取失败，请重新选择。" } } }
        }.flowFont(.body)
            .task {
                await PaperArtwork.prepare(paper:paper,url:PaperFileService.localURL(paper))
                reloadFigures();await loadAutomaticAsset()
            }.onDisappear { request?.cancel() }
    }
    private func reloadFigures() {
        let all = PaperArtwork.candidates(paper.id),ids = PaperArtwork.choice(paper.id)?.ids ?? []
        rankedFigures = ids.compactMap { id in all.first { $0.id == id } }
    }
    private func regenerate() {
        generating = true; error = ""
        request = Task { @MainActor in
            await PaperArtwork.prepare(paper:paper,url:PaperFileService.localURL(paper),force:true)
            ImageLoader.shared.clear();store.recordEvent("cover_retry");reloadFigures();await loadAutomaticAsset();generating = false
        }
    }
    private func loadAutomaticAsset() async {
        guard let url = PaperArtwork.automaticURL(paper.id) else { automaticAsset = nil;return }
        let data = await Task.detached(priority:.utility) { try? Data(contentsOf:url) }.value
        automaticAsset = data.map { CoverAsset(image:$0,page:PaperArtwork.candidates(paper.id).first?.page ?? 0,caption:PaperArtwork.credit(paper.id) ?? "原文封面",manual:false) }
    }
    private var currentAsset:CoverAsset? { store.state.covers[paper.id] ?? automaticAsset }
}
