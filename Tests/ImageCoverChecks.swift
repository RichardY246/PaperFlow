import Foundation
import Security
import LocalAuthentication
import ImageIO

final class ImageMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var requests:[URLRequest] = []
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if let data = request.httpBody { Self.payload = data }
        else if let stream = request.httpBodyStream {
            stream.open();defer { stream.close() };var bytes = Data(),buffer = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer,maxLength:buffer.count);if count <= 0 { break };bytes.append(buffer,count:count) };Self.payload = bytes
        }
        let response = HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main struct ImageCoverChecks {
    @MainActor static func main() async throws {
        func check(_ condition:Bool,_ message:String) { precondition(condition,message);print("PASS: "+message) }
        var budget = ImageBudget()
        try budget.reserve("a",content:"paper1");try budget.reserve("b",content:"paper2");try budget.reserve("c",content:"paper3")
        check(budget.remaining == 0,"发送前预占，三次并发不能超出额度")
        do { try budget.reserve("d",content:"paper4");preconditionFailure("额度检查失效") } catch ImageCoverError.quota { }
        budget.settle("a",billed:false);check(budget.remaining == 1 && budget.used == 0,"明确拒绝释放次数")
        budget.settle("b",billed:true);budget.settle("b",billed:true)
        check(budget.used == 1 && budget.pending.count == 1,"成功结算幂等，未知请求保留预占")
        do { try budget.reserve("again",content:"paper3");preconditionFailure("未知请求被重复提交") } catch ImageCoverError.uncertain { }
        let roundtrip = try JSONDecoder().decode(ImageBudget.self,from:JSONEncoder().encode(budget))
        check(roundtrip == budget,"预占与用量可以重启恢复")
        var old = DemoLedger();old.usedTokens = 120;old.delivered = ["old"]
        var json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as! [String:Any];json.removeValue(forKey:"imageBudget")
        let migrated = try JSONDecoder().decode(DemoLedger.self,from:JSONSerialization.data(withJSONObject:json))
        check(migrated.usedTokens == 120 && migrated.delivered == ["old"] && (migrated.imageBudget ?? ImageBudget()).remaining == 3,"旧额度迁移保留文字和论文用量，新增三张生图")
        old.imageBudget = budget;old.topUp()
        check(old.imageBudget!.limit == 6 && old.imageBudget!.used == 1 && old.usedTokens == 120,"模拟充值增加三张，不重置已有消费")
        check(ImageConfiguration.accepts(AIConfiguration()) && !ImageConfiguration.accepts(AIConfiguration(baseURL:"https://api.deepseek.com",model:"deepseek-chat")),"只复用官方智谱配置，不发送其他厂商密钥")
        check(!ImageConfiguration.accepts(AIConfiguration(baseURL:"https://open.bigmodel.cn.attacker.test/api/paas/v4",model:"glm-5.2")),"相似域名不能关联智谱密钥")
        let input = ImageCoverInput(contentID:"paper:real",title:"Attention Is All You Need",summary:String(repeating:"architecture ",count:1000),paper:true)
        check(input.prompt.count <= 1000 && input.prompt.contains("不要任何文字"),"提示词有长度边界与无文字要求")
        var altered = input;altered.summary = "changed abstract"
        check(altered.cacheID == input.cacheID,"同一论文不会因新增解读重复生图")
        let note = ImageCoverInput(contentID:"post:note",title:"读书",summary:"问题",paper:false)
        var edited = note;edited.summary = "新的主题"
        check(note.cacheID != edited.cacheID,"笔记主题修改使用独立缓存")
        let catalog = try JSONDecoder().decode(Catalog.self,from:Data(contentsOf:URL(fileURLWithPath:"Tests/Fixtures/LegacyCatalog.json")))
        let first = catalog.papers[0]
        var second = first;second.id = "legacy-balance"
        var confirmed = ImageCoverRecord(id:ImageCoverInput(contentID:"paper:"+first.id,title:"",summary:"",paper:true).cacheID,contentID:"paper:"+first.id,requestID:"balance-test",mode:"demo",status:"failed",message:"智谱账户余额不足")
        confirmed.providerCode = "1113"
        var legacy = confirmed;legacy.id = ImageCoverInput(contentID:"paper:"+second.id,title:"",summary:"",paper:true).cacheID;legacy.contentID = "paper:"+second.id;legacy.requestID = "legacy";legacy.providerCode = nil
        let eligible = ImageRecoverySelection.papers(records:[confirmed.id:confirmed,legacy.id:legacy],papers:[first,second],manual:[])
        check(eligible.count == 2,"恢复范围包含新旧两种明确余额不足记录")
        check(ImageRecoverySelection.papers(records:[confirmed.id:confirmed],papers:[first],manual:[first.id]).isEmpty,"手选封面不会被批量恢复覆盖")
        var unknown = confirmed;unknown.status = "unknown"
        check(!unknown.isUnbilledBalanceFailure && ImageRecoverySelection.papers(records:[unknown.id:unknown],papers:[first],manual:[]).isEmpty,"结果不明的请求不会被批量重新付费提交")
        var paid = confirmed;paid.counted = true
        check(!paid.isUnbilledBalanceFailure,"已计次结果不进入余额失败重试")
        var completed = confirmed;completed.status = "ready";completed.remoteURL = "https://image.test/cached.jpg"
        check(ImageRecoverySelection.papers(records:[completed.id:completed,"historical-call":confirmed],papers:[first],manual:[]).isEmpty,"旧失败历史不会使已完成封面重复生图")
        check(ImageRecoverySelection.papers(records:[confirmed.id:confirmed],papers:[],manual:[]).isEmpty,"已移除的论文不会继续批量生图")
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [ImageMockProtocol.self]
        let service = ImageGenerationService(session:URLSession(configuration:config),downloads:URLSession(configuration:config))
        ImageMockProtocol.body = Data(#"{"data":[{"url":"https://image.test/one.png"}]}"#.utf8)
        let address = try await service.generate(prompt:input.prompt,key:"test-placeholder")
        check(address == "https://image.test/one.png","识别官方图片 URL 响应")
        let request = ImageMockProtocol.requests.last!
        let payload = try JSONSerialization.jsonObject(with:ImageMockProtocol.payload) as! [String:Any]
        check(request.url == ImageConfiguration.endpoint && request.httpMethod == "POST" && request.value(forHTTPHeaderField:"Authorization") == "Bearer test-placeholder","专用 images/generations 接口与 Bearer 认证")
        check(payload["model"] as? String == "glm-image" && payload["size"] as? String == "1536x1152" && payload["quality"] as? String == "hd" && payload["watermark_enabled"] == nil,"严格 4:3 参数，保留默认水印")
        ImageMockProtocol.status = 403;ImageMockProtocol.body = Data(#"{"error":{"code":"1311","message":"never display raw error"}}"#.utf8)
        do { _ = try await service.generate(prompt:"test",key:"test-placeholder");preconditionFailure("403 应拒绝") }
        catch let error as ImageGenerationService.Rejection { check(error.localizedDescription.contains("权限") && !error.localizedDescription.contains("raw"),"拒绝请求可释放额度，不回显服务商原文") }
        ImageMockProtocol.status = 429
        ImageMockProtocol.body = Data(#"{"error":{"code":"1113","message":"provider response must not be displayed raw"}}"#.utf8)
        do { _ = try await service.generate(prompt:"test",key:"test-placeholder");preconditionFailure("余额不足应明确拒绝") }
        catch let error as ImageGenerationService.Rejection {
            check(error.code == "1113" && error.httpStatus == 429 && error.localizedDescription.contains("余额") && error.localizedDescription.contains("模拟充值"),"实际 429/1113 响应识别为真实余额不足，不误报限流或未知")
            var rejectedBudget = ImageBudget();try rejectedBudget.reserve("balance",content:"paper:balance");rejectedBudget.settle("balance",billed:false)
            check(rejectedBudget.remaining == 3 && rejectedBudget.used == 0,"余额拒绝释放本地预占，不消耗演示生图次数")
            var failed = ImageCoverRecord(id:"balance",contentID:"paper:test",requestID:"balance",mode:"demo",status:"failed",message:error.localizedDescription)
            failed.providerCode = error.code;failed.httpStatus = error.httpStatus
            check(failed.failureHint == "智谱余额或资源包不足","首页提供简短、明确的失败原因")
            let decoded = try JSONDecoder().decode(ImageCoverRecord.self,from:JSONEncoder().encode(failed))
            check(decoded.providerCode == "1113" && decoded.httpStatus == 429,"错误编号与状态重开后保留")
        }
        ImageMockProtocol.status = 503
        do { _ = try await service.generate(prompt:"test",key:"test-placeholder");preconditionFailure("503 应待确认") }
        catch ImageCoverError.uncertain { print("PASS: 服务器异常保守标为结果不明") }
        ImageMockProtocol.status = 200;ImageMockProtocol.body = Data(#"{"data":[{"url":"http://insecure.test/a.png"}]}"#.utf8)
        do { _ = try await service.generate(prompt:"test",key:"test-placeholder");preconditionFailure("非 HTTPS 不应接受") }
        catch ImageCoverError.uncertain { print("PASS: 不接受不安全的图片地址") }
        // 下载时不传入 Key；即使下载失败，也验证请求与生图 POST 分离。
        ImageMockProtocol.status = 404
        do { _ = try await service.download("https://image.test/missing.png",id:"test",directory:URL.temporaryDirectory.appending(path:UUID().uuidString)) } catch { }
        check(ImageMockProtocol.requests.last?.value(forHTTPHeaderField:"Authorization") == nil && ImageMockProtocol.requests.last?.httpMethod == "GET","图片 CDN 下载不携带 API Key")
        ImageMockProtocol.status = 200
        ImageMockProtocol.body = try Data(contentsOf:URL(fileURLWithPath:"PaperFlow/Assets.xcassets/NotesQuestions.imageset/NotesQuestions.png"))
        let downloaded = try await service.download("https://image.test/success.png",id:"download-check",directory:URL.temporaryDirectory.appending(path:UUID().uuidString))
        let decoded = CGImageSourceCreateWithURL(downloaded as CFURL,nil)
        check(decoded != nil && downloaded.pathExtension == "jpg","实际下载图片可解码，并持久化为本地 JPEG")
        // 只查询已知的演示钥匙串条目，不触发授权弹窗，不输出或写入密钥。
        let authentication = LAContext();authentication.interactionNotAllowed = true
        var query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"PaperFlow.UserAPIKeys",kSecAttrAccount as String:"https://paperflow.local/device-demo/chat/completions",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationContext as String:authentication]
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        var result:CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecSuccess,let bytes = result as? Data,let key = String(data:bytes,encoding:.utf8),!key.isEmpty {
            let live = ImageGenerationService()
            let url = try await live.generate(prompt:"4:3横版纯图片，阅读主题的精致立体插画，绿色书本与金色光线，无文字、无字母、无数字。",key:key)
            let file = try await live.download(url,id:"live-test",directory:URL.temporaryDirectory.appending(path:"paperflow-1.8-live-image"))
            print("LIVE: GLM-Image 一次生成与下载成功："+file.path)
        } else { print("LIVE SKIPPED: Mac 的已知演示钥匙串中无可读取密钥；iPhone 钥匙串无法从 Mac 读取。") }
        print("ALL IMAGE COVER CHECKS PASSED")
    }
}
