import SwiftUI
import WebKit
import PDFKit
import Observation
import SafariServices

extension LibrarySite {
    // 同一 App 阅读器内保持学校、CARSI、出版商跳转的连续会话。
    static func dataStore(_ id:String) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier:UUID(uuidString:"9A4F3410-BB14-4222-9000-000000000001")!)
    }
}

struct BrowserDestination: Identifiable {
    let id = UUID()
    var url: URL
    var profile = "public"
    var paperID: String?
    var systemBrowser:Bool?
}

/// 记录访问时间；校方与出版商在同一 App 阅读器会话中跳转，不推测登录是否成功。
struct LibraryConnectionsView: View {
    @Environment(AppStore.self) private var store
    @State private var browser: BrowserDestination?
    @State private var email = ""
    @State private var openAlexKey = ""
    @State private var coreKey = ""
    @State private var message = ""
    @State private var clearing: LibrarySite?
    var body: some View {
        Form {
            ReadableSection("个人与机构登录") {
                ForEach(LibrarySite.all) { site in
                    VStack(alignment:.leading,spacing:8) {
                        Button(site.name + " · 登录 / 继续访问") {
                            store.state.webVisits[site.id] = Date().timeIntervalSince1970
                            browser = BrowserDestination(url:URL(string:site.url)!,profile:site.id)
                        }
                        Text(site.detail).flowFont(.body).foregroundStyle(.secondary)
                        if let date = store.state.webVisits[site.id] { Text("上次访问：" + Date(timeIntervalSince1970:date).formatted(date:.abbreviated,time:.shortened)).flowFont(.subheadline).foregroundStyle(.secondary) }
                        Button("清除 App 阅读器中的此平台会话",role:.destructive) { clearing = site }.flowFont(.subheadline)
                    }.padding(.vertical,5)
                }
                Text("默认使用系统提供的官方网页浏览器。若登录失败，可转到 Safari。系统网页与 App 阅读器的登录状态不会自动互通。").flowFont(.body).foregroundStyle(.secondary)
            }
            ReadableSection("文献服务（与大模型密钥分开）") {
                SecureField("OpenAlex 密钥（选填）",text:$openAlexKey).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                SecureField("CORE 密钥（选填）",text:$coreKey).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                TextField("Unpaywall 联系邮箱（选填）",text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("OpenAlex 和 CORE 的访客访问可能受限，可分别填写个人密钥；查找 DOI 的开放版本时，才向 Unpaywall 发送联系邮箱。").flowFont(.body).foregroundStyle(.secondary)
                Button("保存文献设置") {
                    do {
                        let value = email.trimmingCharacters(in:.whitespacesAndNewlines)
                        guard value.isEmpty || (value.contains("@") && value.contains(".")) else { throw ServiceError.message("请检查联系邮箱。") }
                        try LibraryKeyStore.save(openAlexKey); try LibraryKeyStore.save(coreKey,provider:"CORE"); store.state.libraryConfiguration.contactEmail = value; message = "已保存。"
                    } catch { message = error.localizedDescription }
                }
                if !message.isEmpty { Text(message).flowFont(.body) }
            }
            ReadableSection("数据来源") {
                Text("统一搜索直接检索 arXiv、HAL、Europe PMC、CORE、OpenAlex、Crossref。机构授权仅在相应网页登录会话中使用。").flowFont(.body)
                Text("阅读全文后可在网站下载 PDF 到“文件”，回到对应论文的原文页导入。App 不把打开登录页显示为已登录。").flowFont(.body)
                Text("Thank you to arXiv for use of its open access interoperability.").flowFont(.subheadline).foregroundStyle(.secondary)
            }
        }.navigationTitle("账号与文献服务").navigationBarTitleDisplayMode(.inline).flowFont(.body)
            .onAppear { email = store.state.libraryConfiguration.contactEmail; openAlexKey = LibraryKeyStore.read(); coreKey = LibraryKeyStore.read("CORE") }
            .sheet(item:$browser) { InAppLibraryBrowser(destination:$0) }
            .confirmationDialog("清除此平台在 App 阅读器中的登录和网页数据？",isPresented:Binding(get:{clearing != nil},set:{if !$0 {clearing = nil}}),titleVisibility:.visible) {
                Button("清除会话",role:.destructive) {
                    guard let site = clearing else { return }
                    let storage = LibrarySite.dataStore(site.id)
                    storage.fetchDataRecords(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                        let domains = LibrarySite.domains(site.id)
                        let matched = records.filter { record in domains.contains { record.displayName == $0 || record.displayName.hasSuffix("." + $0) } }
                        storage.removeData(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes(),for:matched) { message = "已清除 App 阅读器中的平台会话，系统浏览器会话未改。" }
                    }
                    store.state.webVisits.removeValue(forKey:site.id); clearing = nil
                }
            }
    }
}

@MainActor @Observable
final class LibraryBrowserModel: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @ObservationIgnored let webView: WKWebView
    var url: URL
    var loading = true
    var error: String?
    var isPDF = false
    var saved = false
    @ObservationIgnored private var downloads: [ObjectIdentifier: URL] = [:]
    @ObservationIgnored private let paperID: String?
    init(_ destination: BrowserDestination) {
        url = destination.url; paperID = destination.paperID
        let config = WKWebViewConfiguration(); config.websiteDataStore = LibrarySite.dataStore(destination.profile)
        webView = WKWebView(frame:.zero,configuration:config)
        super.init(); webView.navigationDelegate = self; webView.uiDelegate = self

    }
    func loadIfNeeded() { if webView.url == nil { webView.load(URLRequest(url:url)) } }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; error = nil; isPDF = false; if let url = webView.url { self.url = url } }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; if let url = webView.url { self.url = url }; isPDF = isPDF || url.pathExtension.lowercased() == "pdf" }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading = false; self.error = "网页暂时无法加载：" + error.localizedDescription }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false; self.error = error.localizedDescription }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }; return nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        isPDF = navigationResponse.response.mimeType == "application/pdf"
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func savePDF() {
        guard paperID != nil else { return }
        error = nil
        webView.startDownload(using:URLRequest(url:url)) { [weak self] download in download.delegate = self }
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard paperID != nil else { error = "请从某篇文献进入网页，才能关联下载的 PDF。"; completionHandler(nil); return }
        let destination = URL.temporaryDirectory.appending(path:"PaperFlow-Web-" + UUID().uuidString + ".pdf")
        downloads[ObjectIdentifier(download)] = destination; completionHandler(destination)
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let temporary = downloads.removeValue(forKey:ObjectIdentifier(download)), let paperID else { return }
        defer { try? FileManager.default.removeItem(at:temporary) }
        guard let document = PDFDocument(url:temporary), document.pageCount > 0 else { error = "下载内容不是有效 PDF，请在网站内确认全文地址。"; return }
        do {
            let destination = PaperFileService.cachedURL(id:paperID)
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data(contentsOf:temporary).write(to:destination,options:.atomic)
            saved = true
        } catch { self.error = "原文保存失败：" + error.localizedDescription }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let file = downloads.removeValue(forKey:ObjectIdentifier(download)) { try? FileManager.default.removeItem(at:file) }
        self.error = "下载未完成：" + error.localizedDescription
    }
}

struct InAppLibraryBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model: LibraryBrowserModel
    @State private var systemMode:Bool
    @State private var systemURL:URL
    let destination: BrowserDestination
    init(destination: BrowserDestination) { self.destination = destination; _systemURL = State(initialValue:destination.url); _model = State(initialValue:LibraryBrowserModel(destination)); _systemMode = State(initialValue:destination.systemBrowser ?? (destination.profile != "public")) }
    var body: some View {
        if systemMode {
            SystemLibraryBrowser(url:systemURL) { dismiss() }
                .safeAreaInset(edge:.top) {
                    VStack(alignment:.leading,spacing:8) {
                        HStack { Button("切换 App 阅读器") { systemMode = false }; Spacer(); Button("Safari 打开") { openURL(systemURL) } }
                        Text("切换后从入口重开，可能需要重新登录。").flowFont(.subheadline).foregroundStyle(.secondary)
                    }.flowFont(.body).padding(12).background(.regularMaterial)
                }
        } else { NavigationStack {
            VStack(spacing:0) {
                HStack { Image(systemName:"lock.shield"); Text(model.url.host ?? "官方网页").flowFont(.body).textSelection(.enabled); Spacer(); if model.loading { ProgressView() } }.padding(12)
                if let error = model.error { Text(error).flowFont(.body).padding(12); Button("重新加载") { model.webView.reload() } }
                if model.saved { Text("原文已保存，关闭网页后即可离线阅读。").flowFont(.body).padding(12) }
                LibraryWebView(model:model)
            }.navigationTitle("文献与机构访问").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } }
                    ToolbarItemGroup(placement:.bottomBar) {
                        Button { model.webView.goBack() } label: { Image(systemName:"chevron.left") }.accessibilityLabel("网页后退")
                        Button { model.webView.goForward() } label: { Image(systemName:"chevron.right") }.accessibilityLabel("网页前进")
                        Spacer()
                        if model.isPDF && destination.paperID != nil { Button("保存 PDF") { model.savePDF() } }
                        Menu { Button("系统网页浏览器") { systemURL = model.url; systemMode = true }; Button("在 Safari 中打开") { openURL(model.url) } } label: { Image(systemName:"ellipsis.circle") }
                    }
                }
        }.onDisappear { model.webView.stopLoading() }
        }
    }
}

private struct LibraryWebView: UIViewRepresentable {
    let model: LibraryBrowserModel
    func makeUIView(context:Context) -> WKWebView { model.loadIfNeeded(); return model.webView }
    func updateUIView(_ uiView:WKWebView,context:Context) { }
}


/// 系统负责网页登录；应用不读取密码、验证码或系统浏览器 Cookie。
private struct SystemLibraryBrowser: UIViewControllerRepresentable {
    var url:URL
    var onDone:() -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDone:onDone) }
    func makeUIViewController(context:Context) -> SFSafariViewController {
        let view = SFSafariViewController(url:url); view.delegate = context.coordinator; return view
    }
    func updateUIViewController(_ uiViewController:SFSafariViewController,context:Context) { }
    class Coordinator:NSObject,SFSafariViewControllerDelegate {
        var onDone:() -> Void
        init(onDone:@escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller:SFSafariViewController) { onDone() }
    }
}
