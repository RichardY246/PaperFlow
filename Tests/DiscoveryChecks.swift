import Foundation

final class DiscoveryStub: URLProtocol, @unchecked Sendable {
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

@main struct DiscoveryChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition:@autoclosure()->Bool,_ label:String) { guard condition() else { fatalError("FAIL: " + label) }; count += 1; print("PASS: " + label) }
        let oa: [String:Any] = ["meta":["count":40,"next_cursor":"oa-next"],"results":[[
            "id":"https://openalex.org/W123","doi":"https://doi.org/10.1234/example","display_name":"A useful study of human computer interaction","publication_year":2025,"publication_date":"2025-05-01",
            "authorships":[["author":["display_name":"Alex Reader"]]],"abstract_inverted_index":["Study":[0],"human":[1],"interaction":[2]],
            "primary_location":["source":["id":"https://openalex.org/S123","display_name":"Interaction Journal"],"landing_page_url":"https://publisher.example.test/paper"],
            "open_access":["is_oa":true],"best_oa_location":["landing_page_url":"https://repo.example.test/paper","pdf_url":"https://repo.example.test/paper.pdf","is_oa":true,"version":"acceptedVersion"]
        ]]]
        let oaData = try JSONSerialization.data(withJSONObject:oa)
        let (oaPapers,oaCount,oaCursor) = try LiteratureDecoders.openAlex(oaData)
        check(oaPapers.count == 1 && oaCount == 40 && oaCursor == "oa-next","解析 OpenAlex 页数与游标")
        let paper = oaPapers[0]
        check(paper.abstractText == "Study human interaction","重建 OpenAlex 倒排摘要，保持原词顺序")
        check(paper.journalTitle == "Interaction Journal" && paper.retrievalSources == ["OpenAlex"],"检索来源与发表期刊分别保存")
        check(paper.pdfURL == "https://repo.example.test/paper.pdf" && paper.versions?.count == 1,"保留开放版本和直接 PDF 地址")
        let crossItems: [[String:Any]] = (0..<12).map { i in ["DOI":"10.1234/cross-\(i)","title":["Interaction research \(i)"],"container-title":["Interaction Journal"],"author":[["given":"Alex","family":"Reader"]],"published":["date-parts":[[2025,5,1]]],"abstract":"<jats:p>A &amp; B study.</jats:p>","link":[["URL":"https://publisher.example.test/restricted.pdf","content-type":"application/pdf"]]] }
        let crData = try JSONSerialization.data(withJSONObject:["message":["items":crossItems,"total-results":40,"next-cursor":"cross-next"]])
        let (cross,_,_) = try LiteratureDecoders.crossref(crData)
        check(cross[0].abstractText == "A & B study.","Crossref 摘要移除排版标签并还原转义")
        check(cross[0].pdfURL == nil && cross[0].fullTextStatus == "未确认","有下载链接不等于可免费阅读全文")
        var variant = paper; variant.id = "other"; variant.retrievalSources = ["Crossref"]; variant.doi = "https://doi.org/10.1234/EXAMPLE"
        check(PaperIdentity.same(paper,variant),"DOI 大小写与网址形式不造成重复")
        let merged = PaperIdentity.merge(paper,variant)
        check(merged.id == paper.id && Set(merged.retrievalSources ?? []) == ["Crossref","OpenAlex"],"合并保留原 ID 与多个检索来源")
        check(PaperIdentity.webURL("https://account:secret@host.test/paper") == nil && PaperIdentity.webURL("javascript:alert(1)") == nil,"拒绝夹带账号或脚本的原文地址")
        var filter = ContentFilter(); filter.field = "标题"; filter.time = "近一年"; filter.access = "开放全文"
        let url = FederatedLiteratureService.requestURL(.arxiv,query:"人机交互",filter:filter,cursor:"12")
        let params = Dictionary(uniqueKeysWithValues:URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.map { ($0.name,$0.value ?? "") })
        check(params["start"] == "12" && params["search_query"]?.contains("ti:") == true && params["search_query"]?.contains("submittedDate") == true,"标题、日期与下一页条件发送给 arXiv")
        let oaURL = FederatedLiteratureService.requestURL(.openalex,query:"design",filter:filter,cursor:"2")
        check(oaURL.absoluteString.contains("search.title") && oaURL.absoluteString.contains("is_oa"),"OpenAlex 请求携带标题与开放全文条件")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [DiscoveryStub.self]
        let session = URLSession(configuration:configuration)
        let folder = URL.temporaryDirectory.appending(path:"Discovery-" + UUID().uuidString)
        let service = FederatedLiteratureService(session:session,directory:folder)
        var networkFilter = ContentFilter(); networkFilter.sources = ["OpenAlex","Crossref"]
        DiscoveryStub.handler = { request in request.url?.host == "api.openalex.org" ? (200,oaData) : (200,crData) }
        let result = try await service.search(query:"interaction",filter:networkFilter,openAlexKey:"fixture-openalex-key")
        check(result.papers.count == 13 && result.next["Crossref"] == "cross-next" && result.next["OpenAlex"] == "cursor:oa-next","多源结果与各自游标同时保留")
        let cached = try await service.search(query:"interaction",filter:networkFilter,openAlexKey:"fixture-openalex-key")
        check(cached.cached && cached.papers.count == 13,"统一搜索缓存可以复用")
        let limitedService = FederatedLiteratureService(session:session,directory:folder.appending(path:"limited"))
        DiscoveryStub.handler = { request in request.url?.host == "api.openalex.org" ? (429,Data(#"{"retryAfter":600}"#.utf8)) : (200,crData) }
        let partial = try await limitedService.search(query:"test",filter:networkFilter)
        check(partial.papers.count == 12 && partial.warnings.count == 1 && partial.next["Crossref"] != nil,"一个来源额度用尽时仍返回其他来源")
        let next = try await limitedService.search(query:"test",filter:networkFilter,cursors:partial.next)
        check(next.papers.count == 12 && next.warnings.isEmpty,"健康来源继续分页，不反复请求受限来源")
        let unauth = try await service.findOpenVersion(paper,email:"")
        check(unauth == paper,"没有联系邮箱时不发送 Unpaywall 请求")
        DiscoveryStub.handler = { _ in (200,try! JSONSerialization.data(withJSONObject:["best_oa_location":["url":"https://oa.example.test","url_for_pdf":"https://oa.example.test/file.pdf"]])) }
        let open = try await service.findOpenVersion(paper,email:"fixture@example.test")
        check(open.pdfURL == "https://oa.example.test/file.pdf" && open.fullTextStatus == "开放全文","DOI 开放版本补齐原文入口")
        var state = LocalState(); state.targetLanguage = "English"; state.theme = "purple"
        let roundtrip = try JSONDecoder().decode(LocalState.self,from:JSONEncoder().encode(state))
        check(roundtrip.targetLanguage == "English" && roundtrip.theme == "purple","语言与主题重启后保留")
        let old = try JSONDecoder().decode(LocalState.self,from:Data("{}".utf8))
        check(old.targetLanguage == "简体中文" && old.theme == "green","旧数据库升级获得中文和绿色默认值")
        if CommandLine.arguments.count > 1 && !CommandLine.arguments[1].isEmpty {
            let (_,_,cursor) = try LiteratureDecoders.crossref(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
            check(cursor != nil,"真实 Crossref 响应通过同一解析器")
        }
        if CommandLine.arguments.count > 2 {
            let catalog = URL(fileURLWithPath:CommandLine.arguments[2])
            let app = AppStore(directory:folder.appending(path:"state"),catalogURL:catalog)
            app.homeLoading = true
            DiscoveryStub.handler = { _ in (200,crData) }
            var homeFilter = ContentFilter(); homeFilter.sources = ["Crossref"]
            await app.loadHomeNext(filter:homeFilter,refresh:true,service:service,keyAvailable:{false})
            check(!app.homeLoading && app.homeError != nil && app.homeCursors["Crossref"] == "cross-next" && app.state.importedPapers.count == 12,"加载中刷新采用新请求；未配置 API 时保留元数据并提示")
            let requestID = app.homeRequestID; app.homeOrder = ["paper:rag"]; app.aiPauseReason = "fixture"
            app.resetDemo()
            check(app.homeRequestID != requestID && app.homeOrder.isEmpty && app.aiPauseReason == nil && !app.homeLoading,"重置使旧首页请求失效并清除队列状态")
        }
        print("ALL \(count) DISCOVERY CHECKS PASSED")
    }
}
