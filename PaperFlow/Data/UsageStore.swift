import Foundation

extension AppStore {
    var totalTokens:Int { state.tokenTotal ?? state.usageRecords.compactMap { $0.usage?.total }.reduce(0,+) }
    func tokens(on date:Date) -> Int {
        if let days = state.tokenDays { return days[dayKey(date),default:0] }
        return state.usageRecords.filter { Calendar.current.isDate(Date(timeIntervalSince1970:$0.timestamp),inSameDayAs:date) }.compactMap { $0.usage?.total }.reduce(0,+)
    }
    func recordUsage(_ record:UsageRecord) {
        var updated = state
        if updated.tokenTotal == nil { updated.tokenTotal = totalTokens }
        if updated.tokenDays == nil {
            var days:[String:Int] = [:]
            for old in updated.usageRecords { days[dayKey(Date(timeIntervalSince1970:old.timestamp)),default:0] += max(0,old.usage?.total ?? 0) }
            updated.tokenDays = days
        }
        if let value = record.usage?.total {
            updated.tokenTotal! += max(0,value)
            updated.tokenDays![dayKey(Date(timeIntervalSince1970:record.timestamp)),default:0] += max(0,value)
        }
        updated.usageRecords.insert(record,at:0)
        updated.usageRecords = Array(updated.usageRecords.prefix(1000))
        state = updated
    }
}
