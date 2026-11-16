// 发现与管理：本机搜索、学者期刊、收藏、跟踪和本机消息。
import SwiftUI

/// 一个入口合并本机与公共文献检索；输入不发请求，提交或完成筛选后再联网。
struct SearchView: View {
    @Environment(AppStore.self) var store
    @State private var query: String
    @State private var submitted = ""
    @State private var filter = ContentFilter()
    @State private var filtering = false
    @State private var searched = false
    @State private var loading = false
    @State private var next: [String:String] = [:]
    @State private var warnings: [String] = []
    @State private var error: String?
    @State private var request: Task<Void,Never>?
    @State private var requestID = UUID()
    @State private var remoteIDs: [String] = []
    @State private var cacheLabel = ""
    @State private var progress = "正在检索…"
    init(initialQuery: String) { _query = State(initialValue:initialQuery) }
    private var items: [FeedItem] {
        var list = store.content(query: searched ? submitted : query, filter:filter, includeEntities:true)
        if filter.kind == "全部" || filter.kind == "文献" {
            let ids = Set(list.map(\.id))
            list += remoteIDs.compactMap { store.paper($0) }.filter { store.accepts($0,filter:filter) && !ids.contains("paper:" + $0.id) }.map { .paper($0) }
        }
        if filter.sort != "最新",!submitted.isEmpty {
            list.sort { a,b in
                func score(_ item:FeedItem) -> Double { if case .paper(let paper) = item { return SearchRanking.score(paper,query:submitted) };return 0 }
                let left = score(a),right = score(b);return left == right ? a.id < b.id : left > right
            }
        }
        return list
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:18) {
                HStack(spacing:12) {
                    Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索文献、笔记、作者、期刊",text:$query).flowFont(.body).submitLabel(.search).onSubmit { search() }.accessibilityIdentifier("search-query")
                    Button("搜索") { search() }.accessibilityIdentifier("unified-search-submit")
                }.frame(minHeight:50).padding(.horizontal,14).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))
                HStack { Text(searched ? "搜索结果" : "发现内容").flowFont(.headline); Spacer(); FilterButton(active:filter.isActive) { filtering = true } }
                if !cacheLabel.isEmpty { Text(cacheLabel).flowFont(.subheadline).foregroundStyle(.secondary) }
                if !warnings.isEmpty { Text(warnings.joined(separator:"\n")).flowFont(.body).foregroundStyle(.secondary); Button("重试未完成来源") { search() } }
                if items.isEmpty && !loading && error == nil {
                    EmptyHint(title:warnings.isEmpty ? "没有符合条件的结果" : "当前来源未返回可用结果",message:"试试论文原标题、DOI 或 arXiv 编号，也可以放宽筛选。",symbol:"magnifyingglass")
                    if filter.isActive { Button("清除筛选并重试") { filter = ContentFilter() } }
                }
                FeedGrid(items:items,metadataMode:true)
                if loading { HStack { ProgressView(progress); Spacer(); Button("取消") { request?.cancel() } }.padding(.vertical) }
                if let error { Text(error).flowFont(.body); Button("重试搜索") { search() } }
                if searched && !loading && !next.isEmpty {
                    Button("加载更多结果") { search(more:true) }.frame(maxWidth:.infinity,minHeight:44)
                        .onAppear { if error == nil { search(more:true) } }
                }
            }.padding(16)
        }.background(Color.paperBackground).navigationTitle("搜索").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented:$filtering) { ContentFilterSheet(selection:$filter,includeEntities:true,searchMode:true) }
            .onChange(of:filter) { _,_ in search() }
            .onDisappear { request?.cancel() }
    }
    private func search(more: Bool = false) {
        guard !more || !loading else { return }
        request?.cancel()
        let token = UUID(); requestID = token
        if !more { submitted = query.trimmingCharacters(in:.whitespacesAndNewlines); remoteIDs = []; next = [:]; warnings = []; cacheLabel = "" }
        searched = true; error = nil
        guard filter.kind != "帖子" else { loading = false; return }
        var options = filter
        if filter.kind == "学者" { options.field = "作者" }
        if filter.kind == "期刊" { options.journalQuery = submitted }
        let term = filter.kind == "期刊" ? "" : submitted.isEmpty ? filter.topics.sorted().joined(separator:" ") : submitted
        let cursor = more ? next : nil
        progress = "正在检索文献来源…"
        loading = true
        request = Task { @MainActor in
            defer { if requestID == token { loading = false } }
            do {
                let page = try await FederatedLiteratureService.shared.search(query:term,filter:options,cursors:cursor,openAlexKey:LibraryKeyStore.read(),coreKey:LibraryKeyStore.read("CORE"),refresh:!more,onUpdate:{ partial in
                    guard requestID == token,!Task.isCancelled else { return }
                    let ids = store.importPapers(partial.papers)
                    remoteIDs = Array(NSOrderedSet(array:remoteIDs+ids)) as? [String] ?? remoteIDs
                    progress = "已取得 \(remoteIDs.count) 条，继续检索其他来源…"
                })
                try Task.checkCancellation(); guard requestID == token else { return }
                let ids = store.importPapers(page.papers)
                remoteIDs = Array(NSOrderedSet(array:remoteIDs+ids)) as? [String] ?? remoteIDs
                if options.access == "可直接阅读全文" {
                    let candidates = page.papers.sorted { !FullTextLinks.candidates($0).isEmpty && FullTextLinks.candidates($1).isEmpty }.prefix(10)
                    let ids = store.importPapers(Array(candidates))
                    var checked = 0
                    for start in stride(from:0,to:ids.count,by:3) {
                        try Task.checkCancellation(); guard requestID == token else { return }
                        progress = "正在验证原文 \(checked) / \(ids.count)…"
                        await withTaskGroup(of:Void.self) { group in
                            for id in ids[start..<min(start+3,ids.count)] { group.addTask { @MainActor in _ = try? await store.obtainFullText(id,allowLookup:false) } }
                        }
                        checked = min(start+3,ids.count)
                    }
                    try Task.checkCancellation(); guard requestID == token else { return }
                }
                next = page.next; warnings = page.warnings
                let expansion = FederatedLiteratureService.expanded(term)
                cacheLabel = (page.cached ? "缓存结果" : "已检索公共文献") + (expansion != term ? " · " + expansion : "") + (options.access == "可直接阅读全文" ? " · 已验证前 10 条候选，可继续加载" : "")
            } catch { if requestID == token { self.error = Task.isCancelled ? "已取消，已有结果保留。" : error.localizedDescription } }
        }
    }
}

struct EntityView: View {
    @Environment(AppStore.self) var store
    var kind: String
    var id: String
    @State private var saving = false
    private var title: String { kind == "journal" ? store.journalName(id) : id }
    private var papers: [Paper] { store.papers.filter { kind == "journal" ? $0.journalID == id : kind == "user" && id == "PaperFlow AI" ? store.hasPreparedReading($0) : kind == "author" && $0.author == id } }
    private var posts: [UserPost] {
        store.published.filter { p in
            if kind == "user" { return p.isMine ? id == store.state.nickname : p.author == id }
            return p.links.contains("\(kind):\(id)") || p.links.contains { key in key.hasPrefix("paper:") && papers.contains { key == "paper:\($0.id)" } }
        }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 15) {
                    Image(systemName: kind == "journal" ? "books.vertical" : "person.crop.circle").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Color.flow)
                    Text(title).flowFont(.title2, weight: .bold)
                    if kind == "journal", let j = store.journal(id) {
                        Text(j.kind).flowFont(.subheadline).foregroundStyle(Color.flow)
                        Text(j.intro).flowFont(.subheadline).foregroundStyle(.secondary)
                    } else { Text(kind == "author" ? "本地收录的文献与讨论" : "阅读分享与研究兴趣").flowFont(.subheadline).foregroundStyle(.secondary) }
                    HStack {
                        if kind != "user" || id != store.state.nickname { FollowButton(key: "\(kind):\(id)") }
                        if kind != "user" { Button("收藏") { saving = true }.buttonStyle(.bordered).flowFont(.body) }
                    }
                }.padding(.vertical, 12)
            }
            if !papers.isEmpty { ReadableSection("相关文献") { ForEach(papers) { PaperRow(paper: $0) } } }
            ReadableSection("相关图文") {
                if posts.isEmpty { Text("还没有相关帖子，可以从底部发布入口分享想法。").flowFont(.subheadline).foregroundStyle(.secondary) }
                ForEach(posts) { p in Button(p.title) { store.go(.post(p.id)) }.foregroundStyle(.primary) }
            }
        }.navigationTitle(kind == "journal" ? "期刊与来源" : kind == "author" ? "学者主页" : "用户主页")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $saving) { BookmarkPicker(key: "\(kind):\(id)") }
    }
}

struct BookmarkPicker: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    var key: String
    @State private var newName = ""
    var body: some View {
        NavigationStack {
            List {
                ReadableSection("选择收藏夹后保存") {
                    ForEach(store.state.folders, id: \.self) { folder in
                        Button { store.bookmark(key, folder: folder); dismiss() } label: {
                            HStack { Label(folder, systemImage: "folder"); Spacer(); if store.state.bookmarks[key] == folder { Image(systemName: "checkmark") } }
                        }
                    }
                }
                ReadableSection("新建收藏夹") {
                    TextField("收藏夹名称", text: $newName)
                    Button("创建并收藏") { store.addFolder(newName); store.bookmark(key, folder: newName.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if store.state.bookmarks[key] != nil { Button("移出收藏", role: .destructive) { store.bookmark(key, folder: nil); dismiss() } }
            }.navigationTitle("选择收藏夹").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct CollectionsView: View {
    @Environment(AppStore.self) var store
    @State private var folder = "全部"
    @State private var kind = "全部"
    @State private var journal = "全部"
    @State private var newFolder = false
    @State private var name = ""
    private var keys: [String] {
        store.state.bookmarks.keys.filter { key in
            let typeMatches = kind == "全部" || key.hasPrefix(["文献": "paper:", "帖子": "post:", "学者": "author:", "期刊": "journal:"][kind] ?? "")
            let folderMatches = folder == "全部" || store.state.bookmarks[key] == folder
            var journalMatches = journal == "全部"
            let id = key.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            if key.hasPrefix("paper:") { journalMatches = journalMatches || store.paper(id)?.journalID == journal }
            if key.hasPrefix("post:") { journalMatches = journalMatches || store.post(id).map { store.journalIDs(for: $0).contains(journal) } == true }
            if key.hasPrefix("journal:") { journalMatches = journalMatches || id == journal }
            if key.hasPrefix("author:") { journalMatches = journalMatches || store.papers.contains { $0.author == id && $0.journalID == journal } }
            return typeMatches && folderMatches && journalMatches
        }.sorted()
    }
    var body: some View {
        List {
            Section {
                Picker("收藏夹", selection: $folder) { Text("全部").tag("全部"); ForEach(store.state.folders, id: \.self) { Text($0) } }
                Picker("内容类型", selection: $kind) { ForEach(["全部", "文献", "帖子", "学者", "期刊"], id: \.self) { Text($0) } }
                Picker("期刊／来源", selection: $journal) { Text("全部").tag("全部"); ForEach(store.journals) { Text($0.name).tag($0.id) } }
            }
            ReadableSection("已收藏 · \(keys.count)") {
                if keys.isEmpty { EmptyHint(title: "把值得读的留下来", message: "在文献、帖子或期刊页点击收藏。", symbol: "bookmark") }
                ForEach(keys, id: \.self) { key in
                    Button { if let route = store.route(key) { store.go(route) } } label: {
                        VStack(alignment: .leading, spacing: 7) { Text(store.label(key)).foregroundStyle(.primary); Text(store.state.bookmarks[key] ?? "").flowFont(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 5)
                    }.swipeActions { Button("移除", role: .destructive) { store.bookmark(key, folder: nil) } }
                }
            }
        }.navigationTitle("我的收藏")
            .toolbar { Button { newFolder = true } label: { Image(systemName: "folder.badge.plus") }.accessibilityLabel("新建收藏夹") }
            .alert("新建收藏夹", isPresented: $newFolder) { TextField("名称", text: $name); Button("创建") { store.addFolder(name); name = "" }; Button("取消", role: .cancel) { } }
    }
}

struct TrackingView: View {
    @Environment(AppStore.self) var store
    var body: some View {
        List {
            Section {
                HStack { VStack(alignment: .leading, spacing: 5) { Text("继续你的研究线索").flowFont(.headline); Text("已跟踪 \(store.state.following.count) 个对象").flowFont(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "square.stack").foregroundStyle(Color.flow) }.padding(.vertical, 12)
                Button("管理跟踪") { store.go(.following) }
            }
            ReadableSection("相关文献") {
                if store.followedPapers.isEmpty { EmptyHint(title: "关注一个研究方向", message: "在文献、学者、主题或期刊页开启跟踪，相关内容会出现在这里。", symbol: "square.stack") }
                ForEach(store.followedPapers) { p in
                    PaperRow(paper: p)
                }
            }
            ReadableSection("相关讨论") {
                ForEach(store.relatedPosts) { post in Button(post.title) { store.go(.post(post.id)) }.foregroundStyle(.primary) }
            }
        }.listStyle(.insetGrouped).navigationTitle("跟踪")
    }
}

struct FollowManagementView: View {
    @Environment(AppStore.self) var store
    @State private var kind = "全部"
    private var keys: [String] { store.state.following.filter { key in kind == "全部" || key.hasPrefix(["文献":"paper:", "帖子":"post:", "学者":"author:", "用户":"user:", "主题":"topic:", "期刊":"journal:"][kind] ?? "") }.sorted() }
    var body: some View {
        List {
            Picker("类型", selection: $kind) { ForEach(["全部", "文献", "帖子", "学者", "用户", "主题", "期刊"], id: \.self) { Text($0) } }
            if keys.isEmpty { Text("还没有这个类型的跟踪对象。").foregroundStyle(.secondary) }
            ForEach(keys, id: \.self) { key in
                HStack {
                    Button(store.label(key)) { if let route = store.route(key) { store.go(route) } }.foregroundStyle(.primary)
                    Spacer(); Button { store.toggleFollow(key) } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.buttonStyle(.borderless).accessibilityLabel("取消跟踪")
                }
            }
        }.navigationTitle("跟踪管理").toolbar { Button { store.go(.search("")) } label: { Image(systemName: "plus") }.accessibilityLabel("添加跟踪") }
    }
}

struct MessagesView: View {
    @Environment(AppStore.self) var store
    var body: some View {
        List {
            Section {
                HStack {
                    Text("消息").flowFont(.title, weight: .bold)
                    Spacer()
                    Button("全部已读") { store.markAllMessagesRead() }.flowFont(.subheadline)
                }
                Button { store.simulateFollowedPostActivity() } label: { Label("演示更新", systemImage: "bubble.left.and.bubble.right") }
                    .disabled(store.followedPosts.isEmpty).accessibilityIdentifier("simulate-post-update")
                Text("本地演示：跟踪帖子后，点击此按钮添加一条示例评论或回复。").flowFont(.subheadline).foregroundStyle(.secondary)
            }
            ReadableSection("评论与回复") {
                if store.state.notices.isEmpty { Text("跟踪帖子后，新评论和回复会出现在这里；别人回复你的评论时也会提醒。").flowFont(.body).foregroundStyle(.secondary) }
                ForEach(store.state.notices) { notice in
                    Button { store.openNotice(notice) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            if notice.key.hasPrefix("post:"), let post = store.post(String(notice.key.dropFirst(5))) { PostImage(post:post,index:0).frame(width:54,height:68).clipped().clipShape(RoundedRectangle(cornerRadius:8)) }
                            else if notice.key.hasPrefix("paper:"), let paper = store.paper(String(notice.key.dropFirst(6))) { PaperCover(paper:paper).frame(width:72).clipShape(RoundedRectangle(cornerRadius:8)) }
                            Circle().fill(store.state.readMessages.contains(notice.id) ? Color.clear : Color.flow).frame(width: 8, height: 8).padding(.top, 8)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(notice.title).flowFont(.body, weight: .medium).foregroundStyle(.primary)
                                Text(notice.text).flowFont(.body).foregroundStyle(.primary).lineLimit(2)
                                Text(store.label(notice.key)).flowFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Text(Date(timeIntervalSince1970: notice.timestamp).formatted(date: .abbreviated, time: .shortened)).flowFont(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("notice-\(notice.id)")
                }
            }
            if !store.followedPapers.isEmpty {
                ReadableSection("资料动态示例") {
                    ForEach(store.followedPapers) { p in
                        Button { store.state.readMessages.insert(p.id); store.go(.paper(p.id)) } label: { Text(p.hook).flowFont(.body).foregroundStyle(.primary) }
                    }
                }
            }
            ReadableSection("系统消息") { DisclosureGroup("欢迎来到 PaperFlow") { Text("评论、回复、点赞、跟踪和消息保存在这台手机。此版本不接收服务器更新或系统推送。").flowFont(.body).foregroundStyle(.secondary) } }
        }.toolbar(.hidden, for: .navigationBar)
    }
}
