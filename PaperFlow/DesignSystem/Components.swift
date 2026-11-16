// 共用界面组件：字号、颜色、卡片、头像、标签和筛选在这里统一维护。
import SwiftUI
import UIKit
import Observation

private struct FlowFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    var weight: Font.Weight
    init(_ style: Font.TextStyle, weight: Font.Weight? = nil) {
        let points: CGFloat
        switch style {
        case .largeTitle: points = 32
        case .title: points = 27
        case .title2: points = 21
        case .title3: points = 19
        case .subheadline: points = 14
        default: points = 16
        }
        _size = ScaledMetric(wrappedValue: points, relativeTo: style)
        self.weight = weight ?? (style == .headline ? .semibold : .regular)
    }
    func body(content: Content) -> some View { content.font(.custom(FlowTypography.name, fixedSize: size).weight(weight)) }
}

extension View {
    func flowFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View { modifier(FlowFontModifier(style, weight: weight)) }
}

@MainActor @Observable
final class ThemePalette {
    static let shared = ThemePalette()
    var name = "green"
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0xDDEAE4
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static var flow: Color { Color(hex: AppThemes.hex(ThemePalette.shared.name)) }
    static let paperBackground = Color(hex: "F6F7F3")
}

struct BrandMark: View {
    var size: CGFloat = 88
    var body: some View {
        Image("BrandLogo").resizable().scaledToFit().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23)).accessibilityLabel("PaperFlow 标志")
    }
}

struct Pill: View {
    var text: String
    var selected = false
    var body: some View {
        Text(text).flowFont(.subheadline, weight: .medium).padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 44)
            .foregroundStyle(selected ? .white : Color.primary)
            .background(selected ? Color.flow : Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay { Capsule().strokeBorder(selected ? Color.flow : Color.flow.opacity(0.4), lineWidth: 1) }
    }
}

struct TopicStrip: View {
    var values: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { selection = value } label: { Pill(text: value, selected: selection == value) }.buttonStyle(.plain)
                }
            }.padding(.horizontal)
        }
    }
}

struct CoverView: View {
    var color: String
    var symbol: String
    var title: String
    var height: CGFloat = 170
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: color)
            Circle().fill(.white.opacity(0.4)).frame(width: height * 0.8).offset(x: 52, y: -35)
            Image(systemName: symbol).font(.system(size: height * 0.33, weight: .light))
                .foregroundStyle(Color.flow.opacity(0.85)).frame(maxWidth: .infinity, maxHeight: .infinity).offset(y: -12)
            Text(title).flowFont(.title3, weight: .semibold).lineLimit(1).foregroundStyle(Color.flow).padding(16)
        }.frame(height: height).clipped().accessibilityHidden(true)
    }
}

struct Avatar: View {
    var name: String = ""
    var size: CGFloat = 40
    var symbol = "person.fill"
    var photo: Data?
    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.45, weight: .medium)).foregroundStyle(Color.flow)
            }
        }.frame(width: size, height: size).background(Color.flow.opacity(0.12)).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct PostImage: View {
    var post: UserPost
    var index: Int
    @State private var decoded:UIImage?
    var body: some View {
        Group { if index < post.images.count, let uiImage = decoded {
            Image(uiImage: uiImage).resizable().scaledToFit()
        } else if let names = post.imageNames, names.indices.contains(index - post.images.count) {
            Image(names[index - post.images.count]).resizable().scaledToFit()
        } }.task(id:post.id+String(index)+String(post.timestamp)+(post.mediaRevision ?? "")) {
            if post.images.indices.contains(index) { decoded = await ImageLoader.shared.load(key:post.id+String(index)+String(post.timestamp)+(post.mediaRevision ?? ""),data:post.images[index]) }
        }.onDisappear { decoded = nil }
    }
}

struct PostThumbnail: View {
    var post: UserPost
    @State private var decoded:UIImage?
    private var selected:Int { min(max(post.coverIndex ?? 0,0),max(0,post.imageCount-1)) }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            GeometryReader { geo in
                ZStack {
                    Color(.secondarySystemBackground)
                    if let decoded { Image(uiImage:decoded).resizable().scaledToFill().frame(width:geo.size.width,height:geo.size.height).clipped() }
                    else if let names = post.imageNames,names.indices.contains(selected-post.images.count) { Image(names[selected-post.images.count]).resizable().scaledToFill().frame(width:geo.size.width,height:geo.size.height).clipped() }
                    else { Image(systemName:"photo").flowFont(.title).foregroundStyle(.tertiary) }
                }
                .overlay(alignment:.topTrailing) {
                    if post.imageCount > 1 { Label("\(post.imageCount)",systemImage:"square.on.square").flowFont(.subheadline).padding(8).background(.regularMaterial,in:Capsule()).padding(8) }
                }
            }.aspectRatio(4.0/3.0,contentMode:.fit).clipped()
            if post.coverSource == "ai" { Text("AI 示意图").flowFont(.subheadline).foregroundStyle(.secondary).padding(.horizontal,8) }
        }
        .task(id:post.id+String(post.timestamp)+(post.mediaRevision ?? "")+String(selected)+String(post.coverImage?.count ?? 0)) {
            decoded = nil
            if let data = post.coverImage ?? (post.images.indices.contains(selected) ? post.images[selected] : nil) {
                decoded = await ImageLoader.shared.load(key:post.id+"cover"+String(post.timestamp)+(post.mediaRevision ?? "")+String(selected)+String(data.count),data:data)
            }
        }.onDisappear { decoded = nil }
    }
}

struct LikeButton: View {
    @Environment(AppStore.self) var store
    var key: String
    var body: some View {
        let liked = store.state.likes.contains(key)
        Button { store.toggleLike(key) } label: {
            Image(systemName: liked ? "heart.fill" : "heart").flowFont(.title3)
                .foregroundStyle(liked ? Color.pink : Color.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(liked ? "取消点赞" : "点赞").accessibilityIdentifier("like-\(key)")
    }
}

struct FeedGrid: View {
    @Environment(\.dynamicTypeSize) var typeSize
    var items: [FeedItem]
    var metadataMode = false
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 14) {
            ForEach(items) { FeedCard(item: $0, metadataMode: metadataMode).id($0.id) }
        }
    }
}

struct FeedCard: View {
    @State private var recommendation = ""
    @Environment(AppStore.self) var store
    var item: FeedItem
    var metadataMode = false
    private var name: String {
        switch item { case .paper(let p): return p.author; case .post(let p): return p.isMine ? store.state.nickname : p.author; case .entity(let e): return e.kind }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { if let route = store.route(item.id) { store.go(route) } } label: {
                VStack(alignment: .leading, spacing: 0) {
                    switch item {
                    case .paper(let p):
                        PaperCover(paper:p)
                        Text(metadataMode && !store.hasPreparedReading(p) ? p.title : store.displayTitle(p)).flowFont(.body, weight: .semibold).foregroundStyle(.primary).lineLimit(3).padding(12)

                        if metadataMode { Text(FullTextLinks.isVerified(p) ? "已验证原文可读" : p.pdfURL != nil ? "有开放版本 · 待验证" : p.openHTMLURL != nil ? "有在线全文" : "题录 · 全文待查").flowFont(.subheadline).foregroundStyle(Color.flow).padding(.horizontal,12) }
                    case .post(let p):
                        PostThumbnail(post: p)
                        Text(p.title).flowFont(.body, weight: .semibold).foregroundStyle(.primary).lineLimit(3).padding(12)
                    case .entity(let e):
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: e.symbol).font(.system(size: 32)).foregroundStyle(Color.flow).frame(height: 65)
                            Text(e.name).flowFont(.body, weight: .semibold).foregroundStyle(.primary).lineLimit(3)
                            Text(e.detail).flowFont(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 178, alignment: .leading).padding(16)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).multilineTextAlignment(.leading).accessibilityIdentifier("card-\(item.id)")
            HStack(spacing: 0) {
                Text(name).flowFont(.subheadline).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 12)
                Spacer(minLength: 0)
                if case .entity = item { Image(systemName: "arrow.up.right").frame(width: 44, height: 44).foregroundStyle(Color.flow) }
                else { LikeButton(key: item.id) }
            }.padding(.bottom, 4)
        }.background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 18))
            .contextMenu {
                if case .paper(let paper) = item { Button("为什么推荐") { recommendation = RecommendationEngine.reason(paper,state:store.state,papers:store.papers) } }
                if case .entity = item { } else { Button("减少首页推荐", systemImage: "eye.slash") { store.hideFromFeed(item.id) } }
            }
            .alert("推荐依据",isPresented:Binding(get:{!recommendation.isEmpty},set:{if !$0 { recommendation = "" }})) { Button("知道了") { recommendation = "" } } message: { Text(recommendation) }
    }
}

struct EntityLinkRow: View {
    @Environment(AppStore.self) var store
    var key: String
    var symbol: String
    var showFollow = true
    private var followable: Bool { showFollow && ["author:", "journal:", "user:", "paper:", "topic:"].contains { key.hasPrefix($0) } }
    var body: some View {
        HStack(spacing: 10) {
            Button { if let route = store.route(key) { store.go(route) } } label: {
                HStack(spacing: 10) {
                    Avatar(size: 40, symbol: key == "user:\(store.state.nickname)" ? store.state.avatarSymbol : symbol,
                           photo: key == "user:\(store.state.nickname)" ? store.state.avatarPhoto : nil)
                    Text(store.label(key)).flowFont(.body).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if !followable { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if followable { FollowButton(key: key) }
        }
    }
}

struct TagLinks: View {
    @Environment(AppStore.self) var store
    var values: [String]
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(values, id: \.self) { topic in
                Button { store.go(.search(topic)) } label: { Pill(text: "# " + topic) }.buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 360, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, position) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified) }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += height + spacing; height = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing; height = max(height, size.height)
        }
        return (CGSize(width: width, height: subviews.isEmpty ? 0 : y + height), points)
    }
}

struct PaperRow: View {
    @Environment(AppStore.self) var store
    var paper: Paper
    var originalTitle = false
    var body: some View {
        Button { store.go(.paper(paper.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: paper.symbol).flowFont(.title3).foregroundStyle(Color.flow).frame(width: 50, height: 58)
                    .background(Color(hex: paper.color), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(originalTitle ? paper.title : store.displayTitle(paper)).flowFont(.body, weight: .medium).foregroundStyle(.primary).lineLimit(2)
                    Text("\(store.journalName(paper.journalID)) · \(String(paper.year))").flowFont(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 6)
        }.buttonStyle(.plain)
    }
}

struct EmptyHint: View {
    var title: String
    var message: String
    var symbol = "tray"
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message)).frame(minHeight: 230)
    }
}

struct FollowButton: View {
    @Environment(AppStore.self) var store
    var key: String
    var body: some View {
        Button { store.toggleFollow(key) } label: {
            Label(store.state.following.contains(key) ? "已跟踪" : "跟踪", systemImage: store.state.following.contains(key) ? "checkmark" : "plus")
        }.flowFont(.subheadline, weight: .medium).buttonStyle(.bordered).tint(.flow).frame(minHeight: 44)
            .accessibilityIdentifier("follow-\(key)")
            .accessibilityLabel((store.state.following.contains(key) ? "取消跟踪" : "跟踪") + store.label(key))
    }
}

struct FilterButton: View {
    var active: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(active ? "已筛选" : "筛选", systemImage: "line.3.horizontal.decrease").flowFont(.body, weight: .medium).frame(minHeight: 44) }
            .accessibilityIdentifier("content-filter")
    }
}

struct ContentFilterSheet: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss
    @Binding var selection: ContentFilter
    var includeEntities = false
    var papersOnly = false
    var searchMode = false
    @State private var draft = ContentFilter()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !papersOnly { Picker("内容", selection: $draft.kind) {
                        ForEach(includeEntities ? ["全部", "文献", "帖子", "学者", "期刊", "主题"] : ["全部", "文献", "帖子"], id: \.self) { Text($0 == "全部" ? "混合推荐" : $0 == "文献" ? "只看文献" : $0 == "帖子" ? "只看帖子" : $0).tag($0) }
                    } }
                    Picker("排序", selection: $draft.sort) { Text("推荐").tag("推荐"); Text("最新").tag("最新") }
                    Picker("时间", selection: $draft.time) { ForEach(["不限", "近 7 天", "近 30 天", "近一年"], id: \.self) { Text($0) } }
                }
                if searchMode {
                    ReadableSection("检索字段") {
                        Picker("字段", selection: $draft.field) { ForEach(["综合","标题","关键词","作者"], id: \.self) { Text($0) } }
                        TextField("发表期刊名称（选填）", text: $draft.journalQuery)
                        Picker("全文状态", selection: $draft.access) { ForEach(["全部","可直接阅读全文","开放全文","需授权","未确认"], id: \.self) { Text($0) } }
                    }
                    ReadableSection("检索来源（未选表示全部）") {
                        ForEach(LiteratureProvider.allCases, id: \.rawValue) { source in choice(source.rawValue, selected: draft.sources.contains(source.rawValue)) { toggle(source.rawValue, in: &draft.sources) } }
                        Button("个人与机构登录 / 文献服务设置") { dismiss(); store.go(.libraries) }
                    }
                }
                Section {
                    DisclosureGroup("预设标签") { ForEach(store.presetTopics,id: \.self) { topic in choice(topic,selected:draft.topics.contains(topic)) { toggle(topic,in:&draft.topics) } } }
                    DisclosureGroup("我的自定义标签") { ForEach(store.customTopicNames,id: \.self) { topic in choice(topic,selected:draft.topics.contains(topic)) { toggle(topic,in:&draft.topics) } } }
                    Button("管理兴趣标签") { dismiss(); store.go(.topics) }
                } header: { Text("主题").flowFont(.headline) }
                Section { ForEach(store.journals) { j in choice(j.name, selected: draft.journals.contains(j.id)) { toggle(j.id, in: &draft.journals) } } } header: { Text("期刊与来源").flowFont(.headline) }
                Section { Text("时间按论文发表时间或帖子发布时间筛选。").flowFont(.body).foregroundStyle(.secondary) }
            }.navigationTitle("筛选").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { selection = draft; dismiss() }.fontWeight(.semibold) }
                    ToolbarItem(placement: .bottomBar) { Button("重置筛选") { draft = ContentFilter() } }
                }.onAppear { draft = selection }
        }.presentationDetents([.large])
    }
    private func toggle(_ key: String, in values: inout Set<String>) { if values.contains(key) { values.remove(key) } else { values.insert(key) } }
    private func choice(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(text).foregroundStyle(.primary); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.flow) }.frame(minHeight: 36) }.buttonStyle(.plain)
    }
}

struct ReadingTimer: ViewModifier {
    @Environment(AppStore.self) var store
    @Environment(\.scenePhase) var scenePhase
    @State private var visible = false
    var paperID: String
    var enabled = true
    func body(content: Content) -> some View {
        content.onAppear { visible = true }.onDisappear { visible = false }
            .task(id: visible && scenePhase == .active && enabled) {
                guard visible && scenePhase == .active && enabled else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard visible && scenePhase == .active && enabled && !Task.isCancelled else { return }
                    store.readingTick(paperID)
                }
            }
    }
}

struct ReadableSection<Content: View>: View {
    var title: String
    var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { Section { content } header: { Text(title).flowFont(.headline).foregroundStyle(.primary).textCase(nil) } }
}
