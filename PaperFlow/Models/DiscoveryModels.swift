import Foundation

nonisolated struct PaperVersion: Codable, Hashable, Sendable {
    var label: String
    var url: String
    var pdfURL: String?
    var isOpen: Bool
}

nonisolated struct LibraryConfiguration: Codable, Equatable {
    var contactEmail = "" // 用于 Unpaywall 识别请求方；留空时不调用该服务。
}

nonisolated enum LiteratureProvider: String, CaseIterable, Codable {
    case arxiv = "arXiv", openalex = "OpenAlex", crossref = "Crossref"
    case hal = "HAL", europePMC = "Europe PMC", core = "CORE"
}

/// 每个数据源独立分页。某个源失败不会抹去其他源已返回的结果。
nonisolated struct DiscoveryPage: Codable {
    var papers: [Paper]
    var next: [String: String]
    var warnings: [String] = []
    var fetchedAt = Date().timeIntervalSince1970
    var cached = false
}

nonisolated enum ReadingLanguages {
    static let all = ["简体中文", "繁體中文", "English"]
    /// 模型返回的 language 标签不代表正文正确；缓存和新结果都检查实际文字。
    static func accepts(_ text:String, language:String) -> Bool {
        let han = text.unicodeScalars.filter { (0x3400...0x9FFF).contains(Int($0.value)) }.count
        let latin = text.unicodeScalars.filter { (65...90).contains(Int($0.value)) || (97...122).contains(Int($0.value)) }.count
        return language == "English" ? latin > 0 && han <= latin / 10 : han > 0
    }
    static func normalized(_ text:String, language:String) -> String {
        guard language != "English" else { return text }
        return text.applyingTransform(StringTransform(language == "繁體中文" ? "Hans-Hant" : "Hant-Hans"),reverse:false) ?? text
    }
    static func instruction(_ language: String) -> String {
        language == "English" ? "Write every generated field in English." : language == "繁體中文" ? "所有生成欄位使用繁體中文。" : "所有生成字段必须使用简体中文。"
    }
}

nonisolated enum AppThemes {
    static let all = ["green", "blue", "purple", "orange", "gray"]
    static func name(_ id: String) -> String { ["green":"绿色", "blue":"蓝色", "purple":"紫色", "orange":"橙色", "gray":"灰色"][id] ?? "绿色" }
    static func hex(_ id: String) -> String { ["green":"236B5B", "blue":"245FA5", "purple":"7551A8", "orange":"A9511C", "gray":"52616B"][id] ?? "236B5B" }
}
