import Foundation

/// 用户自带密钥。此结构可以写入 JSON，但绝不能包含密钥。
nonisolated struct AIConfiguration: Codable, Equatable {
    var baseURL = "https://open.bigmodel.cn/api/paas/v4"
    var model = "glm-5.2"
    var id: String?
    var name: String?
}

/// 缓存一次生成结果，回到页面时直接读取，避免重复调用付费接口。
nonisolated struct GeneratedReading: Codable, Equatable {
    var accessMode: String? // demo / personal：按实际发起请求时的配置记录。
    var title: String
    var clarification: String // 正文第一句，说明标题的夸张表达与证据边界。
    var body: String
    var sourceLabel: String
    var sourceText: String
    var model: String
    var provider: String
    var createdAt: Double
    var language: String? // 旧版本缺省为简体中文，按语言分别缓存。
    var coverText: String?
    var cards: [OverviewCard]?
    var usage: TokenUsage?
    var figureIDs: [String]?
    var figureReason: String?
    var figureSelectionMethod: String?
    var mediaVersion: Int?
}

nonisolated struct ReadingSource: Equatable {
    var label: String
    var text: String
    var page: Int?
}

/// 模型只生成文字，论文身份、作者、原文地址始终取自文献数据。
nonisolated struct AIDraft: Decodable {
    var title: String
    var clarification: String
    var body: String
    var coverText: String?
    var cards: [OverviewCard]?
    var figureIDs: [String]?
    var figureReason: String?
}
