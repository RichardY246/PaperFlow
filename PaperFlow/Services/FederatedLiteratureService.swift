import Foundation
import Security

/// 文献服务密钥有自己的钥匙串服务名，与大模型密钥完全分开。
@MainActor enum LibraryKeyStore {
    private static func query(_ provider:String) -> [String:Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"PaperFlow.LiteratureKeys", kSecAttrAccount as String:provider] }
    static func read(_ provider:String = "OpenAlex") -> String {
        var q = query(provider); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String, provider:String = "OpenAlex") throws {
        let query = query(provider)
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { SecItemDelete(query as CFDictionary); return }
        guard key.rangeOfCharacter(from: .controlCharacters) == nil else { throw ServiceError.message("文献密钥包含无效字符。") }
        let data = Data(key.utf8)
        var result = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if result == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            result = SecItemAdd(q as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw ServiceError.message("文献密钥保存失败，请解锁设备后重试。") }
    }
}

@MainActor final class FederatedLiteratureService {
    static let shared = FederatedLiteratureService()
    private let session: URLSession
    private let directory: URL
    private var nextArxiv = Date.distantPast
    private var cooldowns: [String: Date] = [:]
    static let pageSize = 12
    init(session: URLSession = .shared, directory: URL? = nil) {
        self.session = session
        self.directory = directory ?? URL.documentsDirectory.appending(path: "PaperFlow/DiscoveryCache", directoryHint: .isDirectory)
    }
    static func expanded(_ query:String) -> String { LiteratureQuery(query).english }
    static func startDate(_ filter: ContentFilter, now: Date = Date()) -> String? {
        guard let days = ["近 7 天":7,"近 30 天":30,"近一年":365][filter.time], let date = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func requestURL(_ provider: LiteratureProvider, query: String, filter: ContentFilter, cursor: String, relaxed:Bool = false) -> URL {
        let query = expanded(query)
        var items: [URLQueryItem] = []
        let root: String
        switch provider {
        case .arxiv:
            root = "https://export.arxiv.org/api/query"
            let field = filter.field == "标题" ? "ti" : filter.field == "作者" ? "au" : "all"
            let words = query.split(whereSeparator: { $0.isWhitespace }).prefix(12).map { "\(field):\"" + $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "") + "\"" }
            var q = words.isEmpty ? "cat:cs.HC OR cat:cs.AI" : words.joined(separator: relaxed ? " OR " : " AND ")
            if let date = startDate(filter) { q = "(\(q)) AND submittedDate:[\(date.replacingOccurrences(of: "-", with: ""))0000 TO 299912312359]" }
            if !filter.journalQuery.isEmpty { q += " AND jr:\"" + filter.journalQuery.replacingOccurrences(of: "\"", with: "") + "\"" }
            items = [.init(name:"search_query",value:q),.init(name:"start",value:cursor),.init(name:"max_results",value:String(pageSize)),.init(name:"sortBy",value:filter.sort == "最新" || query.isEmpty ? "submittedDate" : "relevance"),.init(name:"sortOrder",value:"descending")]
            if let id = LiteratureQuery(query).identifier, !LiteratureQuery(query).isDOI { items = [.init(name:"id_list",value:id),.init(name:"max_results",value:String(pageSize))] }
        case .openalex:
            root = "https://api.openalex.org/works"
            if !query.isEmpty { items.append(.init(name:filter.field == "标题" ? "search.title" : "search", value:query)) }
            if cursor.hasPrefix("cursor:") { items.append(.init(name:"cursor",value:String(cursor.dropFirst(7)))) }
            else { items.append(.init(name:"page",value:cursor)) }
            items.append(.init(name:"per_page",value:String(pageSize)))
            if filter.sort == "最新" || query.isEmpty { items.append(.init(name:"sort",value:"publication_date:desc")) }
            var constraints: [String] = []
            if let date = startDate(filter) { constraints.append("from_publication_date:" + date) }
            if (filter.access == "开放全文" || filter.access == "可直接阅读全文") { constraints.append("is_oa:true") }
            if !constraints.isEmpty { items.append(.init(name:"filter",value:constraints.joined(separator:","))) }
        case .crossref:
            root = "https://api.crossref.org/works"
            if !query.isEmpty { items.append(.init(name: filter.field == "标题" ? "query.title" : filter.field == "作者" ? "query.author" : "query.bibliographic",value:query)) }
            if !filter.journalQuery.isEmpty { items.append(.init(name:"query.container-title",value:filter.journalQuery)) }
            items += [.init(name:"rows",value:String(pageSize)),.init(name:"cursor",value:cursor)]
            if filter.sort == "最新" || query.isEmpty { items += [.init(name:"sort",value:"published"),.init(name:"order",value:"desc")] }
            if let date = startDate(filter) { items.append(.init(name:"filter",value:"from-pub-date:" + date)) }
        case .hal:
            root = "https://api.archives-ouvertes.fr/search/"
            let field = filter.field == "标题" ? "title_t" : filter.field == "作者" ? "authFullName_t" : "text"
            let safe = query.replacingOccurrences(of:"\\",with:"").replacingOccurrences(of:"\"",with:"")
            items = [.init(name:"q",value:query.isEmpty ? "*:*" : field + ":\"" + safe + "\"" + (relaxed ? "~8" : "~3")),.init(name:"rows",value:String(pageSize)),.init(name:"start",value:cursor),.init(name:"wt",value:"json"),.init(name:"fl",value:"halId_s,title_s,authFullName_s,abstract_s,producedDateY_i,producedDate_tdate,journalTitle_s,doiId_s,uri_s,fileMain_s")]
            if LiteratureQuery(query).isDOI { items[0] = .init(name:"q",value:"doiId_s:\"" + query + "\"") }
            if filter.access == "开放全文" || filter.access == "可直接阅读全文" { items.append(.init(name:"fq",value:"submitType_s:file")) }
            if let date = startDate(filter) { items.append(.init(name:"fq",value:"producedDate_tdate:[" + date + "T00:00:00Z TO *]")) }
            if filter.sort == "最新" { items.append(.init(name:"sort",value:"producedDate_tdate desc")) }
            if !filter.journalQuery.isEmpty { items.append(.init(name:"fq",value:"journalTitle_t:\"" + filter.journalQuery.replacingOccurrences(of:"\"",with:"") + "\"")) }
        case .europePMC:
            root = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
            var q = query.isEmpty ? "FIRST_PDATE:[2024-01-01 TO *]" : query
            if filter.field == "标题" { q = "TITLE:\"" + query.replacingOccurrences(of:"\"",with:"") + "\"" }
            if LiteratureQuery(query).isDOI { q = "DOI:" + query }
            if filter.field == "作者" { q = "AUTH:\"" + query.replacingOccurrences(of:"\"",with:"") + "\"" }
            if filter.access == "开放全文" || filter.access == "可直接阅读全文" { q += " OPEN_ACCESS:Y" }
            if let date = startDate(filter) { q += " FIRST_PDATE:[" + date + " TO *]" }
            if !filter.journalQuery.isEmpty { q += " JOURNAL:\"" + filter.journalQuery.replacingOccurrences(of:"\"",with:"") + "\"" }
            if filter.sort == "最新" { q += " sort_date:y" }
            items = [.init(name:"query",value:q),.init(name:"format",value:"json"),.init(name:"resultType",value:"core"),.init(name:"pageSize",value:String(pageSize)),.init(name:"cursorMark",value:cursor)]
        case .core:
            root = "https://api.core.ac.uk/v3/search/works"
            let safe = query.replacingOccurrences(of:"\"",with:"")
            let q = filter.field == "标题" ? "title:\"" + safe + "\"" : filter.field == "作者" ? "authors.name:\"" + safe + "\"" : safe
            items = [.init(name:"q",value:q.isEmpty ? "research" : q),.init(name:"limit",value:String(pageSize)),.init(name:"offset",value:cursor)]
        }
        var parts = URLComponents(string: root)!; parts.queryItems = items
        return parts.url!
    }
    func clearCache() { try? FileManager.default.removeItem(at: directory) }
    func search(query: String, filter: ContentFilter, cursors: [String: String]? = nil, openAlexKey: String = "", coreKey:String = "", refresh: Bool = false,onUpdate:((DiscoveryPage)->Void)? = nil) async throws -> DiscoveryPage {
        let selected = LiteratureProvider.allCases.filter { filter.sources.isEmpty || filter.sources.contains($0.rawValue) }
        let requested = selected.filter { cursors == nil || cursors?[$0.rawValue] != nil }
        let sources = requested.filter { (cooldowns[$0.rawValue + (($0 == .core ? coreKey : openAlexKey).isEmpty ? "guest" : "personal")] ?? .distantPast) <= Date() }
        let cacheText = [query,filter.kind,filter.field,filter.time,filter.sort,filter.journalQuery,filter.access,filter.sources.sorted().joined(separator:","),filter.topics.sorted().joined(separator:","),filter.journals.sorted().joined(separator:","),cursors?.sorted { $0.key < $1.key }.description ?? "first",String(!openAlexKey.isEmpty)].joined(separator:"|")
        let cacheFile = directory.appending(path: PaperIdentity.stableID("query-v2", cacheText + String(!coreKey.isEmpty)) + ".json")
        let cached = (try? Data(contentsOf: cacheFile)).flatMap { try? JSONDecoder().decode(DiscoveryPage.self, from: $0) }
        if !refresh, var cached, Date().timeIntervalSince1970 - cached.fetchedAt < 86400 { cached.cached = true; return cached }
        var batches: [String:[Paper]] = [:], next: [String:String] = [:], failures = 0
        var warnings = requested.filter { !sources.contains($0) }.map { $0.rawValue + " 额度暂时受限，其他来源可继续检索。" }
        if sources.isEmpty && !requested.isEmpty { throw ServiceError.message("当前来源额度受限，可切换来源或在账号与文献服务中填写 OpenAlex 密钥。") }
        // 各来源独立分页；部分受限不会抹去健康来源的结果。
        await withTaskGroup(of: (String, [Paper], String?, String?).self) { group in
            for source in sources {
                let cursor = cursors?[source.rawValue] ?? (source == .arxiv ? "0" : source == .openalex ? (openAlexKey.isEmpty ? "1" : "cursor:*") : (source == .hal || source == .core) ? "0" : "*")
                group.addTask { @MainActor in
                    do {
                        let result = try await self.fetch(source, query: query, filter: filter, cursor: cursor, key: source == .core ? coreKey : openAlexKey)
                        return (source.rawValue, result.0, result.1, nil)
                    } catch { return (source.rawValue, [], nil, source.rawValue + "：" + (Task.isCancelled ? "已取消" : error.localizedDescription)) }
                }
            }
            for await (name, results, cursor, warning) in group {
                batches[name] = results
                if let cursor { next[name] = cursor }
                if let warning { warnings.append(warning); failures += 1 }
                onUpdate?(DiscoveryPage(papers:results,next:next,warnings:warnings))
            }
        }
        try Task.checkCancellation()
        if !sources.isEmpty, failures == sources.count {
            if var cached { cached.cached = true; cached.warnings = ["暂时无法联网，显示已有缓存。"] + warnings; return cached }
            throw ServiceError.message(warnings.joined(separator:"\n"))
        }
        var interleaved: [Paper] = []
        for i in 0..<(batches.values.map(\.count).max() ?? 0) {
            for source in LiteratureProvider.allCases { if let batch = batches[source.rawValue], batch.indices.contains(i) { interleaved.append(batch[i]) } }
        }
        let merged = PaperIdentity.mergeAll(interleaved)
        let sorted = filter.sort == "最新" ? merged.sorted { ($0.publishedAt ?? String($0.year)) > ($1.publishedAt ?? String($1.year)) } : SearchRanking.rank(merged,query:query)
        let result = DiscoveryPage(papers: sorted, next: next, warnings: warnings)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let bytes = try? JSONEncoder().encode(result) { try? bytes.write(to: cacheFile, options:.atomic) }
        // 缓存最多 80 页，避免连续浏览无限占用空间。
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys:[.contentModificationDateKey]), files.count > 80 {
            let sorted = files.sorted { ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for file in sorted.prefix(files.count - 80) { try? FileManager.default.removeItem(at:file) }
        }
        return result
    }
    private func fetch(_ source: LiteratureProvider, query: String, filter: ContentFilter, cursor: String, key: String, relaxed:Bool = false) async throws -> ([Paper], String?) {
        if source == .arxiv {
            let delay = max(0,nextArxiv.timeIntervalSinceNow); nextArxiv = Date().addingTimeInterval(delay + 3)
            try await Task.sleep(for:.seconds(delay))
        }
        var url = Self.requestURL(source, query: query, filter: filter, cursor: cursor,relaxed:relaxed)
        let exactDOI = LiteratureQuery(query)
        if source == .crossref, exactDOI.isDOI, let doi = exactDOI.identifier { url = URL(string:"https://api.crossref.org/works/" + doi.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!)! }
        if source == .openalex && (filter.field == "作者" || !filter.journalQuery.isEmpty) {
            var parts = URLComponents(url:url,resolvingAgainstBaseURL:false)!
            var items = parts.queryItems ?? [], constraints: [String] = []
            if filter.field == "作者" && !query.isEmpty {
                let ids = try await openAlexIDs(endpoint:"authors",query:query,key:key)
                guard !ids.isEmpty else { return ([],nil) }
                items.removeAll { $0.name.hasPrefix("search") }; constraints.append("authorships.author.id:" + ids.joined(separator:"|"))
            }
            if !filter.journalQuery.isEmpty {
                let ids = try await openAlexIDs(endpoint:"sources",query:filter.journalQuery,key:key)
                guard !ids.isEmpty else { return ([],nil) }
                constraints.append("primary_location.source.id:" + ids.joined(separator:"|"))
            }
            let previous = items.first(where: { $0.name == "filter" })?.value
            items.removeAll { $0.name == "filter" }
            items.append(.init(name:"filter",value:([previous].compactMap { $0 } + constraints).joined(separator:",")))
            parts.queryItems = items; url = parts.url!
        }
        var request = URLRequest(url:url); request.timeoutInterval = 18
        request.setValue("PaperFlow/1.6 (educational literature reader)", forHTTPHeaderField:"User-Agent")
        if (source == .openalex || source == .core) && !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField:"Authorization") }
        let (data,response) = try await session.data(for:request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 {
                let object = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
                let delay = min(86400,max(30,object?["retryAfter"] as? Double ?? 300))
                cooldowns[source.rawValue + (key.isEmpty ? "guest" : "personal")] = Date().addingTimeInterval(delay)
            }
            if source == .core && [401,403].contains(code) { cooldowns[source.rawValue + (key.isEmpty ? "guest" : "personal")] = Date().addingTimeInterval(300); throw ServiceError.message("CORE 访问受限，可在文献服务中填写个人 CORE 密钥。") }
            throw ServiceError.message(code == 429 ? (source == .openalex && key.isEmpty ? "公共额度已用完，可填写自己的 OpenAlex 密钥；其他来源仍可用。" : "额度或频率受限，稍后可重试。") : "暂时无法获取结果（\(code)）。")
        }
        switch source {
        case .arxiv:
            let papers = try LiteratureService.parse(data)
            if papers.isEmpty && cursor == "0" && !relaxed && LiteratureQuery(query).words.count > 1 { return try await fetch(source,query:query,filter:filter,cursor:cursor,key:key,relaxed:true) }
            return (papers, papers.count == Self.pageSize ? String((Int(cursor) ?? 0) + Self.pageSize) : nil)
        case .openalex:
            let (papers,total,next) = try LiteratureDecoders.openAlex(data)
            if cursor.hasPrefix("cursor:") { return (papers, papers.isEmpty ? nil : next.map { "cursor:" + $0 }) }
            let page = Int(cursor) ?? 1
            return (papers, page * Self.pageSize < min(total,10000) ? String(page + 1) : nil)
        case .crossref:
            if exactDOI.isDOI, let root = try JSONSerialization.jsonObject(with:data) as? [String:Any], let work = root["message"] as? [String:Any] { let wrapped = try JSONSerialization.data(withJSONObject:["message":["items":[work],"total-results":1]]); return (try LiteratureDecoders.crossref(wrapped).0,nil) }
            let (papers,_,next) = try LiteratureDecoders.crossref(data)
            return (papers, papers.count == Self.pageSize && next != cursor ? next : nil)
        case .hal:
            let (papers,_,next) = try OpenRepositoryDecoders.hal(data)
            if papers.isEmpty && cursor == "0" && !relaxed && LiteratureQuery(query).words.count > 1 { return try await fetch(source,query:query,filter:filter,cursor:cursor,key:key,relaxed:true) }
            return (papers,next)
        case .europePMC:
            let (papers,_,next) = try OpenRepositoryDecoders.europePMC(data); return (papers,papers.count == Self.pageSize && next != cursor ? next : nil)
        case .core:
            let (papers,total,_) = try OpenRepositoryDecoders.core(data)
            let offset = Int(cursor) ?? 0
            return (papers,papers.count == Self.pageSize && offset + papers.count < total ? String(offset + papers.count) : nil)
        }
    }
    private func openAlexIDs(endpoint:String,query:String,key:String) async throws -> [String] {
        var parts = URLComponents(string:"https://api.openalex.org/" + endpoint)!
        parts.queryItems = [.init(name:"search",value:query),.init(name:"per_page",value:"5")]
        var request = URLRequest(url:parts.url!); request.timeoutInterval = 25
        if !key.isEmpty { request.setValue("Bearer " + key,forHTTPHeaderField:"Authorization") }
        let (data,response) = try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.message("作者或期刊查询暂不可用，请稍后重试。") }
        let object = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let results = object?["results"] as? [[String:Any]] ?? []
        return results.compactMap { ($0["id"] as? String)?.split(separator:"/").last.map(String.init) }
    }
    func findOpenVersion(_ paper: Paper, email: String) async throws -> Paper {
        guard let doi = PaperIdentity.doi(paper.doi), email.contains("@"), email.contains(".") else { return paper }
        var parts = URLComponents(string:"https://api.unpaywall.org/v2/" + doi)!
        parts.queryItems = [.init(name:"email",value:email)]
        var request = URLRequest(url:parts.url!); request.timeoutInterval = 25
        let (data,response) = try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let best = object["best_oa_location"] as? [String:Any] else { return paper }
        let pdf = PaperIdentity.webURL(best["url_for_pdf"] as? String)
        guard let url = PaperIdentity.webURL(best["url"] as? String) ?? pdf else { return paper }
        var result = paper; result.pdfURL = pdf ?? paper.pdfURL; result.fullTextStatus = "开放全文"
        result.versions = (paper.versions ?? []) + [PaperVersion(label:"Unpaywall 开放版本",url:url,pdfURL:pdf,isOpen:true)]
        return result
    }
}
