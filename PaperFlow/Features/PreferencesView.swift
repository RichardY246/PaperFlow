import SwiftUI

/// 内容语言影响生成与缓存；主题色只改变控件，不改动原始论文资料。
struct PreferencesView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            ReadableSection("AI 内容语言") {
                Picker("目标语言", selection: $store.state.targetLanguage) { ForEach(ReadingLanguages.all, id: \.self) { Text($0) } }
                Text("标题、解读、封面文案和问答使用目标语言。切换后使用对应语言的缓存，新生成内容才会调用接口。").flowFont(.body).foregroundStyle(.secondary)
            }
            ReadableSection("主题颜色") {
                ForEach(AppThemes.all, id: \.self) { theme in
                    Button { store.state.theme = theme } label: {
                        HStack { Circle().fill(Color(hex: AppThemes.hex(theme))).frame(width: 24,height: 24); Text(AppThemes.name(theme)).foregroundStyle(.primary); Spacer(); if store.state.theme == theme { Image(systemName:"checkmark") } }.frame(minHeight: 38)
                    }.accessibilityIdentifier("theme-" + theme)
                }
            }
            ReadableSection("AI 与用量") {
                Text("首页只展示已完成的解读。刷新和加载更多可能调用接口，用量由当前 API 或课堂额度承担。").flowFont(.body).foregroundStyle(.secondary)
                Button("API 配置") { store.go(.aiSettings) }
                Button("Token 用量") { store.go(.usage) }
            }
        }.navigationTitle("语言与外观").navigationBarTitleDisplayMode(.inline).flowFont(.body)
            .onChange(of: store.state.targetLanguage) { _, _ in store.cancelAutomaticReadings(); store.aiErrors = [:]; store.aiPauseReason = nil; store.configurationRevision += 1 }
    }
}
