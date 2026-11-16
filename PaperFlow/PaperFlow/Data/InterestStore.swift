import Foundation

extension AppStore {
    var presetTopics: [String] { Self.topics.filter { !state.deletedPresetTopics.contains($0) } }
    var orderedCustomTopics: [ResearchTopic] { state.customTopics.filter(\.pinned) + state.customTopics.filter { !$0.pinned } }
    var customTopicNames: [String] { orderedCustomTopics.map(\.name) }
    var availableTopics: [String] { presetTopics + customTopicNames }
    @discardableResult func addTopic(_ text: String) -> Bool {
        let name = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50, !availableTopics.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        state.customTopics.append(ResearchTopic(name:name)); state.interests.insert(name); recordEvent("topic_add")
        return true
    }
    func deleteTopic(_ name: String) {
        var updated = state
        if Self.topics.contains(name) { updated.deletedPresetTopics.insert(name) }
        updated.customTopics.removeAll { $0.name == name }
        updated.interests.remove(name); updated.excludedTopics.remove(name); updated.homeFilter.topics.remove(name)
        state = updated
    }
    func renameTopic(_ old: String, to value: String) -> Bool {
        let name = value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50, let index = state.customTopics.firstIndex(where: { $0.name == old }),
              !availableTopics.contains(where: { $0 != old && $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        var updated = state; updated.customTopics[index].name = name
        if updated.interests.remove(old) != nil { updated.interests.insert(name) }
        if updated.excludedTopics.remove(old) != nil { updated.excludedTopics.insert(name) }
        if updated.homeFilter.topics.remove(old) != nil { updated.homeFilter.topics.insert(name) }
        state = updated; return true
    }
    func toggleTopicPin(_ id: String) { if let i = state.customTopics.firstIndex(where: { $0.id == id }) { state.customTopics[i].pinned.toggle() } }
}

// 只统计操作次数，不记录标签内容、论文正文、密钥或个人身份。
extension AppStore {
    func recordEvent(_ name:String) { state.eventCounts[name,default:0] += 1 }
    func setCover(_ asset:CoverAsset, for id:String) { state.covers[id] = asset; recordEvent("cover_change") }
}
