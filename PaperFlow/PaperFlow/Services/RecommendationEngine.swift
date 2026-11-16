import Foundation

/// 可解释的内容推荐：兴趣与有效阅读形成画像，排序时混入少量探索内容。
enum RecommendationEngine {
    static let aliases = ["生成式 AI":"generative artificial intelligence", "交互设计":"interaction design", "机器学习":"machine learning", "计算机视觉":"computer vision", "人机交互":"human computer interaction", "设计方法":"design methods"]
    static func terms(_ text: String) -> Set<String> {
        let stop: Set<String> = ["the","with","from","this","that","using","paper","study","have","been","their","into","through","based","model","models","results"]
        return Set(text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 3 && !stop.contains($0) })
    }
    private static let wordCache = NSCache<NSString,WordSet>()
    private final class WordSet { let value:Set<String>;init(_ value:Set<String>) { self.value = value } }
    static func words(_ p:Paper) -> Set<String> {
        let key = [p.title,p.abstractText ?? "",p.topics.joined(separator:" ")].joined(separator:" ") as NSString
        if let cached = wordCache.object(forKey:key) { return cached.value }
        let value = terms(key as String);wordCache.countLimit = 2000;wordCache.setObject(WordSet(value),forKey:key);return value
    }
    static func engagement(_ p: Paper, state: LocalState) -> Double {
        var value = 0.0
        let seconds = state.readingSeconds.filter { $0.key.hasSuffix("|" + p.id) }.values.reduce(0,+)
        if seconds >= 30 { value += min(3,Double(seconds)/60) }
        if state.reads.values.contains(where: { $0.contains(p.id) }) { value += 2 }
        if state.likes.contains("paper:" + p.id) { value += 3 }
        if state.bookmarks["paper:" + p.id] != nil { value += 4 }
        return value
    }
    struct Affinity { var paper:Paper; var weight:Double; var words:Set<String> }
    static func affinities(_ papers:[Paper],state:LocalState) -> [Affinity] {
        papers.compactMap { paper in let weight = engagement(paper,state:state); return weight > 0 ? Affinity(paper:paper,weight:weight,words:words(paper)) : nil }
    }
    static func score(_ p: Paper, state: LocalState, papers: [Paper], context:[Affinity]? = nil) -> Double {
        let words = words(p)
        var value = FullTextLinks.isVerified(p) ? 3.0 : 0.0
        for interest in state.interests.subtracting(state.excludedTopics) {
            let tokens = terms((aliases[interest] ?? interest) + " " + interest)
            value += Double(tokens.intersection(words).count) * 5
            if p.topics.contains(interest) { value += 12 }
        }
        for affinity in context ?? affinities(papers,state:state) {
            let read = affinity.paper, weight = affinity.weight
            if read.id != p.id {
                let other = affinity.words
                value += weight * Double(words.intersection(other).count) / Double(max(1,words.union(other).count)) * 15
                if p.journalID == read.journalID { value += weight * 0.4 }
            }
        }
        if state.following.contains("author:" + p.author) { value += 8 }
        if state.following.contains("journal:" + p.journalID) { value += 8 }
        if p.topics.contains(where: { state.following.contains("topic:" + $0) }) { value += 8 }
        if state.history.contains(p.id) { value -= 5 }
        if state.reads.values.contains(where: { $0.contains(p.id) }) { value -= 10 }
        return value
    }
    static func excluded(_ p: Paper, state: LocalState) -> Bool {
        state.hiddenFeedIDs.contains("paper:" + p.id) || state.excludedTopics.contains { topic in
            let tokens = terms(aliases[topic] ?? topic)
            return p.topics.contains(topic) || (!tokens.isEmpty && tokens.isSubset(of:words(p)))
        }
    }
    static func rank(_ papers: [Paper], state: LocalState, refresh: Int, includingExcluded:Bool = false, history:[Paper]? = nil) -> [Paper] {
        let all = includingExcluded ? papers : papers.filter { !excluded($0,state:state) }
        let context = affinities(history ?? papers,state:state)
        let scores = Dictionary(all.map { ($0.id,score($0,state:state,papers:papers,context:context)) },uniquingKeysWith:{a,_ in a})
        let scored = all.sorted { a,b in
            let sa = scores[a.id] ?? 0, sb = scores[b.id] ?? 0
            if sa != sb { return sa > sb }
            return a.id < b.id
        }
        guard scored.count > 5 else { return scored }
        var result = scored
        let index = 4 + abs(refresh) % (scored.count - 4)
        let exploratory = result.remove(at:index); result.insert(exploratory,at:4)
        return result
    }
    static func queries(state: LocalState, papers: [Paper]) -> [String] {
        var result = state.interests.subtracting(state.excludedTopics).sorted()
        let strong = papers.filter { engagement($0,state:state) >= 2 }.sorted { engagement($0,state:state) > engagement($1,state:state) }
        for p in strong.prefix(3) {
            let terms = p.title.components(separatedBy: .alphanumerics.inverted).filter { $0.count > 3 }.prefix(5).joined(separator:" ")
            if !terms.isEmpty { result.insert(terms,at:0) }
        }
        return result.isEmpty ? ["recent interdisciplinary research", "human computer interaction", "generative artificial intelligence"] : Array(NSOrderedSet(array:result)) as? [String] ?? result
    }
    static func reason(_ p:Paper,state:LocalState,papers:[Paper]) -> String {
        let matched = state.interests.filter { topic in p.topics.contains(topic) || !terms(aliases[topic] ?? topic).isDisjoint(with:words(p)) }.sorted()
        if !matched.isEmpty { return "与你选择的兴趣有关：" + matched.joined(separator:"、") + "。收藏、点赞和有效阅读会继续调整推荐。" }
        if papers.contains(where:{ $0.id != p.id && engagement($0,state:state) > 0 }) { return "根据你读过、收藏或点赞的文献，比较标题、摘要、主题与期刊后推荐；也保留少量新方向。" }
        return "这是多领域探索内容。设置兴趣、阅读或收藏后，推荐会逐步调整。"
    }
}
