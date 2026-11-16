import Foundation

/// 课堂额度是设备本地规则，不承诺抵御重装或破解。请求预算先预留，再以实际 usage 结算。
nonisolated struct DemoLedger: Codable {
    var imageBudget: ImageBudget? // 缺省按旧版本迁移，文字额度不变。
    var tokenLimit = IterationConfig.demoTokenLimit
    var paperLimit = IterationConfig.demoPaperLimit
    var usedTokens = 0
    var delivered: Set<String> = []
    var reservations: [String:Int] = [:]
    var pendingPapers: [String:String] = [:]
    var transactions: [String] = []
    var quota: DemoQuota { DemoQuota(tokenLimit:tokenLimit,usedTokens:usedTokens,reservedTokens:reservations.values.reduce(0,+),paperLimit:paperLimit,usedPapers:delivered.count,reservedPapers:Set(pendingPapers.values).subtracting(delivered).count) }
    mutating func reserve(id:String, input:String, output:Int, paper:String?) throws {
        guard !quota.exhausted else { throw DemoLimit.reached }
        if let paper, !delivered.contains(paper), pendingPapers.values.contains(paper) { throw DemoLimit.busy }
        if let paper, !delivered.contains(paper), !pendingPapers.values.contains(paper), delivered.count + quota.reservedPapers >= paperLimit { throw DemoLimit.reached }
        // UTF-8 字节上界保守预留输入，避免以字符数冒充真实 Token 数。
        let budget = input.utf8.count + output + 256
        guard budget <= quota.remainingTokens else { throw DemoLimit.reached }
        reservations[id] = budget; pendingPapers[id] = paper
    }
    mutating func settle(id:String, usage:TokenUsage?, billed:Bool, keepPaper:Bool = false) {
        guard reservations[id] != nil else { return }
        if let total = usage?.total { reservations[id] = nil; usedTokens += max(0,total) }
        else if !billed { reservations[id] = nil }
        // 接口未回 usage 的已发送请求保留预算，界面标为待确认，不伪造精确用量。
        if !keepPaper { pendingPapers[id] = nil }
    }
    mutating func abandon(_ paper:String) { pendingPapers = pendingPapers.filter { $0.value != paper } }
    mutating func deliver(_ paper:String) { delivered.insert(paper); abandon(paper) }
    mutating func topUp() { var images = imageBudget ?? ImageBudget(); images.limit += 3; imageBudget = images; tokenLimit += 30_000; paperLimit += 3; transactions.append("\(Date().timeIntervalSince1970)|模拟增加 30000 Token / 3 篇 / 3 张生图；无扣款") }
}
nonisolated enum DemoLimit: LocalizedError {
    case reached, busy
    var errorDescription: String? {
        switch self {
        case .reached: return "演示额度已用完或不足以完成本次请求。请配置个人 API，或使用模拟充值。"
        case .busy: return "这篇文献正在准备，请稍后查看。"
        }
    }
}
