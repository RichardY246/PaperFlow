// 文献阅读：展示引流标题与首句澄清，打开原文、AI 助手和私人笔记。
import SwiftUI
import SafariServices
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

struct PaperDetailView: View {
    @Environment(AppStore.self) var store
    let snapshot: Paper
    @State private var note = false
    @State private var browser: BrowserDestination?
    @State private var resolving = false
    @State private var resolutionMessage: String?
    @State private var choosingCover = false
    init(paper:Paper) { snapshot = paper }
    private var paper: Paper { store.paper(snapshot.id) ?? snapshot }
    private var generated: GeneratedReading? { store.reading(paper.id) }
    var body: some View {
        ContentDetailPage(key:"paper:" + paper.id,title:store.displayTitle(paper)) {
            PaperCover(paper:paper).clipShape(RoundedRectangle(cornerRadius:18))
        } identity: {
            EntityLinkRow(key:"author:" + paper.author,symbol:"person.fill")
            EntityLinkRow(key:"journal:" + paper.journalID,symbol:"books.vertical.fill")
            ForEach(paper.topics,id:\.self) { topic in EntityLinkRow(key:"topic:" + topic,symbol:"number") }
        } article: {
            if let generated {
                OverviewPager(paper:paper,reading:generated)
                Text("标题说明：" + generated.clarification).flowFont(.body,weight:.medium).lineSpacing(6)
                Button { store.go(.reader(paper.id)) } label: { Text(generated.body).flowFont(.body).lineSpacing(7) }.buttonStyle(.plain).multilineTextAlignment(.leading)
                UsageLabel(usage:generated.usage)
                Text(generated.sourceLabel + " · " + (generated.language ?? "简体中文")).flowFont(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("这篇文献的\(store.state.targetLanguage)解读尚未生成，可在阅读助手中生成。").flowFont(.body)
                if let message = store.aiErrors[paper.id + "|" + store.state.targetLanguage] { Text(message).flowFont(.body).foregroundStyle(.secondary) }
            }
            HStack {
                Button("阅读原文") { store.go(.reader(paper.id)) }.buttonStyle(.borderedProminent)
                Button { store.go(.aiReading(paper.id)) } label: { Label("AI 解读与提问",systemImage:"sparkles") }.buttonStyle(.bordered).accessibilityIdentifier("open-ai-reading")
            }.flowFont(.body)
            HStack {
                Button { store.toggleRead(paper.id) } label: { Label(store.isRead(paper.id) ? "今天已读过" : "标记读过",systemImage:store.isRead(paper.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.bordered)
                Spacer(minLength:0); Button("写笔记") { note = true }.buttonStyle(.bordered)
            }.flowFont(.body)
        } related: {
            if !PaperArtwork.hasOriginal(paper.id),store.state.covers[paper.id] == nil,store.generatedImageURL(store.paperImageInput(paper)) != nil { Text("AI 示意图，仅表达研究主题，不是原论文图表。").flowFont(.subheadline).foregroundStyle(.secondary) }
            if let credit = store.state.covers[paper.id]?.caption ?? PaperArtwork.credit(paper.id) { Text(credit + " · 仅供学习交流").flowFont(.subheadline).foregroundStyle(.secondary) }
            if let choice = PaperArtwork.choice(paper.id),!choice.ids.isEmpty { Text(choice.method + "：" + choice.reason).flowFont(.body).foregroundStyle(.secondary) }
            Button("封面与核心图候选") { choosingCover = true }
            DisclosureGroup("原标题与资料") {
                Text(paper.title).flowFont(.body).textSelection(.enabled)
                Text("\(paper.year) · " + (paper.retrievalSources ?? ["本机"]).joined(separator:" / ")).flowFont(.body).foregroundStyle(.secondary)
                if let abstract = paper.abstractText { Text(abstract).flowFont(.body).textSelection(.enabled) }
                if let doi = paper.doi { Text("DOI: " + doi).flowFont(.body).textSelection(.enabled) }
            }
            if let url = URL(string:paper.sourceURL) { Button("发布页 / 登录后访问") { open(url) }.buttonStyle(.bordered) }
            ForEach(Array((paper.versions ?? []).enumerated()),id:\.offset) { _,version in
                if let url = URL(string:version.url) { Button(version.label + (version.isOpen ? " · 开放版本" : " · 可能需授权")) { open(url) }.flowFont(.body) }
            }
            if !FullTextLinks.isVerified(paper) {
                Button(resolving ? "正在查找开放版本…" : "查找开放全文") {
                    resolving = true; resolutionMessage = nil
                    Task { @MainActor in
                        defer { resolving = false }
                        do {
                            _ = try await store.obtainFullText(paper.id)
                            resolutionMessage = "已取得开放原文，可直接阅读。"
                        } catch { resolutionMessage = error.localizedDescription }
                    }
                }.disabled(resolving)
            }
            if let resolutionMessage { Text(resolutionMessage).flowFont(.body) }
            Button("账号与机构访问") { store.go(.libraries) }.flowFont(.body)
        }
        .sheet(isPresented:$note) { NoteEditor(paperID:paper.id) }
        .sheet(isPresented:$choosingCover) { CoverPicker(paper:paper) }
        .sheet(item:$browser) { InAppLibraryBrowser(destination:$0) }
        .onAppear { store.visit(paper.id) }
        .modifier(ReadingTimer(paperID:paper.id))
    }
    private func open(_ url:URL) { browser = BrowserDestination(url:url,profile:LibrarySite.profile(for:url),paperID:paper.id) }
}

struct SourceView: View {
    @Environment(AppStore.self) var store
    var paper: Paper
    var index: Int
    var body: some View {
        ScrollView {
            if paper.insights.indices.contains(index) {
                let insight = paper.insights[index]
                VStack(alignment: .leading, spacing: 24) {
                    Text(insight.text).flowFont(.body).lineSpacing(7)
                    Divider()
                    Text(insight.source).flowFont(.body).lineSpacing(7).textSelection(.enabled)
                    Text(insight.location).flowFont(.subheadline).foregroundStyle(.secondary)
                    Button("打开对应原文") { store.go(.readerPage(paper.id, insight.page ?? 1)) }.flowFont(.body).buttonStyle(.borderedProminent)
                }.padding(20)
            }
        }.navigationTitle("原文出处").navigationBarTitleDisplayMode(.inline)
    }
}

struct ReaderView: View {
    @Environment(AppStore.self) var store
    var paper: Paper
    var initialPage = 1
    @State private var textMode = false
    @State private var cropping = false
    @State private var excerptImage:UIImage?
    @State private var online = false
    @State private var page = 1
    @State private var totalPages = 0
    @State private var targetPage = 1
    @State private var jumping = false
    @State private var pageText = ""
    @State private var fileURL: URL?
    @State private var loading = false
    @State private var downloadError: String?
    @State private var download: Task<Void, Never>?
    @State private var importing = false
    @State private var importURL:URL?
    @State private var confirmingImport = false
    @State private var importFailure:String?
    private var localURL: URL? { fileURL ?? PaperFileService.localURL(paper) }
    var body: some View {
        Group {
            if let localURL {
                if textMode { PageTextReadingView(paper:paper,url:localURL,page:page) }
                else { PDFReader(url: localURL, initialPage: targetPage, page: $page, totalPages: $totalPages).id(targetPage) }
            } else {
                VStack(spacing: 20) {
                    if loading { ProgressView("正在下载原文…"); Button("取消下载") { download?.cancel() } }
                    else {
                        Image(systemName: "doc.text").font(.system(size: 42)).foregroundStyle(Color.flow)
                        Text(downloadError ?? "联网下载原文后，可在本机离线阅读。").flowFont(.body).multilineTextAlignment(.center)
                        Button("下载原文") { startDownload() }.buttonStyle(.borderedProminent)
                    }
                    Button("打开在线原文") { online = true }.buttonStyle(.bordered)
                    Button("机构与文献库入口") { store.go(.libraries) }
                    Button("导入已下载的 PDF") { importing = true }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.navigationTitle("原文").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button(textMode ? "PDF 原文" : "衬线阅读与翻译") { textMode.toggle() }
                    Button("截取插图 / 设为封面") { if let localURL { Task { excerptImage = await PaperArtwork.pageImage(url:localURL,page:page); cropping = excerptImage != nil; store.recordEvent("reader_excerpt") } } }.disabled(localURL == nil)
                    Button("查看在线来源") { online = true }
                    Button("导入已下载的 PDF") { importing = true }
                } label: { Image(systemName:"ellipsis.circle") }
            } }
            .safeAreaInset(edge: .bottom) {
                if localURL != nil {
                    HStack {
                        Button { pageText = String(page); jumping = true } label: { Text("\(page) / \(max(totalPages, 1)) 页").flowFont(.body).frame(minHeight: 44) }
                        if textMode {
                            Button("上一页") { page = max(1,page - 1) }
                            Button("下一页") { page = min(max(totalPages,1),page + 1) }
                        }
                        Spacer()
                        Button { store.toggleRead(paper.id) } label: { Label(store.isRead(paper.id) ? "已读过" : "标记读过", systemImage: store.isRead(paper.id) ? "checkmark.circle.fill" : "circle") }.flowFont(.body)
                    }.padding(.horizontal, 18).background(.regularMaterial)
                }
            }
            .alert("跳转页码", isPresented: $jumping) {
                TextField("页码", text: $pageText).keyboardType(.numberPad)
                Button("前往") { if let number = Int(pageText) { targetPage = min(max(number, 1), max(totalPages, 1)); page = targetPage } }
                Button("取消", role: .cancel) { }
            }
            .sheet(isPresented:$online,onDismiss:{ fileURL = PaperFileService.localURL(paper); store.recordCachedFullText(paper.id) }) { if let url = URL(string:paper.openHTMLURL ?? paper.sourceURL) { InAppLibraryBrowser(destination:BrowserDestination(url:url,profile:LibrarySite.profile(for:url),paperID:paper.id)) } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf]) { result in
                do { importURL = try result.get(); confirmingImport = true } catch { downloadError = error.localizedDescription }
            }
            .confirmationDialog("将这个 PDF 关联到当前论文？",isPresented:$confirmingImport,titleVisibility:.visible) {
                Button("确认导入") {
                    guard let url = importURL else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do { fileURL = try store.importFullText(paper.id,from:url); totalPages = fileURL.flatMap { PDFDocument(url:$0)?.pageCount } ?? 0; downloadError = nil }
                    catch { importFailure = error.localizedDescription }
                }
            } message: { Text(paper.title + "\n" + (importURL?.lastPathComponent ?? "")) }
            .alert("导入失败",isPresented:Binding(get:{importFailure != nil},set:{if !$0 {importFailure = nil}})) { Button("好") { importFailure = nil } } message: { Text(importFailure ?? "") }
            .onAppear { targetPage = initialPage == 1 ? (store.state.readerPositions[paper.id] ?? 1) : initialPage; page = targetPage; store.visit(paper.id); if localURL == nil { startDownload() } }
            .sheet(isPresented:$cropping) { if let excerptImage { ExcerptActions(paper:paper,image:excerptImage,page:page) } }
            .onChange(of:page) { _,value in store.state.readerPositions[paper.id] = value }
            .onDisappear { download?.cancel() }
            .modifier(ReadingTimer(paperID: paper.id, enabled: localURL != nil))
    }
    private func startDownload() {
        loading = true; downloadError = nil
        download = Task { @MainActor in
            defer { loading = false }
            do {
                fileURL = try await store.obtainFullText(paper.id)
                totalPages = fileURL.flatMap { PDFDocument(url:$0)?.pageCount } ?? 0
            }
            catch { downloadError = Task.isCancelled ? "已取消下载。" : error.localizedDescription }
        }
    }
}

struct PDFReader: UIViewRepresentable {
    let url: URL
    var initialPage: Int
    @Binding var page: Int
    @Binding var totalPages: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        let count = view.document?.pageCount ?? 0
        DispatchQueue.main.async {
            totalPages = count
            if let pdfPage = view.document?.page(at: min(max(initialPage - 1, 0), max(count - 1, 0))) { view.go(to: pdfPage) }
        }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed(_:)), name: .PDFViewPageChanged, object: view)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) { NotificationCenter.default.removeObserver(coordinator) }
    class Coordinator: NSObject {
        var parent: PDFReader
        init(_ parent: PDFReader) { self.parent = parent }
        @objc func changed(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let current = view.currentPage, let doc = view.document else { return }
            let number = doc.index(for: current) + 1
            DispatchQueue.main.async { self.parent.page = number; self.parent.totalPages = doc.pageCount }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}

struct NoteEditor: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    var paperID: String
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                ReadableSection("关联文献") { Text(store.paper(paperID)?.title ?? paperID).flowFont(.body) }
                ReadableSection("私人笔记 · 仅自己可见") { TextEditor(text: $text).frame(minHeight: 260) }
            }.navigationTitle("写笔记").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { store.state.notes[paperID] = text; dismiss() } }
                }.onAppear { text = store.state.notes[paperID] ?? "" }
        }
    }
}
