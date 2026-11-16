import Foundation

/// 一次刷新先召回、排序、生成，再发布。请求取消或失败不会清空已经可读的卡片。
extension AppStore {
    func loadHomeNext(filter: ContentFilter, refresh: Bool = false, service: FederatedLiteratureService? = nil, keyAvailable:(() -> Bool)? = nil) async {
        guard (!homeLoading && !homeFinished) || refresh else { return }
        guard filter.kind == "全部" || filter.kind == "文献" else { if refresh { cancelAutomaticReadings() }; return }
        let requestID = UUID(); homeRequestID = requestID
        let language = state.targetLanguage, configRevision = configurationRevision
        homeLoading = true; homeError = nil; homeProgress = "正在寻找相关文献…"
        defer { if homeRequestID == requestID { homeLoading = false; homeProgress = "" } }
        if refresh { homeCursors = [:]; homeTopicOffset = 0; homeFinished = false; homeRefresh += 1 }
        let topics = filter.topics.isEmpty ? RecommendationEngine.queries(state:state,papers:papers) : filter.topics.sorted()
        let topic = topics[(homeTopicOffset + homeRefresh) % max(topics.count,1)]
        var networkFilter = filter; networkFilter.topics = []
        if networkFilter.access == "全部" { networkFilter.access = "开放全文" }
        do {
            let result = try await (service ?? .shared).search(query:topic,filter:networkFilter,cursors:homeCursors.isEmpty ? nil : homeCursors,openAlexKey:LibraryKeyStore.read(),coreKey:LibraryKeyStore.read("CORE"),refresh:refresh)
            try Task.checkCancellation()
            guard homeRequestID == requestID, language == state.targetLanguage, configRevision == configurationRevision else { return }
            let ids = importPapers(result.papers)
            let incoming = ids.compactMap { self.paper($0) }
            homeCursors = result.next
            if result.next.isEmpty { homeTopicOffset += 1; homeFinished = homeTopicOffset >= max(topics.count,1) }
            homeWarnings = result.warnings
            let ranked = RecommendationEngine.rank(incoming,state:state,refresh:homeRefresh,history:papers)
            let choices = ranked.filter { !hasPreparedReading($0) || !homeOrder.contains("paper:" + $0.id) || reading($0.id)?.mediaVersion != 2 }.sorted { a,b in !FullTextLinks.candidates(a).isEmpty && FullTextLinks.candidates(b).isEmpty }
            var ready: [String] = []; var errors: [String] = []
            var attempted = 0
            for paper in choices {
                var preparing = false
                defer { if preparing { abandonDemoPaper(paper.id) } }
                try Task.checkCancellation()
                guard homeRequestID == requestID, language == state.targetLanguage, configRevision == configurationRevision else { return }
                if ready.count >= IterationConfig.feedBatchSize { break }
                if attempted >= 8 { break }; attempted += 1
                if !hasPreparedReading(paper) || reading(paper.id)?.mediaVersion != 2 {
                    guard keyAvailable?() ?? hasAIKey() else { homeError = "先配置个人 API，或设置课堂演示密钥，即可生成可直接阅读的推荐。"; break }
                    if isDemo, (try? DemoAccess.load().quota.exhausted) == true { quotaNotice = true; break }
                    homeProgress = "正在准备可阅读内容 \(ready.count + 1) / \(IterationConfig.feedBatchSize)…"
                    do {
                        homeProgress = "正在验证原文并选择核心图…"
                        let generated = try await generateReading(paper,requireFullText:true)
                        preparing = true
                        try Task.checkCancellation()
                        guard homeRequestID == requestID, configRevision == configurationRevision else { return }
                        saveReading(generated,for:paper.id,language:language)
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        if case DemoLimit.reached = error { quotaNotice = true; break }
                        errors.append(error.localizedDescription)
                        // 全局配置错误时停止一批，防止连续消耗；单篇资料不足则跳过。
                        if !(error is FullTextUnavailable) && !error.localizedDescription.contains("摘要") && !error.localizedDescription.contains("资料") { break }
                        continue
                    }
                }
                if !FullTextLinks.isVerified(self.paper(paper.id) ?? paper) {
                    do { _ = try await obtainFullText(paper.id,allowLookup:false) }
                    catch { if Task.isCancelled { throw CancellationError() }; errors.append(error.localizedDescription); continue }
                }
                ready.append("paper:" + paper.id)
                try deliverDemoPaper(paper.id)
            }
            guard homeRequestID == requestID else { return }
            if refresh {
                let existing = recommendedContent(filter:filter,preservingOrder:false).map(\.id).filter { !ready.contains($0) }
                homeOrder = ready + existing
            } else { homeOrder = Array(NSOrderedSet(array:homeOrder + ready)) as? [String] ?? homeOrder }
            if ready.isEmpty && homeError == nil { homeError = errors.first ?? (result.warnings.isEmpty ? "暂时没有新的可读文献，可调整兴趣或重试。" : result.warnings.joined(separator:"\n")) }
        } catch { if !Task.isCancelled && homeRequestID == requestID { homeError = error.localizedDescription } }
    }
}
