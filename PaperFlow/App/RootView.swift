// 导航总表：Route 决定打开哪个页面，底部按钮只负责切换一级页面。
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) var store
    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            Group {
                switch store.tab {
                case 1: TrackingView()
                case 3: MessagesView()
                case 4: ProfileView()
                default: HomeView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .paper(let id): if let p = store.paper(id) { PaperDetailView(paper: p) }
                case .post(let id): PostDetailView(postID: id)
                case .source(let id, let index): if let p = store.paper(id) { SourceView(paper: p, index: index) }
                case .reader(let id): if let p = store.paper(id) { ReaderView(paper: p) }
                case .readerPage(let id, let page): if let p = store.paper(id) { ReaderView(paper: p, initialPage: page) }
                case .journal(let id): EntityView(kind: "journal", id: id)
                case .author(let id): EntityView(kind: "author", id: id)
                case .user(let id): EntityView(kind: "user", id: id)
                case .search(let query): SearchView(initialQuery: query)
                case .libraries: LibraryConnectionsView()
                case .preferences: PreferencesView()
                case .aiSettings: AISettingsView()
                case .imageSettings: ImageSettingsView()
                case .usage: UsageView()
                case .demoRecharge: DemoRechargeView()
                case .topics: TopicManagementView()
                case .aiReading(let id): AIReadingView(paperID: id)
                case .collections: CollectionsView()
                case .following: FollowManagementView()
                case .calendar: ReadingCalendarView()
                case .history: HistoryView()
                case .notes: NotesView()
                case .profile: EditProfileView()
                case .interests: InterestSettingsView()
                case .settings: SettingsView()
                case .discussion(let key, let focus): DiscussionContent(key: key, focusID: focus)
                case .reply(let key, let id): DiscussionContent(key: key, focusID: id, initialReplyID: id)
                }
            }
        }
        .sheet(isPresented: $store.showingComposer) {
            ComposerView { postID in
                store.showingComposer = false
                if let postID { store.tab = 0; store.go(.post(postID)) }
                else { store.profileSection = "草稿"; store.tab = 4; store.path = [] }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tab("首页", "house", 0)
            tab("跟踪", "square.stack", 1)
            Button { store.showingComposer = true } label: {
                Image(systemName: "plus").flowFont(.title3, weight: .medium).foregroundStyle(.white)
                    .frame(width: 48, height: 36).background(Color.flow, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity).accessibilityLabel("发布图文")
            }
            tab("消息", "bell", 3)
            tab("我的", "person", 4)
        }.padding(.top, 10).padding(.bottom, 5).background(.regularMaterial)
    }
    private func tab(_ title: String, _ icon: String, _ value: Int) -> some View {
        Button { store.tab = value; store.path = []; if value == 0 { store.homeButtonRevision += 1 } } label: {
            VStack(spacing: 4) {
                Image(systemName: store.tab == value ? icon + ".fill" : icon).font(.system(size: 20, weight: .regular))
                    .overlay(alignment: .topTrailing) { if value == 3 && store.unreadNoticeCount > 0 { Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 5, y: -3) } }
                Text(title).flowFont(.subheadline, weight: store.tab == value ? .semibold : .regular)
            }.foregroundStyle(store.tab == value ? Color.flow : .secondary).frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityLabel(value == 3 && store.unreadNoticeCount > 0 ? "消息，\(store.unreadNoticeCount) 条未读" : title)
    }
}

struct OnboardingView: View {
    @Environment(AppStore.self) var store
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var step = 0
    @State private var managingTopics = false
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack { Text("PaperFlow").flowFont(.title2, weight: .bold); Spacer(); Button("跳到 API 配置") { step = 3 }.flowFont(.body) }.padding(.horizontal, 26).padding(.top, 12)
            TabView(selection: $step) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        BrandMark(size: 110).padding(.top, 46)
                        Text("把好奇心，\n读成线索。").flowFont(.largeTitle, weight: .bold)
                        Text("发现文献，交流想法，\n留下每天的阅读积累。").flowFont(.title3).lineSpacing(8).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
                }.tag(0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        AvatarPhotoPicker(photo: $store.state.avatarPhoto, symbol: store.state.avatarSymbol)
                        Text("先认识一下你").flowFont(.largeTitle, weight: .bold)
                        TextField("昵称", text: $store.state.nickname).textContentType(.nickname).textFieldStyle(.roundedBorder)
                        Picker("AI 内容语言", selection: $store.state.targetLanguage) { ForEach(ReadingLanguages.all, id: \.self) { Text($0) } }
                        Picker("身份", selection: $store.state.role) { ForEach(AppStore.roles, id: \.self) { Text($0) } }.flowFont(.body)
                        TextField("学校或机构（选填）", text: $store.state.school).textFieldStyle(.roundedBorder)
                        TextField("专业或研究方向（选填）", text: $store.state.major).textFieldStyle(.roundedBorder)
                    }.padding(26)
                }.tag(1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Image(systemName: "sparkle.magnifyingglass").font(.system(size: 50, weight: .light)).foregroundStyle(Color.flow).padding(.top, 22)
                        Text("从你的兴趣开始").flowFont(.largeTitle, weight: .bold)
                        Text("选择感兴趣的方向，可多选。").flowFont(.body).foregroundStyle(.secondary)
                        Button("添加、删除与管理兴趣") { managingTopics = true }
                        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                            ForEach(store.availableTopics, id: \.self) { topic in
                                Button { toggle(topic) } label: { Pill(text: topic, selected: store.state.interests.contains(topic)).frame(maxWidth: .infinity) }.buttonStyle(.plain)
                            }
                        }
                    }.padding(26)
                }.tag(2)
                ScrollView { VStack(alignment:.leading,spacing:18) { Text("先准备你的 AI").flowFont(.largeTitle,weight:.bold); APISetupContent(onboarding:true) }.padding(26) }.tag(3)
            }.tabViewStyle(.page(indexDisplayMode: .never)).scrollDismissesKeyboard(.interactively)
            HStack(spacing: 10) {
                ForEach(0..<4) { index in Capsule().fill(index == step ? Color.flow : Color.flow.opacity(0.16)).frame(width: index == step ? 24 : 8, height: 8).accessibilityHidden(true) }
            }.padding(.vertical, 18)
            Button {
                if step < 3 { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { step += 1 } }
                else { store.completeOnboarding() }
            } label: { Text(step == 3 ? "开始发现" : "下一步").flowFont(.headline).frame(maxWidth: .infinity).padding(17) }
                .buttonStyle(.borderedProminent).tint(.flow).padding(.horizontal, 26).padding(.bottom, 16)
        }.background(Color.paperBackground).sheet(isPresented:$managingTopics) { NavigationStack { TopicManagementView().toolbar { Button("完成") { managingTopics = false } } } }
    }
    private func toggle(_ topic: String) {
        if store.state.interests.contains(topic) { store.state.interests.remove(topic) } else { store.state.interests.insert(topic) }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) var store
    private var filter: ContentFilter { store.state.homeFilter }
    @State private var filtering = false
    private var items: [FeedItem] { store.recommendedContent(filter: filter) }
    var body: some View {
        @Bindable var store = store
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Text("PaperFlow").flowFont(.title, weight: .bold).id("home-top")
                    Spacer(minLength: 0)
                    Button { store.go(.search("")) } label: { Image(systemName: "magnifyingglass").flowFont(.title3).frame(width: 44, height: 44) }.accessibilityLabel("搜索")
                    FilterButton(active: filter.isActive) { filtering = true }
                }
                QuotaBanner()
                ImageBalanceRecoveryView()
                if !store.hasAIKey() {
                    Button { store.go(.aiSettings) } label: { Label("配置 API，开启新的 AI 解读", systemImage:"sparkles").flowFont(.body) }.buttonStyle(.bordered)
                }
                if items.isEmpty { EmptyHint(title: "没有符合条件的内容", message: "试试放宽时间、主题或期刊条件。") }
                FeedGrid(items: items).scrollTargetLayout()
                if filter.kind != "帖子" {
                    VStack(spacing:12) {
                        if !store.homeWarnings.isEmpty { DisclosureGroup("部分来源暂不可用") { Text(store.homeWarnings.joined(separator:"\n")).flowFont(.body) } }
                        if store.homeLoading { ProgressView(store.homeProgress) }
                        if let error = store.homeError { Text(error).flowFont(.body).foregroundStyle(.secondary); Button("重试获取") { Task { await store.loadHomeNext(filter:filter) } } }
                        else if store.homeFinished { Text("当前主题暂时没有更多，可以调整兴趣或下拉刷新。").flowFont(.body).foregroundStyle(.secondary) }
                        else if !store.homeLoading { Button("继续发现") { Task { await store.loadHomeNext(filter:filter) } } }
                    }.frame(maxWidth:.infinity).padding(.vertical,20)
                        .onAppear { if store.homeError == nil { Task { await store.loadHomeNext(filter:filter) } } }
                }
            }.padding(.horizontal,16).padding(.top,8).padding(.bottom,20)
        }.scrollPosition(id: $store.homeAnchor, anchor: .top)
            .background(Color.paperBackground).toolbar(.hidden, for:.navigationBar)
            .refreshable { await store.loadHomeNext(filter:filter, refresh:true) }
            .sheet(isPresented:$filtering) { ContentFilterSheet(selection:$store.state.homeFilter) }
            .task { if store.homeCursors.isEmpty && store.homeTopicOffset == 0 { await store.loadHomeNext(filter:filter) } }
            .onAppear { store.homeOrder = items.map(\.id) }
            .onChange(of:items.map(\.id)) { _,ids in store.homeOrder = ids }
            .onChange(of:filter) { _,_ in store.recordEvent("home_filter"); Task { await store.loadHomeNext(filter:filter,refresh:true) } }
            .onChange(of:store.state.interests) { _,_ in Task { await store.loadHomeNext(filter:filter,refresh:true) } }
            .onChange(of:store.state.excludedTopics) { _,_ in Task { await store.loadHomeNext(filter:filter,refresh:true) } }
            .onChange(of:store.configurationRevision) { _,_ in Task { await store.loadHomeNext(filter:filter,refresh:true) } }
            .task(id:store.homeButtonRevision) { if store.homeButtonRevision > 0 { proxy.scrollTo("home-top",anchor:.top); await store.loadHomeNext(filter:filter,refresh:true) } }
        }
    }
}
