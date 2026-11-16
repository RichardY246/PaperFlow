import Foundation

nonisolated struct FigureCandidate: Codable, Identifiable, Sendable {
    var id:String
    var page:Int
    var label:String
    var caption:String
    var anchorX:Double
    var anchorY:Double
    var anchorWidth:Double
    var below:Bool = false
    var score:Double = 0
    var sourceURL:String?
    var quality:String?
    var bounds:[Double]?
}
nonisolated struct FigureChoice: Codable {
    var ids:[String]
    var reason:String
    var method:String
    var model:String?
    var version = 2
}
nonisolated enum FigureRanking {
    nonisolated static func score(caption:String,title:String,abstract:String,page:Int,label:String) -> Double {
        let text = caption.lowercased()
        let important = ["overview","summary","approach","architecture","framework","pipeline","main result","proposed","comparison","performance","workflow","核心","框架","架构","流程","主要结果"]
        var value = Double(important.filter { text.contains($0) }.count) * 3
        let source = Set((title + " " + abstract).lowercased().split { !$0.isLetter }.filter { $0.count > 4 }.map(String.init))
        let captionWords = Set(text.split { !$0.isLetter }.map(String.init))
        value += Double(source.intersection(captionWords).count) * 0.5
        if label.range(of:#"(?:Figure|Fig\.?|图)\s*1\b"#,options:[.regularExpression,.caseInsensitive]) != nil { value += 4 }
        if text.contains("supplement") || text.contains("appendix") || text.contains("additional examples") { value -= 8 }
        return value - Double(page) * 0.04
    }
    nonisolated static func ordered(_ candidates:[FigureCandidate]) -> [FigureCandidate] {
        candidates.sorted { $0.score == $1.score ? $0.page < $1.page : $0.score > $1.score }
    }
    nonisolated static func safeIDs(_ proposed:[String]?,candidates:[FigureCandidate]) -> [String] {
        let allowed = Set(candidates.map(\.id)); var seen:Set<String> = []
        let valid = (proposed ?? []).filter { allowed.contains($0) && seen.insert($0).inserted }
        return Array((valid + ordered(candidates).map(\.id).filter { !valid.contains($0) }).prefix(3))
    }
    nonisolated static func prompt(_ candidates:[FigureCandidate]) -> String {
        ordered(candidates).prefix(18).map { "ID=\($0.id) | \($0.label) | PDF page \($0.page) | \($0.caption.prefix(450))" }.joined(separator:"\n").prefix(6500).description
    }
}
