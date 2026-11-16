import Foundation

/// 把不同网站的字段转换成统一 Paper；界面不用知道各家 JSON 的差异。
enum LiteratureDecoders {
    nonisolated static func openAlex(_ data: Data) throws -> ([Paper], Int, String?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = root["results"] as? [[String: Any]] else { throw ServiceError.message("OpenAlex 返回了无法识别的数据。") }
        let papers = items.compactMap { item -> Paper? in
            guard let title = item["display_name"] as? String, !title.isEmpty, let identifier = item["id"] as? String else { return nil }
            let primary = item["primary_location"] as? [String: Any] ?? [:]
            let source = primary["source"] as? [String: Any] ?? [:]
            let doi = PaperIdentity.doi(item["doi"] as? String)
            let authors = item["authorships"] as? [[String: Any]] ?? []
            let author = (authors.first?["author"] as? [String: Any])?["display_name"] as? String ?? "作者未提供"
            let locations = item["locations"] as? [[String: Any]] ?? []
            var versions = locations.compactMap { location -> PaperVersion? in
                let pdf = PaperIdentity.webURL(location["pdf_url"] as? String)
                guard let url = PaperIdentity.webURL(location["landing_page_url"] as? String) ?? pdf else { return nil }
                return PaperVersion(label: location["version"] as? String ?? "文献版本", url: url, pdfURL: pdf, isOpen: location["is_oa"] as? Bool ?? false)
            }
            if let best = item["best_oa_location"] as? [String: Any], let url = PaperIdentity.webURL(best["landing_page_url"] as? String) ?? PaperIdentity.webURL(best["pdf_url"] as? String) {
                versions.insert(PaperVersion(label: best["version"] as? String ?? "开放版本", url: url, pdfURL: PaperIdentity.webURL(best["pdf_url"] as? String), isOpen: true), at: 0)
            }
            let abstract = reconstruct(item["abstract_inverted_index"] as? [String: [Int]])
            let journalName = source["display_name"] as? String
            let journalID = (source["id"] as? String)?.split(separator: "/").last.map(String.init) ?? "openalex-unknown"
            let sourceURL = doi.map { "https://doi.org/" + $0 } ?? PaperIdentity.webURL(primary["landing_page_url"] as? String) ?? identifier
            let pdf = versions.first(where: { $0.isOpen && $0.pdfURL != nil })?.pdfURL
            let isOA = (item["open_access"] as? [String: Any])?["is_oa"] as? Bool ?? versions.contains(where: \.isOpen)
            return Paper(id: PaperIdentity.stableID("oa", doi ?? identifier), title: title, hook: title, subtitle: "来自 OpenAlex", author: author,
                         year: item["publication_year"] as? Int ?? 0, journalID: journalID,
                         topics: PaperIdentity.topics(title + " " + (abstract ?? "")), sourceURL: sourceURL, pdfURL: pdf,
                         color: "DFE8F1", symbol: "doc.text", coverText: "研究", insights: [], abstractText: abstract,
                         publishedAt: (item["publication_date"] as? String).map { $0 + "T00:00:00Z" }, doi: doi,
                         journalTitle: journalName, retrievalSources: ["OpenAlex"], versions: Array(Set(versions)), fullTextStatus: isOA ? "开放全文" : "需授权")
        }
        let meta = root["meta"] as? [String: Any] ?? [:]
        return (papers, meta["count"] as? Int ?? items.count, meta["next_cursor"] as? String)
    }
    nonisolated static func crossref(_ data: Data) throws -> ([Paper], Int, String?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let message = root["message"] as? [String: Any], let items = message["items"] as? [[String: Any]] else { throw ServiceError.message("Crossref 返回了无法识别的数据。") }
        let papers = items.compactMap { item -> Paper? in
            guard let raw = (item["title"] as? [String])?.first, !raw.isEmpty, let doi = PaperIdentity.doi(item["DOI"] as? String) else { return nil }
            let title = plain(raw)
            let authorData = (item["author"] as? [[String: Any]])?.first ?? [:]
            let author = [authorData["given"] as? String, authorData["family"] as? String].compactMap { $0 }.joined(separator: " ")
            let journal = (item["container-title"] as? [String])?.first
            let dateObject = (item["published"] ?? item["published-print"] ?? item["published-online"]) as? [String: Any] ?? [:]
            let parts = (dateObject["date-parts"] as? [[Int]])?.first ?? []
            let year = parts.first ?? 0
            let date = year > 0 ? String(format: "%04d-%02d-%02dT00:00:00Z", year, parts.count > 1 ? parts[1] : 1, parts.count > 2 ? parts[2] : 1) : nil
            let abstract = (item["abstract"] as? String).map { plain($0) }
            // Crossref 的下载链接可能仍需授权；不能因为有 PDF 链接就标为开放全文。
            let openLicense = (item["license"] as? [[String: Any]] ?? []).contains { ($0["URL"] as? String)?.contains("creativecommons.org/") == true }
            let versions = (item["link"] as? [[String: Any]] ?? []).compactMap { link -> PaperVersion? in
                guard let url = PaperIdentity.webURL(link["URL"] as? String) else { return nil }
                return PaperVersion(label: "出版社版本", url: url, pdfURL: (link["content-type"] as? String) == "application/pdf" && openLicense ? url : nil, isOpen: openLicense)
            }
            return Paper(id: PaperIdentity.stableID("cr", doi), title: title, hook: title, subtitle: "来自 Crossref", author: author.isEmpty ? "作者未提供" : author,
                         year: year, journalID: PaperIdentity.stableID("journal", journal ?? "Crossref"), topics: PaperIdentity.topics(title + " " + (abstract ?? "")),
                         sourceURL: "https://doi.org/" + doi, pdfURL: versions.first(where: { $0.pdfURL != nil })?.pdfURL, color: "E7E4F2", symbol: "doc.text", coverText: "研究",
                         insights: [], abstractText: abstract, publishedAt: date, doi: doi, journalTitle: journal, retrievalSources: ["Crossref"], versions: versions,
                         fullTextStatus: openLicense ? "开放全文" : "未确认")
        }
        return (papers, message["total-results"] as? Int ?? items.count, message["next-cursor"] as? String)
    }
    nonisolated static func reconstruct(_ index: [String: [Int]]?) -> String? {
        guard let index, !index.isEmpty else { return nil }
        var words: [Int: String] = [:]
        for (word, positions) in index { for position in positions where position >= 0 && position < 8000 { words[position] = word } }
        let result = words.keys.sorted().compactMap { words[$0] }.joined(separator: " ")
        return result.isEmpty ? nil : String(result.prefix(16000))
    }
    nonisolated static func plain(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
