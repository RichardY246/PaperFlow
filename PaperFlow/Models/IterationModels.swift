import Foundation

nonisolated struct ResearchTopic: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var pinned = false
}
nonisolated struct OverviewCard: Codable, Identifiable, Equatable {
    var title: String
    var text: String
    var evidence: String?
    var page: Int?
    var id: String { title + text }
}
nonisolated struct TokenUsage: Codable, Equatable {
    var prompt_tokens: Int?
    var completion_tokens: Int?
    var total_tokens: Int?
    var total: Int? { total_tokens ?? (prompt_tokens.flatMap { input in completion_tokens.map { input + $0 } }) }
}
nonisolated struct UsageRecord: Codable, Identifiable {
    var id = UUID().uuidString
    var timestamp = Date().timeIntervalSince1970
    var operation: String
    var model: String
    var provider: String
    var mode: String
    var paperID: String?
    var usage: TokenUsage?
    var succeeded: Bool
}
nonisolated struct DemoQuota: Codable, Equatable {
    var tokenLimit: Int
    var usedTokens: Int
    var reservedTokens: Int
    var paperLimit: Int
    var usedPapers: Int
    var reservedPapers: Int
    var remainingTokens: Int { max(0, tokenLimit - usedTokens - reservedTokens) }
    var exhausted: Bool { remainingTokens == 0 || usedPapers >= paperLimit }
}
nonisolated struct CoverAsset: Codable, Equatable {
    var image: Data
    var page: Int
    var caption: String
    var manual: Bool
    var originalImage: Data?
    var template: String?
}
nonisolated struct TranslationResult: Codable, Equatable {
    var original: String
    var translated: String
    var usage: TokenUsage?
    var page: Int
    var language: String
}
nonisolated enum IterationConfig {
    static let demoModel = "glm-5.2"
    static let demoTokenLimit = 30_000
    static let demoPaperLimit = 3
    static let feedBatchSize = 3
    static let maxOutputTokens = 2400
}
