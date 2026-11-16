import Foundation

/// 不联网、不读写钥匙串。验证推荐、标签、额度和在线迁移的业务边界。
@main struct IterationChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition:@autoclosure()->Bool,_ name:String) { guard condition() else { fatalError("FAIL: " + name) }; count += 1; print("PASS: " + name) }
        func blocked(_ operation:() throws -> Void,_ name:String) { do { try operation(); fatalError("FAIL: " + name) } catch { check(error is DemoLimit,name) } }
        var ledger = DemoLedger()
        for i in 1...3 { try ledger.reserve(id:"r\(i)",input:"abstract",output:500,paper:"p\(i)") }
        blocked({ try ledger.reserve(id:"r4",input:"abstract",output:500,paper:"p4") },"并行预留不能绕过三篇额度")
        check(ledger.quota.usedPapers == 0 && ledger.quota.reservedPapers == 3,"预留论文不冒充成功展示")
        ledger.settle(id:"r1",usage:TokenUsage(prompt_tokens:100,completion_tokens:20,total_tokens:120),billed:true,keepPaper:true)
        blocked({ try ledger.reserve(id:"r4",input:"a",output:100,paper:"p4") },"生成完成但尚未展示时仍保留论文名额")
        ledger.deliver("p1"); ledger.deliver("p1")
        check(ledger.quota.usedPapers == 1 && ledger.quota.reservedPapers == 2,"缓存重复展示只计一次")
        ledger.settle(id:"r1",usage:TokenUsage(total_tokens:120),billed:true)
        check(ledger.usedTokens == 120,"重复回执不重复计费")
        ledger.settle(id:"r2",usage:nil,billed:false); ledger.settle(id:"r3",usage:nil,billed:false)
        check(ledger.quota.reservedPapers == 0 && ledger.reservations.isEmpty,"未发送或被拒绝的失败释放预留")
        try ledger.reserve(id:"unknown",input:"abstract",output:100,paper:"failed")
        let reserved = ledger.quota.reservedTokens
        ledger.settle(id:"unknown",usage:nil,billed:true)
        check(ledger.usedTokens == 120 && ledger.quota.reservedTokens == reserved,"已发送但无 usage 的请求保留待确认预算")
        check(ledger.quota.usedPapers == 1,"失败不计成功论文")
        try ledger.reserve(id:"failed-format",input:"source",output:100,paper:"bad")
        ledger.settle(id:"failed-format",usage:TokenUsage(total_tokens:55),billed:true)
        check(ledger.usedTokens == 175 && ledger.quota.usedPapers == 1,"模型格式失败仍记录实际计费")
        var tokens = DemoLedger(); tokens.tokenLimit = 400
        blocked({try tokens.reserve(id:"too-large",input:"1234567890",output:200,paper:nil)},"预算不足时不发送请求")
        try tokens.reserve(id:"last",input:"a",output:100,paper:nil)
        tokens.settle(id:"last",usage:TokenUsage(total_tokens:400),billed:true)
        blocked({try tokens.reserve(id:"beyond",input:"a",output:1,paper:nil)},"Token 到顶后停止问答与翻译")
        var papers = DemoLedger(); papers.deliver("a"); papers.deliver("b"); papers.deliver("c")
        blocked({try papers.reserve(id:"beyond",input:"a",output:1,paper:nil)},"第三篇展示后停止所有后续演示调用")
        papers.topUp(); check(!papers.quota.exhausted && papers.paperLimit == 6 && papers.tokenLimit == 60000 && papers.transactions.count == 1,"模拟充值增加两类额度并记录无扣款交易")
        var concurrent = DemoLedger(); try concurrent.reserve(id:"first",input:"source",output:100,paper:"same")
        blocked({try concurrent.reserve(id:"duplicate",input:"source",output:100,paper:"same")},"同一篇处理中不重复发起模型调用")
        let restored = try JSONDecoder().decode(DemoLedger.self,from:JSONEncoder().encode(ledger))
        check(restored.usedTokens == 175 && restored.quota.reservedTokens == reserved && restored.delivered == ["p1"],"重新打开仍保留实际用量、待确认预算与篇数")
        check(TokenUsage(prompt_tokens:2,completion_tokens:3).total == 5 && TokenUsage().total == nil,"缺失 usage 不虚构精确 Token 数")

        let folder = URL.temporaryDirectory.appending(path:"PaperFlow-Iteration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let catalog = URL(fileURLWithPath:CommandLine.arguments[1])
        let app = AppStore(directory:folder,catalogURL:catalog)
        check(app.papers.isEmpty && app.state.history.isEmpty,"新安装不注入固定文献或虚构阅读记录")
        let preset = app.presetTopics[0]; app.state.homeFilter.topics.insert(preset); app.deleteTopic(preset)
        check(!app.availableTopics.contains(preset) && !app.state.interests.contains(preset) && !app.state.homeFilter.topics.contains(preset),"删除预设同步清理兴趣和筛选")
        check(app.addTopic("  Robotics  ") && !app.addTopic("robotics") && !app.addTopic("  "),"自定义兴趣去空白、去重与拒绝空白")
        app.state.homeFilter.topics = ["Robotics"]
        check(app.renameTopic("Robotics",to:"Robotics AI") && app.state.interests.contains("Robotics AI") && app.state.homeFilter.topics == ["Robotics AI"],"改名同步兴趣和筛选")
        _ = app.addTopic("HCI"); app.toggleTopicPin(app.state.customTopics.last!.id)
        check(app.customTopicNames.first == "HCI","置顶优先于自定义排序")
        app.deleteTopic("Robotics AI"); check(!app.state.homeFilter.topics.contains("Robotics AI"),"删除自定义同步清理筛选")
        await app.flushStorage()
        let reopened = AppStore(directory:folder,catalogURL:catalog)
        check(reopened.customTopicNames == app.customTopicNames && reopened.state.deletedPresetTopics == app.state.deletedPresetTopics,"兴趣及删除选择重启后保留")
        func paper(_ id:String,_ title:String,_ abstract:String) -> Paper {
            Paper(id:id,title:title,hook:title,subtitle:"",author:id,year:2026,journalID:"arxiv",topics:[],sourceURL:"https://arxiv.org/abs/\(id)",color:"FFFFFF",symbol:"doc",coverText:"",insights:[],abstractText:abstract)
        }
        let ai = paper("ai","Transformer neural machine learning","Neural transformer language representation models")
        let similar = paper("similar","Neural transformer representation","Language models learn a neural representation")
        let biology = paper("biology","Plant ecosystem measurement","Plants grow across a climate gradient")
        let set = [biology,similar,ai]
        var state = LocalState(); state.interests = ["机器学习"]
        check(RecommendationEngine.rank(set,state:state,refresh:0).first?.id == ai.id,"初始兴趣实际改变推荐排序")
        state.interests = []; state.readingSeconds["2026-10-24|ai"] = 5
        check(RecommendationEngine.engagement(ai,state:state) == 0,"短暂误点不作为有效阅读")
        state.readingSeconds["2026-10-24|ai"] = 90
        check(RecommendationEngine.score(similar,state:state,papers:set) > RecommendationEngine.score(biology,state:state,papers:set),"有效阅读提升相近论文排序")
        state.excludedTopics = ["机器学习"]
        check(RecommendationEngine.excluded(ai,state:state) && !RecommendationEngine.excluded(similar,state:state),"排除整个方向，不误伤只有通用单词的论文")
        state = LocalState(); state.interests = []; state.history = [ai.id]
        check(RecommendationEngine.score(ai,state:state,papers:set) < RecommendationEngine.score(biology,state:state,papers:set),"打开记录降低重复推荐，不持续置顶")
        check(!RecommendationEngine.queries(state:state,papers:set).isEmpty,"冷启动有多领域召回方向")
        let id = app.importPaper(ai)
        check(!app.recommendedContent(filter:ContentFilter()).contains { $0.id == "paper:" + id },"未处理文献不会进入首页")
        let generated = GeneratedReading(title:"中文研究标题",clarification:"标题是修辞表达。",body:"研究正文。",sourceLabel:"摘要",sourceText:"source",model:"test",provider:"fixture",createdAt:1,language:"简体中文")
        app.saveReading(generated,for:id,language:"简体中文")
        check(app.recommendedContent(filter:ContentFilter()).contains { $0.id == "paper:" + id },"准备好的结果可以进入首页")
        app.hideFromFeed("paper:" + id)
        check(app.content(query:"Transformer").contains { $0.id == "paper:" + id } && !app.recommendedContent(filter:ContentFilter()).contains { $0.id == "paper:" + id },"首页负反馈不影响主动搜索")
        app.toggleFollow("user:PaperFlow AI"); check(!app.state.following.contains("user:PaperFlow AI"),"不能跟踪 AI 身份")
        let comment = app.receiveComment("paper:"+id,author:"我",text:"",isMine:true,images:[Data([1,2])],paperID:id,page:2)
        check(comment != nil && app.comment(comment!,in:"paper:"+id)?.page == 2,"图片评论可单独发送并保留原文页码")
        app.recordUsage(UsageRecord(operation:"test",model:"test",provider:"fixture",mode:"个人",usage:TokenUsage(total_tokens:12),succeeded:true))
        app.recordUsage(UsageRecord(operation:"failed",model:"test",provider:"fixture",mode:"演示",usage:TokenUsage(total_tokens:3),succeeded:false))
        app.recordUsage(UsageRecord(operation:"unknown",model:"test",provider:"fixture",mode:"演示",usage:nil,succeeded:false))
        check(app.totalTokens == 15 && app.tokens(on:Date()) == 15,"累计与当天只记实际用量，计费失败也包含")
        await app.flushStorage()
        let saved = AppStore(directory:folder,catalogURL:catalog)
        check(saved.comment(comment!,in:"paper:"+id)?.images?.first == Data([1,2]),"图片评论重启后保留")
        check(saved.totalTokens == 15,"累计 Token 重启后保留")
        // 模拟从老版本升级，恢复已收藏的真实论文身份，其他示例论文不注入。
        var legacy = LocalState(); legacy.bookmarks = ["paper:rag":"待读"]; legacy.following = ["user:PaperFlow AI","author:Patrick Lewis"]; legacy.notes = ["rag":"私人笔记"]
        let legacyFolder = folder.appending(path:"legacy");try FileManager.default.createDirectory(at:legacyFolder,withIntermediateDirectories:true)
        try JSONEncoder().encode(legacy).write(to:legacyFolder.appending(path:"user-state-v1.json"))
        let migrated = AppStore(directory:legacyFolder,catalogURL:catalog)
        check(migrated.papers.map(\.id) == ["rag"] && migrated.paper("rag")?.localPDF == nil,"只迁移已保存的论文身份，原文改为在线获取")
        check(migrated.state.notes["rag"] == "私人笔记" && migrated.state.bookmarks["paper:rag"] == "待读" && migrated.state.following == ["author:Patrick Lewis"],"迁移保留用户资料并移除 AI 跟踪")
        print("ALL \(count) ITERATION CHECKS PASSED")
    }
}
