import Foundation
import CryptoKit

/// 去重以 DOI / arXiv ID 为优先；跨源缺少标识时才使用题名、首位作者和年份。
nonisolated enum PaperIdentity {
    nonisolated static func doi(_ text: String?) -> String? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: #"^https?://(dx\.)?doi\.org/"#, with: "", options: .regularExpression)
        return text.hasPrefix("10.") && text.contains("/") ? text : nil
    }
    nonisolated static func arxiv(_ text: String) -> String? {
        guard let range = text.lowercased().range(of: "arxiv.org/abs/") else { return nil }
        return String(text.lowercased()[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: #"v[0-9]+$"#, with: "", options: .regularExpression)
    }
    nonisolated static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    nonisolated static func primary(_ paper: Paper) -> String {
        if let doi = doi(paper.doi) ?? doi(paper.sourceURL) { return "doi:" + doi }
        if let id = arxiv(paper.sourceURL) { return "arxiv:" + id }
        return paper.sourceURL.lowercased().replacingOccurrences(of: "http://", with: "https://").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    nonisolated static func same(_ a: Paper, _ b: Paper) -> Bool {
        let ad = doi(a.doi) ?? doi(a.sourceURL), bd = doi(b.doi) ?? doi(b.sourceURL)
        if let ad, let bd { return ad == bd }
        if primary(a) == primary(b) { return true }
        let title = normalized(a.title)
        let authorA = normalized(a.author.split(separator: " ").last.map(String.init) ?? a.author)
        let authorB = normalized(b.author.split(separator: " ").last.map(String.init) ?? b.author)
        return title.count > 16 && title == normalized(b.title) && !authorA.isEmpty && authorA == authorB && abs(a.year - b.year) <= 2
    }
    nonisolated static func merge(_ original: Paper, _ incoming: Paper) -> Paper {
        var result = original
        result.doi = doi(original.doi) ?? doi(incoming.doi) ?? doi(incoming.sourceURL)
        if result.abstractText?.isEmpty != false { result.abstractText = incoming.abstractText }
        if result.pdfURL == nil { result.pdfURL = incoming.pdfURL }
        if incoming.verifiedPDFURL != nil { result.verifiedPDFURL = incoming.verifiedPDFURL }
        if incoming.hasCachedFullText == true { result.hasCachedFullText = true }
        if let stamp = incoming.fullTextCheckedAt, stamp >= (result.fullTextCheckedAt ?? 0) { result.fullTextCheckedAt = stamp }
        if result.openHTMLURL == nil { result.openHTMLURL = incoming.openHTMLURL }
        if result.publishedAt == nil { result.publishedAt = incoming.publishedAt }
        if result.journalTitle == nil { result.journalTitle = incoming.journalTitle }
        if result.journalID == "arxiv", let name = incoming.journalTitle, !name.localizedCaseInsensitiveContains("arxiv") {
            result.journalID = incoming.journalID; result.journalTitle = name
        }
        result.topics = Array(Set(original.topics + incoming.topics)).sorted()
        result.retrievalSources = Array(Set((original.retrievalSources ?? []) + (incoming.retrievalSources ?? []))).sorted()
        result.versions = Array(Set((original.versions ?? []) + (incoming.versions ?? []))).sorted { $0.url < $1.url }
        if original.localPDF != nil || result.pdfURL != nil || result.versions?.contains(where: \.isOpen) == true { result.fullTextStatus = "开放全文" }
        if FullTextLinks.isVerified(result) { result.fullTextStatus = "可直接阅读全文" }
        return result
    }
    nonisolated static func mergeAll(_ papers: [Paper]) -> [Paper] {
        var result: [Paper] = []
        for paper in papers {
            if let i = result.firstIndex(where: { same($0, paper) }) { result[i] = merge(result[i], paper) }
            else { result.append(paper) }
        }
        return result
    }
    nonisolated static func stableID(_ source: String, _ value: String) -> String {
        source + "-" + SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func webURL(_ text: String?) -> String? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url.absoluteString
    }
    nonisolated static func topics(_ text: String) -> [String] {
        let mappings = [("生成式 AI", ["generative", "language model", "diffusion", "transformer"]), ("人机交互", ["human-computer", "human computer", "user experience", "hci"]),
                        ("交互设计", ["interaction design", "interface", "design research"]), ("机器学习", ["machine learning", "neural", "training"]),
                        ("计算机视觉", ["computer vision", "image", "visual"]), ("设计方法", ["design method", "co-design", "participatory"])]
        return mappings.filter { entry in entry.1.contains { text.localizedCaseInsensitiveContains($0) } }.map(\.0)
    }
}
