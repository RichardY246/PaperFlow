import SwiftUI

struct TopicManagementView: View {
    @Environment(AppStore.self) private var store
    @State private var editing = false
    @State private var oldName: String?
    @State private var name = ""
    @State private var error = ""
    var body: some View {
        List {
            Section { Button("添加自定义兴趣") { oldName = nil; name = ""; editing = true }; if !error.isEmpty { Text(error).foregroundStyle(.secondary) } }
            ReadableSection("预设兴趣 · 可删除") {
                ForEach(store.presetTopics,id:\.self) { topic in topicRow(topic,custom:false) }
                    .onDelete { indices in let names = indices.map { store.presetTopics[$0] }; names.forEach { store.deleteTopic($0) } }
            }
            ReadableSection("我的自定义兴趣") {
                ForEach(store.orderedCustomTopics) { topic in
                    HStack { topicRow(topic.name,custom:true); Menu { Button("改名") { oldName = topic.name; name = topic.name; editing = true }; Button(topic.pinned ? "取消置顶" : "置顶") { store.toggleTopicPin(topic.id) }; Button("删除",role:.destructive) { store.deleteTopic(topic.name) } } label: { Image(systemName:topic.pinned ? "pin.fill" : "ellipsis").frame(width:44,height:44) } }
                }.onMove { source,destination in var topics = store.orderedCustomTopics; topics.move(fromOffsets:source,toOffset:destination); store.state.customTopics = topics }
                    .onDelete { indices in let names = indices.map { store.orderedCustomTopics[$0].name }; names.forEach { store.deleteTopic($0) } }
            }
            ReadableSection("排除的方向") {
                ForEach(store.availableTopics,id:\.self) { topic in
                    Toggle(topic,isOn:Binding(get:{store.state.excludedTopics.contains(topic)},set:{ excluded in if excluded { store.state.excludedTopics.insert(topic); store.state.interests.remove(topic) } else { store.state.excludedTopics.remove(topic) } }))
                }
            }
        }.flowFont(.body).navigationTitle("兴趣管理").navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
            .alert(oldName == nil ? "添加兴趣" : "修改兴趣名称",isPresented:$editing) {
                TextField("研究方向",text:$name)
                Button("保存") { let ok = oldName.map { store.renameTopic($0,to:name) } ?? store.addTopic(name); error = ok ? "" : "名称为空、过长或已存在。" }
                Button("取消",role:.cancel) { }
            }
    }
    private func topicRow(_ name:String,custom:Bool) -> some View {
        Button {
            if store.state.interests.contains(name) { store.state.interests.remove(name) }
            else { store.state.interests.insert(name); store.state.excludedTopics.remove(name) }
        } label: {
            HStack { Text(name).padding(.horizontal,10).padding(.vertical,7).background(custom ? Color.clear : Color.flow.opacity(0.08),in:RoundedRectangle(cornerRadius:8)).overlay { RoundedRectangle(cornerRadius:8).stroke(Color.flow.opacity(0.5),style:StrokeStyle(lineWidth:1,dash:custom ? [4,3] : [])) }; Spacer(); Image(systemName:store.state.interests.contains(name) ? "checkmark.circle.fill" : "circle") }.foregroundStyle(Color.flow).frame(minHeight:44)
        }.buttonStyle(.plain)
    }
}
