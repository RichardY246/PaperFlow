import Foundation
import PDFKit

final class AccessStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest)->(Int,Data))?
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        let (status,data) = Self.handler!(request)
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:[:])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

/// 只写独立临时目录，不读取用户钥匙串。PDF 样本不进入 App 安装包。
@main struct AccessMediaChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition:@autoclosure()->Bool,_ label:String) { guard condition() else { fatalError("FAIL: " + label) }; count += 1; print("PASS: " + label) }
        let project = URL(fileURLWithPath:CommandLine.arguments[1])
        let root = URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let catalog = try JSONDecoder().decode(Catalog.self,from:Data(contentsOf:project.appending(path:"Tests/Fixtures/LegacyCatalog.json")))
        var paper = catalog.papers.first(where:{$0.id == "attention"})!
        let pdf = project.appending(path:"Tests/Fixtures/Papers/attention.pdf")
        let data = try Data(contentsOf:pdf)
        let query = LiteratureQuery("我想找关于人机交互的论文")
        check(query.english.contains("human computer interaction") && !query.english.contains("论文"),"中文方向去掉口语后展开英文检索词")
        check(LiteratureQuery("https://doi.org/10.1234/ABC").identifier == "10.1234/abc","DOI 链接按标识检索")
        check(LiteratureQuery("https://arxiv.org/pdf/1706.03762v7.pdf").identifier == "1706.03762","arXiv PDF 链接提取去版本标识")
        check(FederatedLiteratureService.requestURL(.arxiv,query:"1706.03762",filter:ContentFilter(),cursor:"0").absoluteString.contains("id_list"),"arXiv 标识直接定位论文")
        let halData = Data(#"{"response":{"numFound":13,"start":0,"docs":[{"halId_s":"hal-123","title_s":["A framework for attention"],"authFullName_s":["Alex Reader"],"abstract_s":["Main result"],"producedDateY_i":2025,"journalTitle_s":"Journal A","doiId_s":"10.1234/hal","uri_s":"https://hal.science/hal-123","fileMain_s":"https://hal.science/hal-123/document"}]}}"#.utf8)
        let (hal,total,next) = try OpenRepositoryDecoders.hal(halData)
        check(hal.count == 1 && total == 13 && next == "1" && hal[0].pdfURL?.hasSuffix("/document") == true,"HAL 开放文件与独立分页解析")
        check(hal[0].author == "Alex Reader" && hal[0].journalTitle == "Journal A" && hal[0].doi == "10.1234/hal","HAL 作者、期刊和 DOI 保持完整")
        let epmcData = Data(#"{"hitCount":14,"nextCursorMark":"next-pmc","resultList":{"result":[{"id":"123","source":"MED","pmcid":"PMC123","title":"A biomedical result","authorList":{"author":[{"fullName":"Alex Reader"}]},"pubYear":"2025","firstPublicationDate":"2025-03-01","journalInfo":{"journal":{"title":"Journal B"}},"isOpenAccess":"Y","doi":"10.1234/pmc","abstractText":"<p>Result &amp; method</p>","fullTextUrlList":{"fullTextUrl":[{"url":"https://europepmc.org/articles/PMC123?pdf=render","documentStyle":"pdf","availabilityCode":"OA","site":"Europe PMC"}]}}]}}"#.utf8)
        let (epmc,_,pmcNext) = try OpenRepositoryDecoders.europePMC(epmcData)
        check(epmc[0].pdfURL?.contains("pdf=render") == true && pmcNext == "next-pmc" && epmc[0].openHTMLURL != nil,"Europe PMC 保留开放 PDF 与 HTML 全文")
        check(epmc[0].abstractText == "Result & method" && epmc[0].journalTitle == "Journal B","Europe PMC 清理摘要标签并解析期刊")
        let coreData = Data(#"{"totalHits":30,"results":[{"id":123,"title":"Repository attention study","authors":[{"name":"Alex Reader"}],"yearPublished":2025,"doi":"10.1234/core","abstract":"Core result","downloadUrl":"https://repo.test/file.pdf","sourceFulltextUrls":["https://repo.test/record"]}]}"#.utf8)
        let (core,coreTotal,_) = try OpenRepositoryDecoders.core(coreData)
        check(coreTotal == 30 && core[0].pdfURL == "https://repo.test/file.pdf" && core[0].versions?.count == 2,"CORE 解析下载文件与仓储版本")
        let html = #"<meta content='/file.pdf?a=1&amp;b=2' name='citation_pdf_url'><link type='application/pdf' href='https://other.test/main.pdf'><a href='javascript:run()'>x</a><meta name='citation_pdf_url' content='https://user:pass@bad.test/file.pdf'>"#
        let links = FullTextLinks.pdfURLs(in:html,base:URL(string:"https://repo.test/record")!)
        check(links.map(\.absoluteString) == ["https://repo.test/file.pdf?a=1&b=2","https://other.test/main.pdf"],"从 HTML 找真实 PDF 链接，解析相对地址并拒绝嵌入账号")
        check(!FullTextLinks.isVerified(hal[0]),"来源声称开放不等于已经取得原文")
        var verified = hal[0]; verified.hasCachedFullText = true
        check(FullTextLinks.isVerified(verified),"只有已缓存或近期验证过的 PDF 标为可读")
        check(PaperIdentity.merge(hal[0],verified).hasCachedFullText == true,"跨源合并保留已验证的原文")
        let store = AppStore(directory:root.appending(path:"state"),catalogURL:project.appending(path:"PaperFlow/Resources/DemoCatalog.json"))
        _ = store.importPaper(verified);store.clearFullTextVerification()
        check(store.state.importedPapers.allSatisfy { !FullTextLinks.isVerified($0) },"清理缓存后不会留下失效的可读标记")
        var importedOnly = hal[0]; importedOnly.id = "manual-only"; importedOnly.doi = "10.1234/manual"; importedOnly.pdfURL = nil; importedOnly.versions = nil; importedOnly.fullTextStatus = "可直接阅读全文"; importedOnly.hasCachedFullText = true
        _ = store.importPaper(importedOnly);store.clearFullTextVerification()
        check(store.paper("manual-only")?.fullTextStatus == "未确认","清理仅手动导入的文件后不误称有开放全文")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AccessStub.self]
        let session = URLSession(configuration:config)
        let service = FederatedLiteratureService(session:session,directory:root.appending(path:"discovery"))
        var filter = ContentFilter(); filter.sources = ["HAL","Europe PMC","CORE"]
        AccessStub.handler = { request in
            switch request.url?.host {
            case "api.archives-ouvertes.fr": return (200,halData)
            case "www.ebi.ac.uk": return (200,epmcData)
            default: return (403,Data())
            }
        }
        let result = try await service.search(query:"attention",filter:filter)
        check(result.papers.count == 2 && result.warnings.count == 1 && result.warnings[0].contains("CORE"),"新增来源独立失败，保留其他来源结果")
        var coreFilter = filter; coreFilter.sources = ["CORE"]
        AccessStub.handler = { request in
            (request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-core-key" ? 200 : 403,coreData)
        }
        let keyed = try await service.search(query:"attention",filter:coreFilter,coreKey:"fixture-core-key",refresh:true)
        check(keyed.papers.count == 1,"CORE 个人密钥不受访客冷却影响")
        let imported = try PaperFileService.importPDF(pdf,for:paper,directory:root.appending(path:"pdf"))
        check(PDFDocument(url:imported)?.pageCount == PDFDocument(url:pdf)?.pageCount,"用户导入 PDF 可由原文阅读器直接读取")
        let bad = root.appending(path:"not-pdf.pdf"); try Data("<html>login</html>".utf8).write(to:bad)
        var rejected = false
        do { _ = try PaperFileService.importPDF(bad,for:paper,directory:root.appending(path:"pdf")) } catch { rejected = true }
        check(rejected && PDFDocument(url:imported)?.pageCount ?? 0 > 0,"HTML 登录页被拒绝且不损坏已有 PDF")
        paper.id = "fallback-test"; paper.pdfURL = "https://blocked.test/paper.pdf"; paper.sourceURL = "https://repo.test/record"
        paper.versions = [PaperVersion(label:"作者版本",url:"https://repo.test/record",isOpen:true)]
        AccessStub.handler = { request in
            if request.url?.host == "blocked.test" { return (403,Data()) }
            if request.url?.path == "/record" { return (200,Data("<meta name='citation_pdf_url' content='/file.pdf'>".utf8)) }
            return (200,data)
        }
        let downloaded = try await PaperFileService.downloadVerified(paper,session:session,directory:root.appending(path:"fallback"))
        check(downloaded.remoteURL == "https://repo.test/file.pdf" && PDFDocument(url:downloaded.file) != nil,"PDF 失败后切换开放版本，并从 HTML 解析 PDF 下载")
        paper = catalog.papers.first(where:{$0.id == "attention"})!
        let figures = await FigureExtractor.list(paper:paper,url:pdf)
        check(figures.count >= 3 && figures.allSatisfy { $0.caption.count > $0.label.count + 8 },"真实论文识别带说明的图注，排除正文引用")
        check(figures.contains { $0.label.lowercased().contains("1") && $0.caption.lowercased().contains("architecture") },"识别 Transformer 架构核心图")
        let ids = FigureRanking.safeIDs(["invented-id",figures[0].id,figures[0].id],candidates:figures)
        check(ids.count == min(3,figures.count) && Set(ids).count == ids.count && !ids.contains("invented-id"),"模型只能选择实际图注，去重并补足最多三张候选")
        await FigureExtractor.render(paperID:paper.id,candidates:figures,ids:ids,url:pdf,directory:root.appending(path:"figures"))
        check(ids.allSatisfy { FileManager.default.fileExists(atPath:FigureExtractor.imageURL(paper.id,candidate:$0,directory:root.appending(path:"figures")).path) },"按图注位置生成候选图，而非整页随机截图")
        let manifest = figures.map { ["id":$0.id,"label":$0.label,"caption":$0.caption,"page":String($0.page),"x":String($0.anchorX),"y":String($0.anchorY),"w":String($0.anchorWidth),"image":FigureExtractor.imageURL(paper.id,candidate:$0.id,directory:root.appending(path:"figures")).path] }
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:root.appending(path:"figures.json"))
        check(FigureRanking.score(caption:"Overview of proposed architecture and main result",title:paper.title,abstract:"",page:3,label:"Figure 1") > FigureRanking.score(caption:"Additional examples in the appendix",title:paper.title,abstract:"",page:10,label:"Figure 8"),"核心方法和主要结果优先于附录样例")
        check(figures.first(where:{$0.id == "p3-figure1"})?.caption == "Figure 1: The Transformer - model architecture.","图注截止于下一段正文，不混入后续章节")
        for name in ["lora","ddpm","resnet"] {
            let sample = catalog.papers.first(where:{$0.id == name})!
            let sampleURL = project.appending(path:"Tests/Fixtures/Papers/\(name).pdf")
            let list = await FigureExtractor.list(paper:sample,url:sampleURL)
            let chosen = FigureRanking.safeIDs(nil,candidates:list)
            await FigureExtractor.render(paperID:name,candidates:list,ids:chosen,url:sampleURL,directory:root.appending(path:"figures"))
            check(!list.isEmpty && chosen.allSatisfy { FileManager.default.fileExists(atPath:FigureExtractor.imageURL(name,candidate:$0,directory:root.appending(path:"figures")).path) },"真实 \(name) 论文识别和裁切候选图")
            let records = chosen.map { id in ["id":id,"caption":list.first(where:{$0.id == id})!.caption,"image":FigureExtractor.imageURL(name,candidate:id,directory:root.appending(path:"figures")).path] }
            try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:root.appending(path:name + "-figures.json"))
        }
        let hnu = URL(string:LibrarySite.hnuLogin)!
        check(hnu.host == "cas.hnu.edu.cn" && URLComponents(url:hnu,resolvingAgainstBaseURL:false)?.queryItems?.first?.value?.contains("unified-auth.chaoxing.com") == true,"湖大入口直达校方 CAS 并保留图书馆回跳地址")
        check(LibrarySite.profile(for:hnu) == "hnu" && LibrarySite.profile(for:URL(string:"https://webvpn.hnu.edu.cn/")!) == "hnu","湖大登录与 WebVPN 使用同一访问分类")
        check(LibrarySite.profile(for:URL(string:"https://fakehnu.edu.cn.example.test/")!) == "public","机构域名使用严格后缀匹配")
        print("ALL \(count) ACCESS / MEDIA CHECKS PASSED")
        print("ARTIFACTS: " + root.path)
    }
}
