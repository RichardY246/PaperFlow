import Foundation

extension AppStore {
    func recoverDemoSession() {
        for (id,var record) in state.imageGenerations where record.status == "requesting" {
            record.status = "unknown";record.message = ImageCoverError.uncertain.localizedDescription;state.imageGenerations[id] = record;state.imageCalls[record.requestID] = record
        }
        do {
            var ledger = try DemoAccess.load()
            // 进程已重启，没有仍在执行的论文任务；未知计费预算继续保留。
            if !ledger.pendingPapers.isEmpty { ledger.pendingPapers = [:]; try DemoAccess.save(ledger) }
            state.demoQuota = ledger.quota;imageBudget = ledger.imageBudget ?? ImageBudget()
        } catch { aiPauseReason = error.localizedDescription }
    }
    var isDemo: Bool { state.apiMode != "personal" }
    var activeAIConfiguration: AIConfiguration { isDemo ? AIConfiguration() : state.aiConfiguration }
    func refreshQuota() {
        do { let ledger = try DemoAccess.load();state.demoQuota = ledger.quota;imageBudget = ledger.imageBudget ?? ImageBudget() }
        catch { aiPauseReason = error.localizedDescription }
    }
    func hasAIKey() -> Bool {
        if let cached = aiKeyAvailability,cached.revision == configurationRevision,cached.mode == state.apiMode { return cached.value }
        let value = isDemo ? !((try? DemoAccess.key()) ?? "").isEmpty : !((try? APIKeyStore.read(state.aiConfiguration)) ?? "").isEmpty
        aiKeyAvailability = (configurationRevision,state.apiMode,value);return value
    }
    func performAI<T>(operation:String,paperID:String? = nil,input:String,preparingPaper:Bool = false,forceDemo:Bool = false,keyOverride:String? = nil,
                      action:(AIService,AIConfiguration,String) async throws -> T) async throws -> T {
        let demo = forceDemo || isDemo, ticket = UUID().uuidString
        let config = demo ? AIConfiguration() : state.aiConfiguration
        let key = try keyOverride ?? (demo ? DemoAccess.key() : APIKeyStore.read(config))
        guard !key.isEmpty else { throw ServiceError.message(demo ? "请先设置课堂演示密钥，或配置个人 API。" : "请先配置个人 API。") }
        if demo {
            var ledger = try DemoAccess.load()
            do { try ledger.reserve(id:ticket,input:input + String(repeating:" ",count:3000),output:IterationConfig.maxOutputTokens,paper:preparingPaper ? paperID : nil) }
            catch { if case DemoLimit.reached = error { quotaNotice = true }; state.demoQuota = ledger.quota; throw error }
            try DemoAccess.save(ledger); state.demoQuota = ledger.quota
        }
        let service = AIService()
        let result:T
        do { result = try await action(service,config,key) }
        catch {
            try? finishRequest(service,operation:operation,id:ticket,demo:demo,config:config,paperID:paperID,succeeded:false)
            throw error
        }
        // 结算与网络异常分开，避免钥匙串写入失败时把同一请求计费两次。
        try finishRequest(service,operation:operation,id:ticket,demo:demo,config:config,paperID:paperID,succeeded:true)
        return result
    }
    private func finishRequest(_ service:AIService,operation:String,id:String,demo:Bool,config:AIConfiguration,paperID:String?,succeeded:Bool) throws {
        if demo {
            var ledger = try DemoAccess.load()
            ledger.settle(id:id,usage:service.lastUsage,billed:service.sentRequest && !service.rejected,keepPaper:succeeded)
            try DemoAccess.save(ledger); state.demoQuota = ledger.quota
        }
        if service.sentRequest {
            recordUsage(UsageRecord(operation:operation,model:config.model,provider:URL(string:config.baseURL)?.host ?? "",mode:demo ? "演示" : "个人",paperID:paperID,usage:service.lastUsage,succeeded:succeeded))
        }
    }
    func deliverDemoPaper(_ id:String) throws {
        guard reading(id)?.accessMode == "demo" else { return }
        var ledger = try DemoAccess.load(); ledger.deliver(id); try DemoAccess.save(ledger); state.demoQuota = ledger.quota
        if ledger.quota.exhausted { quotaNotice = true }
    }
    func abandonDemoPaper(_ id:String) {
        guard var ledger = try? DemoAccess.load(), ledger.pendingPapers.values.contains(id) else { return }; ledger.abandon(id); try? DemoAccess.save(ledger); state.demoQuota = ledger.quota
    }
    func generateReading(_ paper:Paper,requireFullText:Bool = false) async throws -> GeneratedReading {
        if requireFullText || PaperFileService.localURL(paper) == nil {
            if requireFullText { do { _ = try await obtainFullText(paper.id,allowLookup:false) } catch { if Task.isCancelled { throw CancellationError() }; throw FullTextUnavailable(message:error.localizedDescription) } }
            else { _ = try? await obtainFullText(paper.id) }
        }
        try Task.checkCancellation()
        guard let source = PaperFileService.readingSource(paper) else { throw ServiceError.message("暂缺摘要或可读取的原文，请先获取原文。") }
        let figures = [FigureCandidate]() // 封面独立加载，不再占用正文生成的等待链。
        let language = state.targetLanguage, mode = isDemo ? "demo" : "personal"
        var reading = try await performAI(operation:"文献概览",paperID:paper.id,input:source.text + FigureRanking.prompt(figures),preparingPaper:true) { service,config,key in
            try await service.generate(paper:paper,source:source,configuration:config,key:key,language:language,figures:figures)
        }
        if Task.isCancelled { if mode == "demo" { abandonDemoPaper(paper.id) }; throw CancellationError() }
        reading.accessMode = mode; return reading
    }
    func askPaper(_ paper:Paper,question:String) async throws -> (String,TokenUsage?) {
        guard let source = PaperFileService.readingSource(paper) else { throw ServiceError.message("暂缺可用资料。") }
        let language = state.targetLanguage
        return try await performAI(operation:"问答",paperID:paper.id,input:source.text + question) { service,config,key in
            let result = try await service.answer(question:question,paper:paper,source:source,configuration:config,key:key,language:language)
            return (result,service.lastUsage)
        }
    }
    func simulateRecharge() throws {
        var ledger = try DemoAccess.load(); ledger.topUp(); try DemoAccess.save(ledger); state.demoQuota = ledger.quota; imageBudget = ledger.imageBudget ?? ImageBudget(); quotaNotice = false; aiPauseReason = nil
    }
}
