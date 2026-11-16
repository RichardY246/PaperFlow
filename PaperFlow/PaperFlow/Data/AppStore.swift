// 应用状态中心：保存收藏、跟踪、阅读与互动；网络服务在 Services 中独立实现。
import Foundation
import Observation

nonisolated private struct ContentCacheKey:Hashable {
    var query:String;var filter:ContentFilter;var entities:Bool;var recommended:Bool;var minute:Int
}

// @Observable 让 SwiftUI 自动刷新；@MainActor 保证界面状态只在主线程修改。
@MainActor @Observable
final class AppStore {
    let catalog: Catalog
    var state: LocalState { didSet { updateIndexes(from:oldValue); persist() } }
    var path: [Route] = []
    var tab = 0
    var profileSection = "阅读"
    var showingComposer = false
    var selectedReadingDate = Date()
    var storageError: String?
    var homeCursors: [String: String] = [:]
    var homeTopicOffset = 0
    var homeLoading = false
    var homeRequestID = UUID()
    var homeFinished = false
    var homeError: String?
    var homeWarnings: [String] = []
    var homeAnchor: String?
    var homeOrder: [String] = []
    var homeRefresh = 0 { didSet { cachedFeed = [:];contentCache = [:] } }
    var homeProgress = ""
    var homeButtonRevision = 0
    var quotaNotice = false
    var pendingExcerpt: CoverAsset?
    var excerptPaperID: String?
    var aiPendingIDs: Set<String> = []
    var aiErrors: [String: String] = [:]
    var aiPauseReason: String?
    @ObservationIgnored var imageJobs: [String:Task<ImageCoverRecord,Error>] = [:]
    @ObservationIgnored var imageTail: Task<Void,Never>?
    var imageBudget = ImageBudget()
    var imageActivity: Set<String> = []
    @ObservationIgnored var imageRecoveryTask:Task<Void,Never>?
    var imageRecoveryRunning = false
    var imageRecoveryStopRequested = false
    var imageRecoveryStatus = ""
    var configurationRevision = 0
    @ObservationIgnored var aiKeyAvailability:(revision:Int,mode:String,value:Bool)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let database: StateDatabase
    @ObservationIgnored private var saving: Task<Void,Never>?
    @ObservationIgnored private var paperIndex: [String:Paper] = [:]
    @ObservationIgnored private var paperList: [Paper] = []
    @ObservationIgnored private var journalIndex: [String:Journal] = [:]
    @ObservationIgnored private var cachedFeed: [String:[FeedItem]] = [:]
    @ObservationIgnored private var contentCache:[ContentCacheKey:[FeedItem]] = [:]
    @ObservationIgnored private var validReadings: [String:GeneratedReading] = [:]
    @ObservationIgnored private var pendingSeconds: [String: Int] = [:]
    static let topics = ["生成式 AI", "交互设计", "机器学习", "计算机视觉", "人机交互", "设计方法"]
    static let roles = ["本科生", "硕士生", "博士生", "教师", "研究人员", "从业者", "其他"]
    static let avatars = ["person.fill", "leaf.fill", "sun.max.fill", "moon.fill", "cat.fill", "bird.fill"]

    init(directory: URL? = nil, catalogURL: URL? = nil) {
        let directory = directory ?? URL.documentsDirectory.appending(path: "PaperFlow", directoryHint: .isDirectory)
        fileURL = directory.appending(path: "user-state-v1.json")
        database = StateDatabase(directory:directory)
        do {
            guard let url = catalogURL ?? Bundle.main.url(forResource: "DemoCatalog", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        } catch {
            catalog = Catalog(papers: [], journals: [], posts: [])
            state = LocalState()
            storageError = "示例数据未能载入：\(error.localizedDescription)"
            return
        }
        do {
            if let saved = try StateDatabase.load(directory) {
                state = saved;rebuildIndexes();applyDemoUpdates();migrateOnlineState();return
            }
        } catch { state = LocalState();storageError = "数据库读取失败，原文件已保留："+error.localizedDescription;return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let backup = directory.appending(path:"user-state-v1.pre-sqlite.json")
                if !FileManager.default.fileExists(atPath:backup.path) { try FileManager.default.copyItem(at:fileURL,to:backup) }
                state = try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: fileURL))
            }
            catch {
                state = LocalState()
                storageError = "已有数据暂时无法读取，原文件已保留。请先备份再重置。"
                return
            }
        } else {
            var initial = LocalState()
            initial.posts = catalog.posts
            state = initial
            persist()
        }
        rebuildIndexes()
        applyDemoUpdates()
        migrateOnlineState()
        persist()
    }

    private func applyDemoUpdates() {
        guard storageError == nil, state.demoRevision < 3 else { return }
        var updated = state
        for post in catalog.posts {
            if let index = updated.posts.firstIndex(where: { $0.id == post.id && !$0.isMine }) { updated.posts[index] = post }
            else if !updated.posts.contains(where: { $0.id == post.id }) { updated.posts.append(post) }
        }
        for (key, samples) in catalog.comments ?? [:] {
            let existing = Set(updated.comments[key, default: []].map(\.id))
            updated.comments[key, default: []].insert(contentsOf: samples.filter { !existing.contains($0.id) }, at: 0)
        }
        if updated.role == "设计学习者" || updated.role == "设计研究者" { updated.role = "本科生" }
        for key in Array(updated.comments.keys) {
            for index in updated.comments[key, default: []].indices where updated.comments[key]![index].isMine == nil {
                updated.comments[key]![index].isMine = updated.comments[key]![index].author == updated.nickname
            }
        }
        updated.demoRevision = 3
        state = updated
    }

    /// 合并同一交互内的状态变更，编码与磁盘写入交给数据库 actor。
    func persist() {
        guard storageError == nil else { return }
        saving?.cancel()
        let snapshot = state, database = database, previous = saving
        saving = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do { try await database.save(snapshot) }
            catch { self?.storageError = "保存失败，旧数据保留："+error.localizedDescription }
        }
    }
    func flushStorage() async { await saving?.value }
    private func updateIndexes(from old:LocalState) {
        contentCache = [:]
        if old.importedPapers != state.importedPapers { rebuildIndexes() }
        if old.generatedReadings != state.generatedReadings || old.targetLanguage != state.targetLanguage { validReadings = [:] }
        if old.importedPapers != state.importedPapers || old.interests != state.interests || old.excludedTopics != state.excludedTopics || old.readingSeconds != state.readingSeconds || old.reads != state.reads || old.likes != state.likes || old.bookmarks != state.bookmarks || old.following != state.following || old.posts != state.posts || old.hiddenFeedIDs != state.hiddenFeedIDs || old.history != state.history { cachedFeed = [:] }
    }
    private func rebuildIndexes() {
        paperIndex = Dictionary(catalog.papers.map { ($0.id,$0) },uniquingKeysWith:{$1})
        for paper in state.importedPapers { paperIndex[paper.id] = paper }
        let originals = Set(catalog.papers.map(\.id))
        paperList = catalog.papers.compactMap { paperIndex[$0.id] } + state.importedPapers.filter { !originals.contains($0.id) }
        journalIndex = Dictionary(catalog.journals.map { ($0.id,$0) },uniquingKeysWith:{$1})
        for paper in paperList where journalIndex[paper.journalID] == nil { journalIndex[paper.journalID] = Journal(id:paper.journalID,name:paper.journalTitle ?? paper.journalID,kind:"期刊与来源",intro:"来自在线检索结果。") }
    }
    var papers: [Paper] { paperList }
    var journals: [Journal] { journalIndex.values.sorted { $0.id < $1.id } }
    func paper(_ id:String) -> Paper? { paperIndex[id] }
    func post(_ id: String) -> UserPost? { state.posts.first { $0.id == id } }
    func journal(_ id: String) -> Journal? { journalIndex[id] }
    func journalName(_ id: String) -> String { journal(id)?.name ?? id }
    func go(_ route: Route) { path.append(route) }
    var published: [UserPost] { state.posts.filter { !$0.isDraft }.sorted { $0.timestamp > $1.timestamp } }
    var drafts: [UserPost] { state.posts.filter { $0.isDraft && $0.isMine } }

    func feed(kind: String = "混合推荐", includingExcluded:Bool = false) -> [FeedItem] {
        let cacheKey = kind+String(includingExcluded)+String(homeRefresh)
        if let cached = cachedFeed[cacheKey] { return cached }
        let sorted = RecommendationEngine.rank(papers,state:state,refresh:homeRefresh,includingExcluded:includingExcluded)
        if kind == "只看文献" { return sorted.map { .paper($0) } }
        let posts = published.sorted {
            let left = state.interests.contains($0.topic) ? 1 : 0
            let right = state.interests.contains($1.topic) ? 1 : 0
            return left == right ? $0.timestamp > $1.timestamp : left > right
        }
        if kind == "只看帖子" { return posts.map { .post($0) } }
        var result: [FeedItem] = []
        for i in 0..<max(sorted.count, posts.count * 2) {
            if i < sorted.count { result.append(.paper(sorted[i])) }
            if i % 2 == 1, i / 2 < posts.count { result.append(.post(posts[i / 2])) }
        }
        cachedFeed[cacheKey] = result
        return result
    }

    func toggleFollow(_ key: String) {
        guard key != "user:PaperFlow AI" else { return }
        if state.following.contains(key) { state.following.remove(key) } else { state.following.insert(key) }
    }
    func toggleLike(_ key: String) {
        if state.likes.contains(key) { state.likes.remove(key) } else { state.likes.insert(key) }
    }
    func bookmark(_ key: String, folder: String?) { state.bookmarks[key] = folder }
    func addFolder(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && !state.folders.contains(name) { state.folders.append(name) }
    }
    func savePost(_ value: UserPost) {
        var post = value
        if let old = self.post(post.id),old.images != post.images || old.imageNames != post.imageNames || old.coverImage != post.coverImage { post.mediaRevision = UUID().uuidString }
        if let i = state.posts.firstIndex(where: { $0.id == post.id }) { state.posts[i] = post }
        else { state.posts.append(post) }
    }
    /// 原图已经恢复时，只移除当前的未计费余额失败标记；旧调用审计继续保留。
    func resolveBalanceFailure(_ cacheID:String) {
        guard let record = state.imageGenerations[cacheID],record.isUnbilledBalanceFailure else { return }
        var updated = state
        if updated.imageCalls[record.requestID] == nil { updated.imageCalls[record.requestID] = record }
        updated.imageGenerations[cacheID] = nil
        state = updated
    }
    func deletePost(_ id: String) {
        guard post(id)?.isMine == true else { return }
        var updated = state
        updated.posts.removeAll { $0.id == id }
        updated.bookmarks.removeValue(forKey: "post:\(id)")
        updated.likes.remove("post:\(id)")
        let removed = Set(updated.comments["post:\(id)", default: []].map(\.id))
        updated.comments.removeValue(forKey: "post:\(id)")
        updated.likedCommentIDs.subtract(removed)
        updated.commentLikedAt = updated.commentLikedAt.filter { !removed.contains($0.key) }
        updated.notices.removeAll { $0.key == "post:\(id)" }
        updated.following.remove("post:\(id)")
        state = updated
    }
    // parentID 为空是新评论，有值是回复。自己的发言不触发“别人评论”的消息。
    func comment(_ key: String, text: String, parentID: String? = nil) {
        receiveComment(key, author: state.nickname, text: text, parentID: parentID, isMine: true)
    }

    func visit(_ id: String, date: Date = Date()) {
        guard paper(id) != nil else { return }
        var updated = state
        updated.history.removeAll { $0 == id }
        updated.history.insert(id, at: 0)
        updated.visitedAt[id] = date.timeIntervalSince1970
        state = updated
    }
    func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    func markRead(_ id: String, date: Date = Date()) {
        guard paper(id) != nil else { return }
        let day = dayKey(date)
        var updated = state
        updated.dismissedReads[day, default: []].removeAll { $0 == id }
        if !updated.reads[day, default: []].contains(id) {
            updated.reads[day, default: []].append(id)
            updated.readAt[day, default: [:]][id] = date.timeIntervalSince1970
        }
        state = updated
    }
    func isRead(_ id: String, date: Date = Date()) -> Bool { state.reads[dayKey(date), default: []].contains(id) }
    func toggleRead(_ id: String, date: Date = Date()) {
        guard paper(id) != nil else { return }
        if isRead(id, date: date) {
            let day = dayKey(date)
            var updated = state
            updated.reads[day, default: []].removeAll { $0 == id }
            updated.readAt[day]?[id] = nil
            if !updated.dismissedReads[day, default: []].contains(id) { updated.dismissedReads[day, default: []].append(id) }
            state = updated
            pendingSeconds["\(day)|\(id)"] = 0
        } else { markRead(id, date: date) }
    }
    func readingTick(_ id: String) {
        guard paper(id) != nil, !state.dismissedReads[dayKey(Date()), default: []].contains(id) else { return }
        let key = "\(dayKey(Date()))|\(id)"
        pendingSeconds[key, default: 0] += 1
        if pendingSeconds[key, default: 0] >= 30 {
            state.readingSeconds[key, default: 0] += pendingSeconds[key, default: 0]
            pendingSeconds[key] = 0
            markRead(id)
        }
    }
    var todaysCount: Int { state.reads[dayKey(Date()), default: []].count }
    var totalRead: Int { state.reads.values.reduce(0) { $0 + $1.count } }
    func label(_ key: String) -> String {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return key }
        switch parts[0] {
        case "paper": return paper(parts[1]).map { displayTitle($0) } ?? parts[1]
        case "post": return post(parts[1])?.title ?? "已移除的帖子"
        case "journal": return journalName(parts[1])
        default: return parts[1]
        }
    }
    func route(_ key: String) -> Route? {
        let p = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard p.count == 2 else { return nil }
        switch p[0] {
        case "paper": return .paper(p[1])
        case "post": return .post(p[1])
        case "journal": return .journal(p[1])
        case "author": return .author(p[1])
        case "user": return .user(p[1])
        case "topic": return .search(p[1])
        default: return nil
        }
    }
    func follows(_ paper: Paper) -> Bool {
        state.following.contains("paper:\(paper.id)") || state.following.contains("author:\(paper.author)")
        || state.following.contains("journal:\(paper.journalID)") || paper.topics.contains { state.following.contains("topic:\($0)") }
    }
    var followedPapers: [Paper] { papers.filter { follows($0) } }
    func completeOnboarding() {
        var updated = state
        let name = updated.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.nickname = name.isEmpty ? "好奇的读者" : name
        updated.school = updated.school.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.major = updated.major.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.completedOnboarding = true
        state = updated
    }
    /// 换语言、换接口或退到后台时，使旧任务失效；旧任务结束也不能清空新队列。
    func cancelAutomaticReadings() {
        homeRequestID = UUID(); homeLoading = false; homeProgress = ""; aiPendingIDs = []
    }
    func resetDemo() {
        storageError = nil
        let quota = state.demoQuota, usage = state.usageRecords, tokenTotal = state.tokenTotal, tokenDays = state.tokenDays
        var initial = LocalState(); initial.posts = catalog.posts; initial.demoQuota = quota; initial.usageRecords = usage; initial.tokenTotal = tokenTotal; initial.tokenDays = tokenDays; initial.imageConfiguration = state.imageConfiguration; initial.imageGenerations = state.imageGenerations;initial.imageCalls = state.imageCalls
        state = initial
        applyDemoUpdates()
        migrateOnlineState()
        pendingSeconds = [:]
        path = []; tab = 0
        homeRequestID = UUID(); homeLoading = false; homeAnchor = nil; homeOrder = []
        homeCursors = [:]; homeTopicOffset = 0; homeFinished = false; homeWarnings = []; homeError = nil
        cancelAutomaticReadings(); aiErrors = [:]; aiPauseReason = nil
    }


}

extension AppStore {
    func journalIDs(for post: UserPost) -> Set<String> {
        var ids = Set(post.links.filter { $0.hasPrefix("journal:") }.map { String($0.dropFirst(8)) })
        for key in post.links where key.hasPrefix("paper:") {
            if let paper = paper(String(key.dropFirst(6))) { ids.insert(paper.journalID) }
        }
        return ids
    }
    func topics(for post: UserPost) -> Set<String> {
        var topics = Set(post.links.filter { $0.hasPrefix("topic:") }.map { String($0.dropFirst(6)) })
        for key in post.links where key.hasPrefix("paper:") {
            if let paper = paper(String(key.dropFirst(6))) { topics.formUnion(paper.topics) }
        }
        return topics
    }
    private func matchesTime(_ timestamp: Double, filter: ContentFilter, now: Date) -> Bool {
        let days = ["近 7 天": 7, "近 30 天": 30, "近一年": 365][filter.time]
        guard let days, let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return true }
        return timestamp >= start.timeIntervalSince1970 && timestamp <= now.timeIntervalSince1970
    }
    private func paperTime(_ paper: Paper) -> Double {
        if let stamp = paper.publishedAt, let date = ISO8601DateFormatter().date(from: stamp) { return date.timeIntervalSince1970 }
        return Calendar.current.date(from: DateComponents(year: paper.year, month: 1, day: 1))?.timeIntervalSince1970 ?? 0
    }
    func accepts(_ paper: Paper, filter: ContentFilter, now: Date = Date()) -> Bool {
        let sources = Set(paper.retrievalSources ?? (paper.journalID == "arxiv" ? ["arXiv"] : []))
        let status = FullTextLinks.isVerified(paper) ? "可直接阅读全文" : (paper.fullTextStatus == "可直接阅读全文" ? "开放全文" : paper.fullTextStatus ?? (paper.pdfURL != nil ? "开放全文" : "未确认"))
        return (filter.sources.isEmpty || !filter.sources.isDisjoint(with:sources))
        && (filter.access == "全部" || filter.access == status || (filter.access == "开放全文" && status == "可直接阅读全文"))
        && (filter.journalQuery.isEmpty || (paper.journalTitle ?? journalName(paper.journalID)).localizedCaseInsensitiveContains(filter.journalQuery))
        && (filter.journals.isEmpty || filter.journals.contains(paper.journalID))
        && (filter.topics.isEmpty || filter.topics.contains { topic in
            if paper.topics.contains(topic) { return true }
            let words = LiteratureQuery(topic).words
            let text = paper.title + " " + (paper.abstractText ?? "")
            return !words.isEmpty && words.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        })
        && matchesTime(paperTime(paper), filter: filter, now: now)
    }
    func accepts(_ post: UserPost, filter: ContentFilter, now: Date = Date()) -> Bool {
        (filter.journals.isEmpty || !filter.journals.isDisjoint(with: journalIDs(for: post)))
        && (filter.topics.isEmpty || !filter.topics.isDisjoint(with: topics(for: post)))
        && matchesTime(post.timestamp, filter: filter, now: now)
    }
    func content(query: String = "", filter: ContentFilter? = nil, includeEntities: Bool = false, now: Date = Date(), recommended:Bool = false) -> [FeedItem] {
        let filter = filter ?? ContentFilter()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = state.revision // 保留 SwiftUI 对数据变更的观察；缓存只跳过计算。
        let cacheKey = ContentCacheKey(query:query,filter:filter,entities:includeEntities,recommended:recommended,minute:Int(now.timeIntervalSince1970/60))
        if let cached = contentCache[cacheKey] { return cached }
        func matches(_ text: String) -> Bool {
            query.isEmpty || query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
        }
        // 主动搜索保留负反馈内容；只有首页推荐应用“不感兴趣”。
        let source:[FeedItem] = recommended ? feed(includingExcluded:true) : (papers.map { .paper($0) } + published.map { .post($0) })
        let list = source.filter { item in
            switch item {
            case .paper(let p):
                return (filter.kind == "全部" || filter.kind == "文献") && accepts(p, filter: filter, now: now)
                && matches(filter.field == "标题" ? p.title + " " + displayTitle(p) : filter.field == "作者" ? p.author : [p.title, displayTitle(p), p.abstractText ?? "", p.hook, p.subtitle, p.coverText, p.id, p.author, p.journalTitle ?? journalName(p.journalID), p.topics.joined(separator: " ")].joined(separator: " "))
            case .post(let p):
                return (filter.kind == "全部" || filter.kind == "帖子") && accepts(p, filter: filter, now: now)
                && matches([p.title, p.body, p.author, p.links.joined(separator: " "), p.links.map { label($0) }.joined(separator: " "), journalIDs(for: p).map { journalName($0) }.joined(separator: " ")].joined(separator: " "))
            case .entity: return false
            }
        }
        var result = filter.sort == "最新" ? list.sorted { lhs, rhs in
            @MainActor func time(_ item: FeedItem) -> Double { switch item { case .paper(let p): return paperTime(p); case .post(let p): return p.timestamp; case .entity: return 0 } }
            return time(lhs) > time(rhs)
        } : query.isEmpty ? list : list.sorted { a,b in
            func score(_ item:FeedItem) -> Double { if case .paper(let paper) = item { return SearchRanking.score(paper,query:query) };return 0 }
            let left = score(a),right = score(b);return left == right ? a.id < b.id : left > right
        }
        if includeEntities {
            let related = papers.filter { accepts($0, filter: filter, now: now) }
            if filter.kind == "全部" || filter.kind == "学者" {
                for author in Set(related.map(\.author)).sorted() where matches(author) {
                    result.append(.entity(DiscoveryEntity(id: "author:\(author)", name: author, kind: "学者", detail: "\(related.filter { $0.author == author }.count) 篇文献", symbol: "person.fill")))
                }
            }
            if filter.kind == "全部" || filter.kind == "期刊" {
                for journal in journals where matches(journal.name) && related.contains(where: { $0.journalID == journal.id }) {
                    result.append(.entity(DiscoveryEntity(id: "journal:\(journal.id)", name: journal.name, kind: journal.kind, detail: "\(related.filter { $0.journalID == journal.id }.count) 篇文献", symbol: "books.vertical.fill")))
                }
            }
            if filter.kind == "全部" || filter.kind == "主题" {
                for topic in availableTopics where matches(topic) && related.contains(where: { $0.topics.contains(topic) }) {
                    result.append(.entity(DiscoveryEntity(id: "topic:\(topic)", name: topic, kind: "主题", detail: "\(related.filter { $0.topics.contains(topic) }.count) 篇文献", symbol: "number")))
                }
            }
        }
        if contentCache.count >= 16 { contentCache = [:] };contentCache[cacheKey] = result
        return result
    }
}

extension AppStore {
    func item(for key: String) -> FeedItem? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "paper": return paper(parts[1]).map { .paper($0) }
        case "post": return post(parts[1]).map { .post($0) }
        case "journal": return journal(parts[1]).map { .entity(DiscoveryEntity(id: key, name: $0.name, kind: $0.kind, detail: "期刊与来源", symbol: "books.vertical.fill")) }
        case "user": return .entity(DiscoveryEntity(id: key, name: parts[1], kind: "用户", detail: "阅读分享与讨论", symbol: "person.fill"))
        case "author": return .entity(DiscoveryEntity(id: key, name: parts[1], kind: "学者", detail: "相关文献与讨论", symbol: "person.fill"))
        case "topic": return .entity(DiscoveryEntity(id: key, name: parts[1], kind: "主题", detail: "相关文献与讨论", symbol: "number"))
        default: return nil
        }
    }
}

extension AppStore {
    func hasContent(_ key: String) -> Bool {
        if key.hasPrefix("post:") { return post(String(key.dropFirst(5))).map { !$0.isDraft } ?? false }
        if key.hasPrefix("paper:") { return paper(String(key.dropFirst(6))) != nil }
        return false
    }
    func isMyComment(_ comment: Comment) -> Bool { comment.isMine ?? (comment.author == state.nickname) }
    func comment(_ id: String, in key: String) -> Comment? { state.comments[key, default: []].first { $0.id == id } }
    func rootComments(_ key: String) -> [Comment] {
        state.comments[key, default: []].filter { $0.parentID == nil || comment($0.parentID!, in: key) == nil }
    }
    func rootID(for comment: Comment, in key: String) -> String {
        var current = comment
        var seen: Set<String> = [comment.id]
        while let parentID = current.parentID, !seen.contains(parentID), let parent = self.comment(parentID, in: key) {
            seen.insert(parentID)
            current = parent
        }
        return current.id
    }
    func replies(to root: Comment, in key: String) -> [Comment] {
        state.comments[key, default: []].filter { $0.id != root.id && rootID(for: $0, in: key) == root.id }.sorted { $0.timestamp < $1.timestamp }
    }
    @discardableResult
    func receiveComment(_ key: String, author: String, text: String, parentID: String? = nil, isMine: Bool = false, date: Date = Date(), images: [Data] = [], paperID: String? = nil, page: Int? = nil) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasContent(key), !trimmed.isEmpty || !images.isEmpty else { return nil }
        let parent = parentID.flatMap { comment($0, in: key) }
        guard parentID == nil || parent != nil else { return nil }
        var entry = Comment(author: author, text: trimmed)
        entry.parentID = parentID; entry.isMine = isMine; entry.timestamp = date.timeIntervalSince1970
        entry.images = Array(images.prefix(1)); entry.paperID = paperID; entry.page = page
        var updated = state
        updated.comments[key, default: []].append(entry)
        if !isMine {
            let repliedToMe = parent.map { isMyComment($0) } ?? false
            let ownPost = key.hasPrefix("post:") && post(String(key.dropFirst(5)))?.isMine == true
            if repliedToMe || ownPost || updated.following.contains(key) {
                let title = repliedToMe ? "\(author) 回复了你的评论" : ownPost ? "\(author) 评论了你的帖子" : parent != nil ? "\(author) 在跟踪内容下回复了评论" : "\(author) 评论了你跟踪的内容"
                updated.notices.insert(InteractionNotice(key: key, commentID: entry.id, title: title, text: trimmed.isEmpty ? "图片评论" : trimmed, timestamp: entry.timestamp), at: 0)
            }
        }
        state = updated
        return entry.id
    }
    func toggleCommentLike(_ id: String, in key: String, date: Date = Date()) {
        guard comment(id, in: key) != nil else { return }
        var updated = state
        if updated.likedCommentIDs.contains(id) {
            updated.likedCommentIDs.remove(id); updated.commentLikedAt.removeValue(forKey: id)
        } else {
            updated.likedCommentIDs.insert(id); updated.commentLikedAt[id] = date.timeIntervalSince1970
        }
        state = updated
    }
    func commentLikeCount(_ comment: Comment) -> Int { max(0, comment.baseLikes ?? 0) + (state.likedCommentIDs.contains(comment.id) ? 1 : 0) }
    func commentActivities(replied: Bool) -> [CommentActivity] {
        var activities: [CommentActivity] = []
        for (key, comments) in state.comments where hasContent(key) {
            for entry in comments {
                if replied, isMyComment(entry), let parentID = entry.parentID, let parent = comment(parentID, in: key) {
                    activities.append(CommentActivity(key: key, comment: parent, reply: entry, timestamp: entry.timestamp))
                } else if !replied, state.likedCommentIDs.contains(entry.id) {
                    activities.append(CommentActivity(key: key, comment: entry, timestamp: state.commentLikedAt[entry.id] ?? entry.timestamp))
                }
            }
        }
        return activities.sorted { $0.timestamp > $1.timestamp }
    }
    var followedPosts: [UserPost] { published.filter { state.following.contains("post:\($0.id)") } }
    var relatedPosts: [UserPost] {
        published.filter { p in state.following.contains("post:\(p.id)") || state.following.contains("user:\(p.author)") || p.links.contains { state.following.contains($0) } || !journalIDs(for: p).isDisjoint(with: state.following.filter { $0.hasPrefix("journal:") }.map { String($0.dropFirst(8)) }) }
    }
    var unreadNoticeCount: Int { state.notices.filter { !state.readMessages.contains($0.id) }.count }
    func markAllMessagesRead() { state.readMessages.formUnion(state.notices.map(\.id) + followedPapers.map(\.id) + ["welcome"]) }
    func openNotice(_ notice: InteractionNotice) {
        state.readMessages.insert(notice.id)
        if hasContent(notice.key) { go(.discussion(notice.key, notice.commentID)) }
    }
    @discardableResult
    func simulateFollowedPostActivity() -> Bool {
        guard let target = followedPosts.first else { return false }
        let key = "post:\(target.id)"
        let own = state.comments[key, default: []].last { isMyComment($0) }
        let parent = own ?? rootComments(key).first
        let isReply = state.demoActivityIndex % 2 == 1
        let names = ["半页笔记", "晚点再读", "阿青"]
        let index = state.comments[key, default: []].count % names.count
        let text = isReply ? "我也有类似的想法，想把这个问题和原文的实验放在一起看看。" : "刚看完这条分享，我会先读关联论文的图表，再带着问题回到正文。"
        guard receiveComment(key, author: names[index], text: text, parentID: isReply ? parent?.id : nil) != nil else { return false }
        // 这个事件由用户点击“演示更新”产生，尚未连接真实社区服务器。
        state.demoActivityIndex += 1
        return true
    }
}


// MARK: - 在线论文与 AI 缓存
extension AppStore {
    /// 合并元数据时保留原有 ID，已有收藏、评论和阅读记录不会因数据源变化而失效。
    @discardableResult
    func importPaper(_ incoming: Paper) -> String {
        if let existing = papers.first(where: { PaperIdentity.same($0, incoming) }) {
            let merged = PaperIdentity.merge(existing, incoming)
            if merged != existing {
                if let index = state.importedPapers.firstIndex(where: { $0.id == existing.id }) { state.importedPapers[index] = merged }
                else { state.importedPapers.append(merged) }
            }
            return existing.id
        }
        state.importedPapers.append(incoming)
        return incoming.id
    }
    @discardableResult
    func importPapers(_ incoming:[Paper]) -> [String] {
        var list = state.importedPapers, ids:[String] = []
        for paper in incoming {
            if let index = list.firstIndex(where:{PaperIdentity.same($0,paper)}) { ids.append(list[index].id);list[index] = PaperIdentity.merge(list[index],paper) }
            else if let original = catalog.papers.first(where:{PaperIdentity.same($0,paper)}) { let merged = PaperIdentity.merge(original,paper);list.append(merged);ids.append(original.id) }
            else { list.append(paper);ids.append(paper.id) }
        }
        if list != state.importedPapers { state.importedPapers = list }
        return ids
    }
    static func paperIdentity(_ paper: Paper) -> String { PaperIdentity.primary(paper) }
    func reading(_ id: String, language: String? = nil) -> GeneratedReading? {
        let language = language ?? state.targetLanguage
        let cacheKey = id+"|"+language
        if let saved = validReadings[cacheKey] { return saved }
        if let saved = state.generatedReadings[id + "|" + language], [saved.title,saved.clarification,saved.body].allSatisfy({ ReadingLanguages.accepts($0,language:language) }) { validReadings[cacheKey] = saved;return saved }
        if language == "简体中文" { return state.generatedReadings[id] }
        return nil
    }
    func saveReading(_ value: GeneratedReading, for id: String, language: String) { state.generatedReadings[id + "|" + language] = value }
    func hasPreparedReading(_ paper: Paper) -> Bool { reading(paper.id) != nil }
    func displayTitle(_ paper: Paper) -> String {
        if let reading = reading(paper.id) { return reading.title }

        return paper.title
    }
    func displayCover(_ paper: Paper) -> String { reading(paper.id)?.coverText ?? (state.targetLanguage == "English" ? "READ" : state.targetLanguage == "繁體中文" ? "讀點新知" : "读点新知") }
    func hideFromFeed(_ key: String) { state.hiddenFeedIDs.insert(key) }
    func recommendedContent(filter: ContentFilter, preservingOrder:Bool = true) -> [FeedItem] {
        let candidates = content(filter: filter,recommended:true).filter { item in
            guard !state.hiddenFeedIDs.contains(item.id) else { return false }
            if case .paper(let paper) = item { return hasPreparedReading(paper) && !RecommendationEngine.excluded(paper,state:state) }
            return true
        }
        guard preservingOrder && !homeOrder.isEmpty else { return candidates }
        var remaining = Dictionary(candidates.map { ($0.id,$0) },uniquingKeysWith:{a,_ in a})
        let stable = homeOrder.compactMap { remaining.removeValue(forKey:$0) }
        return stable + candidates.filter { remaining[$0.id] != nil }
    }
}
