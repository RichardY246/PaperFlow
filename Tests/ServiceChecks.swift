import Foundation

// 用模拟响应验证请求，不使用个人密钥，也不产生模型费用。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@main struct ServiceChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            guard value() else { fatalError("FAIL: \(name)") }; count += 1; print("PASS: \(name)")
        }
        let config = AIConfiguration(baseURL: " https://api.example.test/v1/ ", model: "test-model")
        let endpoint = try AIService.endpoint(config)
        check(endpoint.absoluteString == "https://api.example.test/v1/chat/completions", "服务地址保留 v1 并正确拼接接口")
        check(try! AIService.endpoint(AIConfiguration(baseURL: endpoint.absoluteString, model: "m")) == endpoint, "完整接口不重复追加路径")
        for invalid in ["http://example.test", "https://user:secret@example.test", "https://example.test?api_key=bad", "https://example.test/#key"] {
            do { _ = try AIService.endpoint(AIConfiguration(baseURL: invalid, model: "m")); fatalError("accepted invalid URL") }
            catch { check(true, "拒绝不安全或夹带凭据的服务地址") }
        }
        let cards: [[String:Any]] = (0..<5).map { i in ["title":"研究问题 \(i)","text":"这份资料只包含摘要，研究结论需要原文核对。","evidence":"source evidence","page":NSNull()] }
        let draftText = String(data:try JSONSerialization.data(withJSONObject:["title":"这个方法改变了一切？","clarification":"标题是夸张表达，摘要只支持特定条件下的结果。","body":"研究提供了一种方法，并讨论了其适用条件与局限。","coverText":"研究线索","cards":cards]),encoding:.utf8)!
        let draft = try AIService.decodeDraft("```json\n" + draftText + "\n```")
        check(draft.clarification.contains("夸张"), "模型结果保留正文首句的标题澄清")
        do { _ = try AIService.decodeDraft(#"{"title":"标题","clarification":"","body":"正文"}"#); fatalError("accepted empty clarification") }
        catch { check(true, "缺少澄清时不保存生成结果") }
        let xml = #"""
        <?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><entry><id>http://arxiv.org/abs/1706.03762v7</id><title>Attention Is All You Need</title><summary>First &amp; second sentence.</summary><published>2017-06-12T17:57:34Z</published><author><name>Ashish Vaswani</name></author><category term="cs.CL"/></entry><entry><id>http://arxiv.org/abs/1706.03762v8</id><title>Attention Is All You Need</title><summary>new version</summary><published>2017-06-12T17:57:34Z</published><author><name>Ashish Vaswani</name></author></entry></feed>
        """#
        let papers = try LiteratureService.parse(Data(xml.utf8))
        check(papers.count == 1 && papers[0].id == "arxiv-1706.03762", "arXiv 版本去重并生成稳定 ID")
        check(papers[0].abstractText == "First & second sentence." && papers[0].author == "Ashish Vaswani", "XML 摘要转义和作者解析正确")
        check(papers[0].pdfURL == "https://arxiv.org/pdf/1706.03762" && papers[0].topics == ["生成式 AI"], "结果包含原文入口和主题")
        let url = LiteratureService.searchURL("人机交互")
        check(url.scheme == "https" && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value?.contains("human") == true, "在线检索使用 HTTPS 并支持常见中文方向")
        do { _ = try LiteratureService.parse(Data("bad XML".utf8)); fatalError("accepted bad XML") }
        catch { check(true, "错误响应不会伪装成空检索结果") }
        let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        let service = AIService(session: session)
        StubURLProtocol.handler = { request in
            guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key" else { fatalError("invalid auth") }
            // URLSession 可能把 body 转成流；这里主要验证授权头、URL 与响应处理。
            return (200, try JSONSerialization.data(withJSONObject: ["choices":[["message":["content":draftText]]],"usage":["prompt_tokens":100,"completion_tokens":50,"total_tokens":150]]))
        }
        let source = ReadingSource(label: "测试摘要", text: "Only a test abstract.", page: nil)
        let generated = try await service.generate(paper: papers[0], source: source, configuration: config, key: "fixture-key")
        check(generated.title == draft.title && generated.sourceText == source.text && generated.model == "test-model", "生成结果保存原始资料、模型与来源")
        check(generated.usage?.total == 150 && service.lastUsage?.total == 150,"接口实际 usage 随结果保存")
        check(generated.cards?.count == 5 && generated.cards?.allSatisfy { $0.evidence == nil && $0.page == nil } == true,"未核实引句和摘要猜测页码不会展示")
        check(generated.provider == "api.example.test", "生成结果保存服务商以便回看")
        let figures = [FigureCandidate(id:"p2-figure1",page:2,label:"Figure 1",caption:"Overview architecture",anchorX:0.1,anchorY:0.5,anchorWidth:0.8,score:8),FigureCandidate(id:"p5-figure2",page:5,label:"Figure 2",caption:"Main performance result",anchorX:0.1,anchorY:0.5,anchorWidth:0.8,score:10)]
        var selectedDraft = try JSONSerialization.jsonObject(with:Data(draftText.utf8)) as! [String:Any]
        selectedDraft["figureIDs"] = ["p5-figure2","not-in-paper"]; selectedDraft["figureReason"] = "主结果图最直接地支持论文的主要贡献。"
        let selectedText = String(data:try JSONSerialization.data(withJSONObject:selectedDraft),encoding:.utf8)!
        StubURLProtocol.handler = { _ in (200,try! JSONSerialization.data(withJSONObject:["choices":[["message":["content":selectedText]]]])) }
        let selected = try await service.generate(paper:papers[0],source:source,configuration:config,key:"fixture-key",figures:figures)
        check(selected.figureIDs?.first == "p5-figure2" && selected.figureIDs?.contains("not-in-paper") == false && selected.figureSelectionMethod == "AI 图注选择","AI 核心图选择保留有效优先顺序并拒绝捏造图号")
        check(selected.figureReason?.contains("主要贡献") == true && selected.mediaVersion == 2,"核心图理由与新媒体版本随解读保存")
        selectedDraft["figureIDs"] = ["invented-id"]
        let invalidSelection = String(data:try JSONSerialization.data(withJSONObject:selectedDraft),encoding:.utf8)!
        StubURLProtocol.handler = { _ in (200,try! JSONSerialization.data(withJSONObject:["choices":[["message":["content":invalidSelection]]]])) }
        let fallbackFigure = try await service.generate(paper:papers[0],source:source,configuration:config,key:"fixture-key",figures:figures)
        check(fallbackFigure.figureSelectionMethod == "图注排序" && fallbackFigure.figureReason == nil && fallbackFigure.figureIDs?.first == "p5-figure2","无有效模型选择时明确回退图注排序，不展示模型捏造理由")
        StubURLProtocol.handler = { _ in (200,try! JSONSerialization.data(withJSONObject:["choices":[["message":["content":#"{"title":"English","clarification":"An exaggeration.","body":"English text."}"#]]]])) }
        do { _ = try await service.generate(paper:papers[0],source:source,configuration:config,key:"fixture-key",language:"简体中文"); fatalError("accepted wrong language") }
        catch { check(error.localizedDescription.contains("目标语言") || error.localizedDescription.contains("概览卡片"), "中文生成不会接受全英文结果") }
        StubURLProtocol.handler = { _ in (200,try! JSONSerialization.data(withJSONObject:["choices":[["message":["content":draftText]]]])) }
        do { _ = try await service.generate(paper:papers[0],source:source,configuration:config,key:"fixture-key",language:"English"); fatalError("accepted Chinese as English") }
        catch { check(error.localizedDescription.contains("目标语言") || error.localizedDescription.contains("概览卡片"), "英文生成不会接受中文正文或只相信语言标签") }
        check(ReadingLanguages.normalized("这是阅读记录",language:"繁體中文") == "這是閱讀記錄", "繁体目标语言转换生成内容的字形")
        StubURLProtocol.handler = { _ in (401, Data("secret should never be echoed".utf8)) }
        do { _ = try await service.complete(configuration: config, key: "fixture-key", system: "test", user: "test"); fatalError("accepted 401") }
        catch { check(error.localizedDescription.contains("密钥") && !error.localizedDescription.contains("secret"), "鉴权错误不回显服务器原文或密钥") }
        StubURLProtocol.handler = { _ in (429, Data()) }
        do { _ = try await service.complete(configuration: config, key: "fixture-key", system: "test", user: "test"); fatalError("accepted 429") }
        catch { check(error.localizedDescription.contains("额度"), "额度不足有可理解的提示") }
        StubURLProtocol.handler = { _ in (429, Data(#"{"error":{"code":"1305","message":"fixture-key must never be echoed"}}"#.utf8)) }
        let glm = AIConfiguration(baseURL:"https://open.bigmodel.cn/api/paas/v4",model:"glm-5.2")
        do { _ = try await service.complete(configuration:glm,key:"fixture-key",system:"test",user:"test"); fatalError("accepted overload") }
        catch { check(error.localizedDescription.contains("繁忙") && error.localizedDescription.contains("1305") && !error.localizedDescription.contains("fixture-key"), "智谱繁忙错误显示安全代码并保留密钥隐私") }
        StubURLProtocol.handler = { _ in (200, Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8)) }
        do { _ = try await service.complete(configuration: config, key: "fixture-key", system: "test", user: "test"); fatalError("accepted empty output") }
        catch { check(error.localizedDescription.contains("没有返回文字"), "空输出不能覆盖已有内容") }
        StubURLProtocol.handler = { _ in (500,Data(#"{"usage":{"prompt_tokens":11,"completion_tokens":4,"total_tokens":15}}"#.utf8)) }
        do { _ = try await service.complete(configuration:config,key:"fixture-key",system:"test",user:"test"); fatalError("accepted server failure") } catch { check(service.lastUsage?.total == 15 && service.sentRequest && !service.rejected,"失败请求仍保留服务商返回的实际计费") }
        var state = LocalState(); state.importedPapers = papers; state.generatedReadings[papers[0].id] = generated
        let encoded = try JSONEncoder().encode(state)
        check(!String(decoding: encoded, as: UTF8.self).contains("fixture-key"), "普通 JSON 不包含个人密钥")
        let restored = try JSONDecoder().decode(LocalState.self, from: encoded)
        check(restored.generatedReadings[papers[0].id] == generated && restored.importedPapers.count == 1, "在线文献与 AI 缓存可完整恢复")
        let directory = URL.temporaryDirectory.appending(path: "PaperFlow-Network-\(UUID().uuidString)")
        var calls = 0
        StubURLProtocol.handler = { _ in calls += 1; return (200, Data(xml.utf8)) }
        let literature = LiteratureService(session: session, directory: directory)
        let first = try await literature.search("attention")
        let second = try await literature.search("attention")
        check(!first.fromCache && second.fromCache && calls == 1, "重复检索直接使用缓存，避免额外请求")
        let reloaded = LiteratureService(session: session, directory: directory)
        let third = try await reloaded.search("attention")
        check(third.fromCache && third.papers.count == 1 && calls == 1, "搜索缓存重启后仍可用")
        var expired = third; expired.fetchedAt = 0
        try JSONEncoder().encode(["attention": expired]).write(to: directory.appending(path: "literature-search.json"))
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offline = LiteratureService(session: session, directory: directory)
        let fallback = try await offline.search("attention")
        check(fallback.fromCache && fallback.fetchedAt == 0, "断网时可回看旧缓存，并保留原获取时间")
        offline.clearCache()
        check(!FileManager.default.fileExists(atPath: directory.appending(path: "literature-search.json").path), "重置能清除搜索缓存")
        if CommandLine.arguments.count > 1 {
            let live = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let results = try LiteratureService.parse(live)
            check(!results.isEmpty && results.allSatisfy { $0.pdfURL?.hasPrefix("https://arxiv.org/pdf/") == true }, "真实 arXiv 接口返回可解析文献和原文地址")
        }
        print("ALL \(count) SERVICE CHECKS PASSED")
    }
}
