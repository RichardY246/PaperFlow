import Foundation

struct LiteratureResults: Codable {
    var papers: [Paper]
    var fetchedAt: Double
    var fromCache = false
}

/// 第一个在线数据源先采用 arXiv。搜索缓存保存在本机，原文只在打开时下载。
@MainActor
final class LiteratureService {
    static let shared = LiteratureService()
    private let session: URLSession
    private let cacheURL: URL
    private var cache: [String: LiteratureResults] = [:]
    private var nextRequest = Date.distantPast
    init(session: URLSession = .shared, directory: URL? = nil) {
        self.session = session
        cacheURL = (directory ?? URL.documentsDirectory.appending(path: "PaperFlow")).appending(path: "literature-search.json")
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([String: LiteratureResults].self, from: data) { cache = saved }
    }
    static func searchURL(_ query: String) -> URL {
        let translated = query.replacingOccurrences(of: "人机交互", with: "human computer interaction")
            .replacingOccurrences(of: "交互设计", with: "interaction design")
            .replacingOccurrences(of: "生成式 AI", with: "generative AI")
            .replacingOccurrences(of: "机器学习", with: "machine learning")
            .replacingOccurrences(of: "计算机视觉", with: "computer vision")
        let words = translated.prefix(200).split(whereSeparator: { $0.isWhitespace }).prefix(10)
        let search = words.isEmpty ? "cat:cs.HC OR cat:cs.AI" : words.map {
            "all:\"" + $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "") + "\""
        }.joined(separator: " AND ")
        var parts = URLComponents(string: "https://export.arxiv.org/api/query")!
        parts.queryItems = [URLQueryItem(name: "search_query", value: search), URLQueryItem(name: "max_results", value: "20"),
                            URLQueryItem(name: "sortBy", value: "submittedDate"), URLQueryItem(name: "sortOrder", value: "descending")]
        return parts.url!
    }
    func clearCache() {
        cache = [:]
        try? FileManager.default.removeItem(at: cacheURL)
    }
    func search(_ query: String, refresh: Bool = false) async throws -> LiteratureResults {
        let cacheKey = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !refresh, var saved = cache[cacheKey], Date().timeIntervalSince1970 - saved.fetchedAt < 86400 {
            saved.fromCache = true; return saved
        }
        // arXiv 要求请求间留出间隔。提前预约时间，连续点击也不会同时发送多次。
        let delay = max(0, nextRequest.timeIntervalSinceNow)
        nextRequest = Date().addingTimeInterval(delay + 3)
        try await Task.sleep(for: .seconds(delay))
        try Task.checkCancellation()
        var request = URLRequest(url: Self.searchURL(query)); request.timeoutInterval = 35
        request.setValue("PaperFlow/1.3 (educational literature reader)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw ServiceError.message("arXiv 暂时无法搜索，请稍后重试或使用文献网站入口。")
            }
            let papers = try Self.parse(data)
            let result = LiteratureResults(papers: papers, fetchedAt: Date().timeIntervalSince1970)
            cache[cacheKey] = result
            // 最多保留 30 次检索，避免搜索缓存一直增长。
            if cache.count > 30, let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { cache.removeValue(forKey: oldest) }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bytes = try? JSONEncoder().encode(cache) { try? bytes.write(to: cacheURL, options: .atomic) }
            return result
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if var saved = cache[cacheKey] { saved.fromCache = true; return saved }
            throw error
        }
    }
    static func parse(_ data: Data) throws -> [Paper] {
        let delegate = ArxivParser()
        let parser = XMLParser(data: data); parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.hasAPIError else { throw ServiceError.message("文献服务返回的数据无法读取，请稍后重试。") }
        return delegate.papers
    }
}

/// XMLParser 会分段交付文字，因此使用 += 收集，避免长摘要被截断。
private final class ArxivParser: NSObject, XMLParserDelegate {
    var papers: [Paper] = []
    var hasAPIError = false
    private var insideEntry = false
    private var insideAuthor = false
    private var element = ""
    private var fields: [String: String] = [:]
    private var authors: [String] = []
    private var author = ""
    private var categories: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        if elementName == "entry" { insideEntry = true; fields = [:]; authors = []; categories = [] }
        guard insideEntry else { return }
        if elementName == "author" { insideAuthor = true; author = "" }
        if elementName == "category", let term = attributeDict["term"] { categories.append(term) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideEntry else { return }
        if insideAuthor && element == "name" { author += string }
        else if ["id", "title", "summary", "published", "arxiv:doi", "arxiv:journal_ref"].contains(element) { fields[element, default: ""] += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "author", insideEntry { authors.append(clean(author)); insideAuthor = false }
        guard elementName == "entry" else { return }
        insideEntry = false
        let rawID = fields["id", default: ""]
        guard let range = rawID.range(of: "arxiv.org/abs/") else { hasAPIError = true; return }
        let id = clean(String(rawID[range.upperBound...])).replacingOccurrences(of: #"v[0-9]+$"#, with: "", options: .regularExpression)
        let title = clean(fields["title", default: ""])
        guard !title.isEmpty, !id.isEmpty else { return }
        let summary = clean(fields["summary", default: ""])
        let date = clean(fields["published", default: ""])
        let topics = Array(Set(categories.map { category in
            switch category {
            case "cs.HC": return "人机交互"
            case "cs.CV": return "计算机视觉"
            case "cs.AI", "cs.CL": return "生成式 AI"
            case "cs.LG", "stat.ML": return "机器学习"
            default: return category
            }
        })).sorted()
        let paper = Paper(id: "arxiv-" + id.replacingOccurrences(of: "/", with: "-"), title: title, hook: title,
                          subtitle: "来自 arXiv 的在线文献", author: authors.first ?? "作者未提供", year: Int(date.prefix(4)) ?? 0,
                          journalID: "arxiv", topics: topics, sourceURL: "https://arxiv.org/abs/" + id,
                          pdfURL: "https://arxiv.org/pdf/" + id, color: "DFEAE4", symbol: "doc.text", coverText: "arXiv",
                          insights: [], abstractText: summary, publishedAt: date, doi: PaperIdentity.doi(fields["arxiv:doi"]),
                          journalTitle: fields["arxiv:journal_ref"].map(clean), retrievalSources: ["arXiv"],
                          versions: [PaperVersion(label: "预印本", url: "https://arxiv.org/abs/" + id, pdfURL: "https://arxiv.org/pdf/" + id, isOpen: true)], fullTextStatus: "开放全文")
        if !papers.contains(where: { $0.id == paper.id }) { papers.append(paper) }
    }
    private func clean(_ string: String) -> String { string.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
}
