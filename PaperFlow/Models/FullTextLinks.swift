import Foundation

nonisolated struct FullTextUnavailable: LocalizedError {
    var message:String
    var errorDescription:String? { message }
}

nonisolated enum FullTextLinks {
    nonisolated static func candidates(_ paper:Paper) -> [URL] {
        var values = [paper.verifiedPDFURL,paper.pdfURL].compactMap { $0 }
        values += (paper.versions ?? []).filter(\.isOpen).compactMap(\.pdfURL)
        if let id = PaperIdentity.arxiv(paper.sourceURL) { values.append("https://arxiv.org/pdf/" + id) }
        values += (paper.versions ?? []).filter(\.isOpen).map(\.url)
        if let html = paper.openHTMLURL { values.append(html) }
        var seen:Set<String> = []
        return values.compactMap { PaperIdentity.webURL($0) }.filter { seen.insert($0).inserted }.compactMap(URL.init(string:))
    }
    nonisolated static func pdfURLs(in html:String,base:URL) -> [URL] {
        let tags = (try? NSRegularExpression(pattern:#"<(meta|link|a)\b[^>]*>"#,options:[.caseInsensitive])).map { regex in regex.matches(in:html,range:NSRange(html.startIndex...,in:html)).compactMap { Range($0.range,in:html).map { String(html[$0]) } } } ?? []
        var result:[URL] = []
        let attribute = try! NSRegularExpression(pattern:#"([\w:-]+)\s*=\s*["']([^"']*)["']"#,options:[.caseInsensitive])
        for tag in tags {
            var values:[String:String] = [:]
            for match in attribute.matches(in:tag,range:NSRange(tag.startIndex...,in:tag)) {
                if let key = Range(match.range(at:1),in:tag), let value = Range(match.range(at:2),in:tag) { values[String(tag[key]).lowercased()] = String(tag[value]).replacingOccurrences(of:"&amp;",with:"&") }
            }
            let name = (values["name"] ?? values["property"] ?? "").lowercased()
            let address = name == "citation_pdf_url" || name == "dc.identifier" ? values["content"] : values["href"]
            guard let address, let url = URL(string:address,relativeTo:base)?.absoluteURL,
                  PaperIdentity.webURL(url.absoluteString) != nil else { continue }
            if name == "citation_pdf_url" || values["type"]?.lowercased() == "application/pdf" || url.path.lowercased().hasSuffix(".pdf") { result.append(url) }
        }
        var seen:Set<String> = []; return result.filter { seen.insert($0.absoluteString).inserted }
    }
    nonisolated static func isVerified(_ paper:Paper,now:Date = Date()) -> Bool {
        paper.hasCachedFullText == true || (paper.verifiedPDFURL != nil && now.timeIntervalSince1970 - (paper.fullTextCheckedAt ?? 0) < 86400)
    }
}
