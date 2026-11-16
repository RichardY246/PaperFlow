// 个人页面：阅读日历、历史、资料编辑与设置；编辑资料先用草稿，保存后生效。
import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) var store
    @State private var editing: UserPost?
    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Button { store.go(.profile) } label: { Avatar(name: store.state.nickname, size: 72, symbol: store.state.avatarSymbol, photo: store.state.avatarPhoto) }.accessibilityLabel("编辑个人资料")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.state.nickname).flowFont(.title2, weight: .bold)
                        Text([store.state.school, store.state.major, store.state.role].filter { !$0.isEmpty }.joined(separator: " · ")).flowFont(.body).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { store.go(.settings) } label: { Image(systemName: "gearshape").flowFont(.title3).frame(width: 44, height: 44) }.accessibilityLabel("设置")
                }.padding(.horizontal, 18)
                TopicStrip(values: ["发布", "收藏", "阅读", "评论", "跟踪", "草稿"], selection: $store.profileSection)
                VStack(alignment: .leading, spacing: 22) {
                    switch store.profileSection {
                    case "阅读":
                        HStack { Text("今天读了 \(store.todaysCount) 篇").flowFont(.headline); Spacer(); Button("阅读日历") { store.selectedReadingDate = Date(); store.go(.calendar) }.flowFont(.body) }
                        ReadingHeatmap(dayCount: 91) { date in store.selectedReadingDate = date; store.go(.calendar) }
                        HStack { Button("阅读历史") { store.go(.history) }; Spacer(); Button("私人笔记") { store.go(.notes) } }.flowFont(.body)
                        ForEach(Array(store.state.history.prefix(5)), id: \.self) { id in HistoryRow(paperID: id) }
                    case "评论": CommentActivityContent()
                    case "收藏":
                        HStack { Text("\(store.state.bookmarks.count) 个收藏").flowFont(.headline); Spacer(); Button("管理收藏夹") { store.go(.collections) }.flowFont(.body) }
                        let items = store.state.bookmarks.keys.sorted().compactMap { store.item(for: $0) }
                        if items.isEmpty { EmptyHint(title: "把值得读的留下来", message: "在文献、帖子、学者或期刊页点击收藏。", symbol: "bookmark") }
                        else { FeedGrid(items: items) }
                    case "跟踪":
                        HStack { Text("\(store.state.following.count) 个跟踪").flowFont(.headline); Spacer(); Button("管理跟踪") { store.go(.following) }.flowFont(.body) }
                        let items = store.state.following.sorted().compactMap { store.item(for: $0) }
                        if items.isEmpty { EmptyHint(title: "跟踪你的研究线索", message: "跟踪文献、学者、主题或期刊。", symbol: "square.stack") }
                        else { FeedGrid(items: items) }
                    default:
                        let posts = store.profileSection == "草稿" ? store.drafts : store.published.filter(\.isMine)
                        if posts.isEmpty { EmptyHint(title: store.profileSection == "草稿" ? "还没有草稿" : "分享你的第一个想法", message: "点击底部加号，写一条阅读分享。", symbol: "square.and.pencil") }
                        else if store.profileSection == "草稿" {
                            ForEach(posts) { p in Button { editing = p } label: { HStack { Image(systemName: "doc.text"); Text(p.title).flowFont(.body); Spacer(); Image(systemName: "chevron.right") }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) }
                        } else { FeedGrid(items: posts.map { .post($0) }) }
                    }
                }.padding(.horizontal, 18)
            }.padding(.vertical, 16)
        }.background(Color.paperBackground).toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { p in ComposerView(post: p) { id in editing = nil; if let id { store.go(.post(id)) } } }
    }
}

struct ReadingHeatmap: View {
    @Environment(AppStore.self) var store
    var dayCount: Int
    var onSelect: (Date) -> Void
    private var dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let first = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today)!
        let padding = (calendar.component(.weekday, from: first) + 5) % 7
        return (0..<(dayCount + padding)).compactMap { calendar.date(byAdding: .day, value: $0 - padding, to: first) }
    }
    private func color(_ count: Int) -> Color {
        count == 0 ? Color(hex: "EDF0EB") : Color.flow.opacity([0.0, 0.23, 0.43, 0.67, 1.0][min(count, 4)])
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(16), spacing: 4), count: 7), spacing: 4) {
                        ForEach(dates, id: \.self) { date in
                            let key = store.dayKey(date)
                            let count = store.state.reads[key, default: []].count
                            Button { onSelect(date) } label: {
                                RoundedRectangle(cornerRadius: 3).fill(color(count)).frame(width: 16, height: 16)
                                    .overlay { if Calendar.current.isDateInToday(date) { RoundedRectangle(cornerRadius: 3).stroke(Color.flow, lineWidth: 1) } }
                            }.buttonStyle(.plain).id(key).accessibilityLabel("\(key)，阅读 \(count) 篇")
                        }
                    }
                }.frame(height: 140).onAppear { proxy.scrollTo(store.dayKey(Date()), anchor: .trailing) }
            }
            HStack(spacing: 5) { Text("少"); ForEach(0..<5) { n in RoundedRectangle(cornerRadius: 2).fill(color(n)).frame(width: 10, height: 10) }; Text("多") }.flowFont(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct ReadingCalendarView: View {
    @Environment(AppStore.self) var store
    @State private var date = Date()
    @State private var range = "近 90 天"
    @State private var initialized = false
    private var ids: [String] { store.state.reads[store.dayKey(date), default: []] }
    var body: some View {
        List {
            Section {
                Picker("日期范围", selection: $range) { Text("近 90 天").tag("近 90 天"); Text("近一年").tag("近一年") }.pickerStyle(.segmented)
                ReadingHeatmap(dayCount: range == "近一年" ? 365 : 91) { date = $0 }.padding(.vertical)
                DatePicker("查看日期", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            ReadableSection("\(store.dayKey(date)) · \(ids.count) 篇") {
                if ids.isEmpty { Text("这一天还没有阅读记录。").foregroundStyle(.secondary) }
                ForEach(ids, id: \.self) { id in if let p = store.paper(id) {
                    VStack(alignment: .leading, spacing: 6) {
                        PaperRow(paper: p)
                        if let stamp = store.state.readAt[store.dayKey(date)]?[id] { Text(Date(timeIntervalSince1970: stamp).formatted(date: .omitted, time: .shortened)).flowFont(.subheadline).foregroundStyle(.secondary).padding(.leading, 62) }
                    }
                } }
            }

        }.navigationTitle("阅读日历").navigationBarTitleDisplayMode(.inline).onAppear {
            if !initialized { date = store.selectedReadingDate; initialized = true }
        }
    }
}

struct HistoryRow: View {
    @Environment(AppStore.self) var store
    var paperID: String
    var body: some View {
        if let paper = store.paper(paperID) {
            VStack(alignment: .leading, spacing: 4) {
                PaperRow(paper: paper,originalTitle:true)
                Text(store.state.visitedAt[paperID].map { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) } ?? "时间未记录")
                    .flowFont(.subheadline).foregroundStyle(.secondary).padding(.leading, 62)
            }.padding(.vertical, 6)
        }
    }
}

struct HistoryView: View {
    @Environment(AppStore.self) var store
    @State private var clearing = false
    var body: some View {
        List {
            if store.state.history.isEmpty { EmptyHint(title: "从第一篇开始", message: "打开过的文献会出现在这里。", symbol: "clock") }
            ForEach(store.state.history, id: \.self) { HistoryRow(paperID: $0) }
        }.navigationTitle("阅读历史").toolbar { Button("清空") { clearing = true }.disabled(store.state.history.isEmpty) }
            .confirmationDialog("清空历史列表？阅读日历统计会保留。", isPresented: $clearing, titleVisibility: .visible) { Button("清空列表", role: .destructive) { store.state.history = []; store.state.visitedAt = [:] } }
    }
}

struct NotesView: View {
    @Environment(AppStore.self) var store
    @State private var editing: Paper?
    var body: some View {
        List {
            ReadableSection("点击文献记录想法") {
                ForEach(store.papers) { p in
                    Button { editing = p } label: { VStack(alignment: .leading, spacing: 7) { Text(p.hook).foregroundStyle(.primary); Text(store.state.notes[p.id].flatMap { $0.isEmpty ? nil : $0 } ?? "还没有笔记，点击开始写。").flowFont(.body).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 5) }
                }
            }
        }.navigationTitle("私人笔记").sheet(item: $editing) { p in NoteEditor(paperID: p.id) }
    }
}

struct EditProfileView: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var role = "本科生"
    @State private var school = ""
    @State private var major = ""
    @State private var avatar = "person.fill"
    @State private var photo: Data?
    @State private var initialized = false
    var body: some View {
        Form {
            Section {
                AvatarPhotoPicker(photo: $photo, symbol: avatar)
                LazyVGrid(columns: [.init(.adaptive(minimum: 64))], spacing: 18) {
                    ForEach(AppStore.avatars, id: \.self) { symbol in Button { avatar = symbol; photo = nil } label: { Avatar(size: 60, symbol: symbol).overlay(Circle().stroke(photo == nil && avatar == symbol ? Color.flow : .clear, lineWidth: 2)) }.buttonStyle(.plain).accessibilityLabel("头像 \(symbol)") }
                }.padding(.vertical, 12)
            } header: { Text("头像").flowFont(.headline) }
            Section {
                TextField("昵称", text: $name)
                Picker("身份", selection: $role) { ForEach(AppStore.roles, id: \.self) { Text($0) } }
                TextField("学校或机构（选填）", text: $school)
                TextField("专业或研究方向（选填）", text: $major)
            } header: { Text("个人资料").flowFont(.headline) }
            Button("修改兴趣") { store.go(.interests) }
        }.flowFont(.body).navigationTitle("编辑资料").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { store.state.nickname = name.trimmingCharacters(in: .whitespacesAndNewlines); store.state.role = role; store.state.school = school.trimmingCharacters(in: .whitespacesAndNewlines); store.state.major = major.trimmingCharacters(in: .whitespacesAndNewlines); store.state.avatarSymbol = avatar; store.state.avatarPhoto = photo; dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            .onAppear {
                guard !initialized else { return }; initialized = true
                name = store.state.nickname; role = store.state.role; school = store.state.school; major = store.state.major; avatar = store.state.avatarSymbol; photo = store.state.avatarPhoto
            }
    }
}

struct InterestSettingsView: View { var body: some View { TopicManagementView() } }

struct SettingsView: View {
    @Environment(AppStore.self) var store
    @State private var resetting = false
    @State private var clearingCache = false
    @State private var cacheStatus = ""
    var body: some View {
        List {
            Section {
                BrandMark(size: 72).frame(maxWidth: .infinity).padding(.vertical)
                Text("PaperFlow 1.5").flowFont(.headline)
                Text("文献来自网络，AI 处理完成后展示。帖子与评论保留课堂演示内容。").flowFont(.body)
                Text("统一搜索 arXiv、OpenAlex 和 Crossref，首页持续加载文献。填写个人 API 密钥后可生成解读、提出问题。论坛和消息仍为本机演示。").flowFont(.body).foregroundStyle(.secondary)
                Text("跟踪帖子后，新评论与回复进入消息页；消息页的“演示更新”用于生成本地示例事件。评论可回复和点赞，“我的 → 评论”保留互动记录。").flowFont(.body)
                Text("前台阅读 30 秒会记入当天。同篇每天只计一次；取消已读后，当天不会再自动标记，可手动重新标记。").flowFont(.body)
            }
            Section {
                Button("编辑个人资料") { store.go(.profile) }
                Button("修改兴趣") { store.go(.interests) }
                Button("AI 设置 · 我的 API 密钥") { store.go(.aiSettings) }.accessibilityIdentifier("open-ai-settings")
                Button("语言与主题颜色") { store.go(.preferences) }
                Button("个人与机构登录 / 文献服务") { store.go(.libraries) }
                if !store.state.hiddenFeedIDs.isEmpty { Button("恢复减少推荐的内容") { store.state.hiddenFeedIDs = [] } }
                Button("重新进入引导") { store.state.completedOnboarding = false; store.path = [] }
            }
            Section {
                Text("内容保存在当前手机，卸载后本机内容会被删除。API 密钥由钥匙串管理，可在 AI 设置单独删除；重置演示不会删除密钥。").flowFont(.body).foregroundStyle(.secondary)
                Button("清理原文与检索缓存") { clearingCache = true }
                if !cacheStatus.isEmpty { Text(cacheStatus).flowFont(.body) }
                Button("重置演示数据", role: .destructive) { resetting = true }
            }
        }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("清理下载的 PDF、自动封面与检索缓存？收藏、摘图、笔记和额度保留。",isPresented:$clearingCache,titleVisibility:.visible) { Button("清理缓存",role:.destructive) { LiteratureService.shared.clearCache(); FederatedLiteratureService.shared.clearCache(); PaperFileService.clearCache(); PaperArtwork.clearCache(); store.clearFullTextVerification(); cacheStatus = "缓存已清理，原文可重新下载。" } }
            .confirmationDialog("清除本机新增内容并恢复示例数据？API 密钥和课堂额度保留。", isPresented: $resetting, titleVisibility: .visible) { Button("确认重置", role: .destructive) { LiteratureService.shared.clearCache(); FederatedLiteratureService.shared.clearCache(); PaperFileService.clearCache(); store.resetDemo() } }
    }
}
