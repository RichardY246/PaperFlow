import Foundation
import NaturalLanguage

/// 搜索按查询相关性排序，与首页兴趣推荐分离；中英文都保留。
nonisolated enum SearchRanking {
    static func terms(_ text:String) -> [String] {
        let tokenizer = NLTokenizer(unit:.word);tokenizer.string = text.lowercased()
        var result:[String] = []
        tokenizer.enumerateTokens(in:tokenizer.string!.startIndex..<tokenizer.string!.endIndex) { range,_ in
            let token = String(tokenizer.string![range]);if token.contains(where:{$0.isLetter || $0.isNumber}) { result.append(token) };return true
        };return result
    }
    static func score(_ paper:Paper,query:String) -> Double {
        let query = LiteratureQuery(query)
        if let id = query.identifier {
            if PaperIdentity.doi(paper.doi) == id || PaperIdentity.arxiv(paper.sourceURL) == id { return 10000 }
        }
        let title = paper.title.lowercased(),author = paper.author.lowercased(),abstract = (paper.abstractText ?? "").lowercased()
        let words = Set(terms(query.original)+terms(query.english))
        var value = title.contains(query.original.lowercased()) ? 40.0 : 0
        for word in words {
            if title.contains(word) { value += 5 }
            if author.contains(word) { value += 3 }
            if abstract.contains(word) { value += 1 }
        };return value
    }
    static func rank(_ papers:[Paper],query:String) -> [Paper] {
        let scores = Dictionary(papers.map { ($0.id,score($0,query:query)) },uniquingKeysWith:{$1})
        return papers.sorted { let a = scores[$0.id] ?? 0,b = scores[$1.id] ?? 0;return a == b ? $0.id < $1.id : a > b }
    }
}
