import Foundation

// 数据模型只描述“保存什么”。界面显示和网络请求分别放在 Features 与 Services。
nonisolated struct Insight: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var text: String
    var source: String
    var location: String
    var page: Int? // PDF 从 1 开始的页序号，可能与论文印刷页码不同。
}

nonisolated struct Paper: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var hook: String
    var subtitle: String
    var author: String
    var year: Int
    var journalID: String
    var topics: [String]
    var sourceURL: String
    var pdfURL: String?
    var localPDF: String?
    var color: String
    var symbol: String
    var coverText: String
    var insights: [Insight]
    var abstractText: String? // 在线检索返回的原始摘要，提供给 AI 时保持原文。
    var publishedAt: String? // ISO 日期；旧演示数据只有年份，仍然可以读取。
    var headlineNote: String? // 静态示例的标题澄清；真实生成结果有独立缓存。
    var doi: String?
    var journalTitle: String?
    var retrievalSources: [String]?
    var versions: [PaperVersion]?
    var fullTextStatus: String?
    var verifiedPDFURL: String? // 必须实际下载并由 PDFKit 验证后填写。
    var fullTextCheckedAt: Double?
    var openHTMLURL: String?
    var hasCachedFullText: Bool?
}

nonisolated struct Journal: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String
    var intro: String
}

nonisolated struct UserPost: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var author = "我"
    var title = ""
    var body = ""
    var links: [String] = []
    var images: [Data] = []
    var coverImage: Data? // 独立的 4:3 封面；原始配图保持完整。
    var coverSource: String? // photo / ai
    var coverIndex: Int?
    var mediaRevision:String? // 图片变更时更新，避免缩略图缓存显示旧照片。
    var imageCredits: [String]? // 与 images 同序；相册图片为空，原文摘图保留论文与页码。
    var imageNames: [String]? // 安装包中的示例图片名称；相册照片保存在 images 中。
    var color = "DCE9E3"
    var symbol = "text.book.closed"
    var timestamp = Date().timeIntervalSince1970
    var isDraft = false
    var isMine = true
    var imageCount: Int { images.count + (imageNames?.count ?? 0) }
    var topic: String { links.first(where: { $0.hasPrefix("topic:") })?.dropFirst(6).description ?? "阅读分享" }
}

nonisolated struct Comment: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var author: String
    var text: String
    var timestamp = Date().timeIntervalSince1970
    var parentID: String?
    var isMine: Bool?
    var baseLikes: Int?
    var images: [Data]?
    var paperID: String?
    var page: Int?
}

nonisolated struct InteractionNotice: Codable, Identifiable {
    var id = UUID().uuidString
    var key: String
    var commentID: String?
    var title: String
    var text: String
    var timestamp = Date().timeIntervalSince1970
}

nonisolated struct CommentActivity: Identifiable {
    var key: String
    var comment: Comment
    var reply: Comment?
    var timestamp: Double
    var id: String { reply?.id ?? comment.id }
}

nonisolated struct Catalog: Codable {
    var papers: [Paper]
    var journals: [Journal]
    var posts: [UserPost]
    var comments: [String: [Comment]]?
}

nonisolated struct LocalState: Codable {
    var completedOnboarding = false
    var nickname = "好奇的读者"
    var role = "本科生"
    var school = ""
    var major = ""
    var avatarSymbol = "person.fill"
    var avatarPhoto: Data? // 裁剪后的 512 像素 JPEG；nil 时显示默认图标。
    var importedPapers: [Paper] = []
    var generatedReadings: [String: GeneratedReading] = [:]
    var aiConfiguration = AIConfiguration() // 只保存地址与模型，密钥由钥匙串独立保存。
    var hiddenFeedIDs: Set<String> = []
    var targetLanguage = "简体中文"
    var theme = "green"
    var libraryConfiguration = LibraryConfiguration()
    var webVisits: [String: Double] = [:]
    var interests: Set<String> = ["生成式 AI", "交互设计"]
    var folders = ["待读", "研究灵感"]
    var bookmarks: [String: String] = [:]
    var following: Set<String> = []
    var likes: Set<String> = []
    var posts: [UserPost] = []
    var comments: [String: [Comment]] = [:]
    var reads: [String: [String]] = [:]
    var readingSeconds: [String: Int] = [:]
    var history: [String] = []
    var visitedAt: [String: Double] = [:]
    var readAt: [String: [String: Double]] = [:]
    var dismissedReads: [String: [String]] = [:]
    var notes: [String: String] = [:]
    var readMessages: Set<String> = []
    var likedCommentIDs: Set<String> = []
    var commentLikedAt: [String: Double] = [:]
    var notices: [InteractionNotice] = []
    var demoActivityIndex = 0
    var demoRevision = 0
    var customTopics: [ResearchTopic] = []
    var deletedPresetTopics: Set<String> = []
    var excludedTopics: Set<String> = []
    var homeFilter = ContentFilter()
    var apiProfiles: [AIConfiguration] = []
    var apiMode = "demo"
    var imageConfiguration = ImageConfiguration()
    var imageGenerations: [String:ImageCoverRecord] = [:] // 内容缓存索引
    var imageCalls: [String:ImageCoverRecord] = [:] // 按 requestID 保留每次调用，包括失败重试
    var demoQuota: DemoQuota?
    var usageRecords: [UsageRecord] = []
    var tokenTotal: Int?
    var tokenDays: [String:Int]?
    var covers: [String: CoverAsset] = [:]
    var readerPositions: [String: Int] = [:]
    var translations: [String: TranslationResult] = [:]
    var eventCounts: [String:Int] = [:]
    var revision = 0

    init() { }
    // 新字段用 decodeIfPresent 提供默认值：升级时保留用户原有收藏、评论和阅读记录。
    enum CodingKeys: String, CodingKey {
        case imageConfiguration, imageGenerations, imageCalls
        case customTopics, deletedPresetTopics, excludedTopics, homeFilter, apiProfiles, apiMode, demoQuota, usageRecords, tokenTotal, tokenDays, covers, readerPositions, translations, eventCounts, revision
        case completedOnboarding, nickname, role, school, major, avatarSymbol, avatarPhoto, importedPapers, generatedReadings, aiConfiguration, hiddenFeedIDs, targetLanguage, theme, libraryConfiguration, webVisits, interests, folders, bookmarks, following, likes, posts, comments, reads, readingSeconds, history, visitedAt, readAt, dismissedReads, notes, readMessages, likedCommentIDs, commentLikedAt, notices, demoActivityIndex, demoRevision
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        imageConfiguration = try c.decodeIfPresent(ImageConfiguration.self,forKey:.imageConfiguration) ?? imageConfiguration
        imageGenerations = try c.decodeIfPresent([String:ImageCoverRecord].self,forKey:.imageGenerations) ?? [:]
        imageCalls = try c.decodeIfPresent([String:ImageCoverRecord].self,forKey:.imageCalls) ?? [:]
        customTopics = try c.decodeIfPresent([ResearchTopic].self, forKey: .customTopics) ?? customTopics
        deletedPresetTopics = try c.decodeIfPresent(Set<String>.self, forKey: .deletedPresetTopics) ?? deletedPresetTopics
        excludedTopics = try c.decodeIfPresent(Set<String>.self, forKey: .excludedTopics) ?? excludedTopics
        homeFilter = try c.decodeIfPresent(ContentFilter.self, forKey: .homeFilter) ?? homeFilter
        apiProfiles = try c.decodeIfPresent([AIConfiguration].self, forKey: .apiProfiles) ?? apiProfiles
        apiMode = try c.decodeIfPresent(String.self, forKey: .apiMode) ?? apiMode
        demoQuota = try c.decodeIfPresent(DemoQuota.self, forKey: .demoQuota)
        usageRecords = try c.decodeIfPresent([UsageRecord].self, forKey: .usageRecords) ?? usageRecords
        tokenTotal = try c.decodeIfPresent(Int.self, forKey:.tokenTotal)
        tokenDays = try c.decodeIfPresent([String:Int].self, forKey:.tokenDays)
        covers = try c.decodeIfPresent([String: CoverAsset].self, forKey: .covers) ?? covers
        readerPositions = try c.decodeIfPresent([String: Int].self, forKey: .readerPositions) ?? readerPositions
        translations = try c.decodeIfPresent([String: TranslationResult].self, forKey: .translations) ?? translations
        eventCounts = try c.decodeIfPresent([String:Int].self, forKey: .eventCounts) ?? [:]
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? revision
        completedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .completedOnboarding) ?? completedOnboarding
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? nickname
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? role
        school = try c.decodeIfPresent(String.self, forKey: .school) ?? school
        major = try c.decodeIfPresent(String.self, forKey: .major) ?? major
        avatarSymbol = try c.decodeIfPresent(String.self, forKey: .avatarSymbol) ?? avatarSymbol
        avatarPhoto = try c.decodeIfPresent(Data.self, forKey: .avatarPhoto)
        importedPapers = try c.decodeIfPresent([Paper].self, forKey: .importedPapers) ?? []
        generatedReadings = try c.decodeIfPresent([String: GeneratedReading].self, forKey: .generatedReadings) ?? [:]
        aiConfiguration = try c.decodeIfPresent(AIConfiguration.self, forKey: .aiConfiguration) ?? AIConfiguration()
        hiddenFeedIDs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenFeedIDs) ?? []
        targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage) ?? targetLanguage
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? theme
        libraryConfiguration = try c.decodeIfPresent(LibraryConfiguration.self, forKey: .libraryConfiguration) ?? LibraryConfiguration()
        webVisits = try c.decodeIfPresent([String: Double].self, forKey: .webVisits) ?? [:]
        interests = try c.decodeIfPresent(Set<String>.self, forKey: .interests) ?? interests
        folders = try c.decodeIfPresent([String].self, forKey: .folders) ?? folders
        bookmarks = try c.decodeIfPresent([String: String].self, forKey: .bookmarks) ?? bookmarks
        following = try c.decodeIfPresent(Set<String>.self, forKey: .following) ?? following
        likes = try c.decodeIfPresent(Set<String>.self, forKey: .likes) ?? likes
        posts = try c.decodeIfPresent([UserPost].self, forKey: .posts) ?? posts
        comments = try c.decodeIfPresent([String: [Comment]].self, forKey: .comments) ?? comments
        reads = try c.decodeIfPresent([String: [String]].self, forKey: .reads) ?? reads
        readingSeconds = try c.decodeIfPresent([String: Int].self, forKey: .readingSeconds) ?? readingSeconds
        history = try c.decodeIfPresent([String].self, forKey: .history) ?? history
        visitedAt = try c.decodeIfPresent([String: Double].self, forKey: .visitedAt) ?? visitedAt
        readAt = try c.decodeIfPresent([String: [String: Double]].self, forKey: .readAt) ?? readAt
        dismissedReads = try c.decodeIfPresent([String: [String]].self, forKey: .dismissedReads) ?? dismissedReads
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? notes
        readMessages = try c.decodeIfPresent(Set<String>.self, forKey: .readMessages) ?? readMessages
        likedCommentIDs = try c.decodeIfPresent(Set<String>.self, forKey: .likedCommentIDs) ?? likedCommentIDs
        commentLikedAt = try c.decodeIfPresent([String: Double].self, forKey: .commentLikedAt) ?? commentLikedAt
        notices = try c.decodeIfPresent([InteractionNotice].self, forKey: .notices) ?? notices
        demoActivityIndex = try c.decodeIfPresent(Int.self, forKey: .demoActivityIndex) ?? demoActivityIndex
        demoRevision = try c.decodeIfPresent(Int.self, forKey: .demoRevision) ?? demoRevision
    }
}

nonisolated struct ContentFilter: Codable, Equatable, Hashable {
    var kind = "全部"
    var topics: Set<String> = []
    var journals: Set<String> = []
    var time = "不限"
    var sort = "推荐"
    var sources: Set<String> = [] // 空集合表示全部来源；与发表期刊分开。
    var field = "综合"
    var journalQuery = ""
    var access = "全部"
    var isActive: Bool { self != ContentFilter() }
}

nonisolated struct DiscoveryEntity: Identifiable {
    var id: String
    var name: String
    var kind: String
    var detail: String
    var symbol: String
}

nonisolated enum Route: Hashable {
    case paper(String), post(String), journal(String), author(String), user(String)
    case search(String), libraries, aiSettings, aiReading(String), preferences, imageSettings, usage, demoRecharge, topics
    case collections, following, calendar, history, notes, profile, interests, settings
    case source(String, Int), reader(String), readerPage(String, Int)
    case discussion(String, String?), reply(String, String)
}

nonisolated enum FeedItem: Identifiable {
    case paper(Paper), post(UserPost), entity(DiscoveryEntity)
    var id: String {
        switch self {
        case .paper(let p): return "paper:\(p.id)"
        case .post(let p): return "post:\(p.id)"
        case .entity(let e): return e.id
        }
    }
}
