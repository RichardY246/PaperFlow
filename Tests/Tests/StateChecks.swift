import Foundation

@main
struct StateChecks {
    @MainActor static func main() async throws {
        let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
        let folder = URL.temporaryDirectory.appending(path: "PaperFlow-Checks-\(UUID().uuidString)")
        let store = AppStore(directory: folder, catalogURL: catalog)
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { fatalError("FAIL: \(label)") }
            print("PASS: \(label)")
        }
        check(store.storageError == nil && store.catalog.papers.count == 8 && store.published.count == 5, "示例数据库完整加载")
        check(store.todaysCount == 0, "历史示例不混入今天的计数")
        let all = store.feed()
        check(Set(all.map(\.id)).count == all.count, "混合推荐没有重复内容")
        check(all.contains { if case .post = $0 { return true }; return false }, "混合推荐包含用户帖子")
        check(store.feed(kind: "只看文献").allSatisfy { if case .paper = $0 { return true }; return false }, "首页类型筛选有效")
        store.state.interests = ["计算机视觉"]
        if case .paper(let p) = store.feed().first { check(p.topics.contains("计算机视觉"), "兴趣变化会调整首页顺序") }
        else { fatalError("FAIL: first item is not a paper") }
        store.addFolder("  测试收藏夹  ")
        store.addFolder("测试收藏夹")
        check(store.state.folders.filter { $0 == "测试收藏夹" }.count == 1, "收藏夹去重与名称清理")
        store.bookmark("paper:rag", folder: "测试收藏夹")
        store.toggleFollow("journal:nature")
        check(store.followedPapers.contains { $0.id == "deep" }, "期刊跟踪能关联文献动态")
        store.markRead("rag"); store.markRead("rag")
        check(store.todaysCount == 1, "当天重复阅读只计一篇")
        store.markRead("does-not-exist")
        check(store.todaysCount == 1, "无效文献不会增加阅读量")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        store.markRead("rag", date: yesterday)
        check(store.state.reads[store.dayKey(yesterday), default: []].contains("rag"), "跨天阅读分别保存")
        for _ in 0..<29 { store.readingTick("clip") }
        check(!store.state.reads[store.dayKey(Date()), default: []].contains("clip"), "未满 30 秒不自动计数")
        store.readingTick("clip")
        check(store.todaysCount == 2, "满 30 秒自动记入阅读日历")
        var post = UserPost(); post.title = "测试草稿"; post.body = "测试发布内容"; post.isDraft = true
        store.savePost(post)
        check(store.drafts.contains { $0.id == post.id }, "草稿可保存")
        post.isDraft = false; post.links = ["paper:rag", "journal:arxiv"]; post.images = [Data([1,2,3])]
        store.savePost(post)
        check(!store.drafts.contains { $0.id == post.id } && store.published.contains { $0.id == post.id }, "草稿发布后不会留下重复版本")
        store.comment("paper:rag", text: "   ")
        check(store.state.comments["paper:rag", default: []].isEmpty, "空评论不会保存")
        store.comment("paper:rag", text: "一个想法")
        store.state.notes["rag"] = "我的笔记"
        store.completeOnboarding()
        await store.flushStorage()
        let reopened = AppStore(directory: folder, catalogURL: catalog)
        check(reopened.state.completedOnboarding && reopened.state.bookmarks["paper:rag"] == "测试收藏夹", "重新启动后引导和收藏状态保留")
        check(reopened.state.following.contains("journal:nature") && reopened.todaysCount == 2, "重新启动后跟踪和当天阅读保留")
        check(reopened.post(post.id)?.images == post.images && reopened.post(post.id)?.links == post.links, "重新启动后图文和关联资料保留")
        check(reopened.state.comments["paper:rag"]?.count == 1 && reopened.state.notes["rag"] == "我的笔记", "重新启动后评论和笔记保留")
        reopened.bookmark("paper:rag", folder: nil)
        check(reopened.state.bookmarks["paper:rag"] == nil, "取消收藏生效")
        reopened.deletePost(post.id)
        check(reopened.post(post.id) == nil, "本人帖子可以删除")
        let badFolder = URL.temporaryDirectory.appending(path: "PaperFlow-Corruption-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: badFolder, withIntermediateDirectories: true)
        let badFile = badFolder.appending(path: "user-state-v1.json")
        let broken = Data("{broken".utf8)
        try broken.write(to: badFile)
        let badStore = AppStore(directory: badFolder, catalogURL: catalog)
        badStore.state.nickname = "不能覆盖损坏原件"
        check(badStore.storageError != nil && (try? Data(contentsOf: badFile)) == broken, "损坏的数据文件会保留，不会被空白状态覆盖")
        // New read controls must survive timers and relaunches.
        reopened.toggleRead("rag")
        check(!reopened.isRead("rag"), "可以取消今天的阅读标记")
        for _ in 0..<60 { reopened.readingTick("rag") }
        check(!reopened.isRead("rag"), "取消后自动计时不会重新标记")
        await reopened.flushStorage()
        let suppressed = AppStore(directory: folder, catalogURL: catalog)
        for _ in 0..<30 { suppressed.readingTick("rag") }
        check(!suppressed.isRead("rag"), "重启后保留当天取消标记的选择")
        suppressed.toggleRead("rag")
        check(suppressed.isRead("rag") && suppressed.state.readAt[suppressed.dayKey(Date())]?["rag"] != nil, "可以重新标记并记录实际时间")
        let visitTime = Date(timeIntervalSince1970: 1792584000)
        suppressed.visit("rag", date: visitTime)
        suppressed.visit("rag", date: visitTime.addingTimeInterval(60))
        check(suppressed.state.history.filter { $0 == "rag" }.count == 1 && suppressed.state.visitedAt["rag"] == visitTime.timeIntervalSince1970 + 60, "历史保留最近访问时间且不会重复")
        await suppressed.flushStorage()
        let savedVisit = AppStore(directory: folder, catalogURL: catalog)
        check(savedVisit.state.visitedAt["rag"] == visitTime.timeIntervalSince1970 + 60, "访问时间重启后保留")
        var filter = ContentFilter(); filter.kind = "帖子"; filter.journals = ["arxiv"]
        let journalPosts = savedVisit.content(filter: filter)
        check(journalPosts.contains { $0.id == "post:sample-1" }, "期刊筛选能通过关联论文找到帖子")
        check(journalPosts.allSatisfy { if case .post = $0 { return true }; return false }, "组合筛选正确限制内容类型")
        filter.topics = ["计算机视觉"]
        check(savedVisit.content(filter: filter).contains { $0.id == "post:sample-2" }, "主题与期刊可组合筛选")
        filter = ContentFilter(); filter.kind = "文献"; filter.topics = ["计算机视觉"]; filter.journals = ["nature"]
        check(savedVisit.content(filter: filter).map(\.id) == ["paper:deep"], "文献多条件筛选返回正确结果")
        filter = ContentFilter(); filter.kind = "学者"
        check(savedVisit.content(query: "Vaswani", filter: filter, includeEntities: true).map(\.id) == ["author:Ashish Vaswani"], "学者搜索只返回学者卡片")
        filter.kind = "期刊"
        check(savedVisit.content(query: "Nature", filter: filter, includeEntities: true).map(\.id) == ["journal:nature"], "期刊搜索与学者使用同一实体结果")
        filter = ContentFilter(); filter.kind = "帖子"; filter.time = "近 7 天"
        check(!savedVisit.content(filter: filter, now:Date(timeIntervalSince1970:savedVisit.published.map(\.timestamp).max()!)).isEmpty, "时间筛选保留近期帖子")
        filter.kind = "文献"
        check(savedVisit.content(filter: filter).isEmpty, "旧论文不会混入近七天结果")
        check(savedVisit.content(query: "RAG").contains { $0.id == "paper:rag" }, "英文标题可搜索")
        check(savedVisit.content(query: "不存在的演示资料").isEmpty, "未知资料不会产生虚构搜索结果")
        check(savedVisit.published.filter { $0.imageCount > 1 }.count >= 3, "示例库有多条多图帖子")
        check(savedVisit.published.allSatisfy { !(savedVisit.state.comments["post:\($0.id)"] ?? []).isEmpty }, "全部示例帖子预置了评论")
        check(savedVisit.catalog.papers.allSatisfy { $0.localPDF != nil && !$0.insights.contains { $0.source.isEmpty || $0.page == nil } }, "所有论文有本地原文与页码")

        // Simulate an installed v1 database; do not fabricate times for old visits.
        let legacyFolder = URL.temporaryDirectory.appending(path: "PaperFlow-Legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(savedVisit.state)) as! [String: Any]
        for key in ["demoRevision", "school", "major", "avatarSymbol", "visitedAt", "readAt", "dismissedReads", "likedCommentIDs", "commentLikedAt", "notices", "demoActivityIndex"] { legacy.removeValue(forKey: key) }
        legacy["nickname"] = "已有用户"; legacy["role"] = "设计学习者"
        legacy["comments"] = ["post:sample-0": [["id": "my-old-comment", "author": "已有用户", "text": "保留这条评论", "timestamp": visitTime.timeIntervalSince1970]]]
        var legacyPosts = legacy["posts"] as! [[String: Any]]
        for index in legacyPosts.indices { legacyPosts[index].removeValue(forKey: "imageNames") }
        legacyPosts.append(["id":"legacy-own", "author":"已有用户", "title":"原有发布", "body":"必须保留", "links":[], "images":[], "color":"FFFFFF", "symbol":"book", "timestamp":visitTime.timeIntervalSince1970, "isDraft":false, "isMine":true])
        legacy["posts"] = legacyPosts
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyFolder.appending(path: "user-state-v1.json"))
        let migrated = AppStore(directory: legacyFolder, catalogURL: catalog)
        check(migrated.storageError == nil && migrated.state.nickname == "已有用户" && migrated.state.role == "本科生", "旧数据库可无损升级并更新身份选项")
        check(migrated.post("legacy-own")?.body == "必须保留" && migrated.state.bookmarks == savedVisit.state.bookmarks && migrated.state.following == savedVisit.state.following, "升级保留本人帖子、收藏与跟踪")
        check(migrated.post("sample-0")!.imageCount == 3 && migrated.state.comments["post:sample-0"]!.contains { $0.id == "my-old-comment" }, "升级补入示例多图及评论且保留原评论")
        check(migrated.state.visitedAt["rag"] == nil && migrated.state.history.contains("rag"), "旧历史保留但不伪造访问时间")
        await migrated.flushStorage()
        let migratedAgain = AppStore(directory: legacyFolder, catalogURL: catalog)
        check(migratedAgain.state.comments["post:sample-0"]!.count == migrated.state.comments["post:sample-0"]!.count, "反复打开不会重复导入示例评论")
        migratedAgain.state.school = "湖南大学"; migratedAgain.state.major = "工业设计"; migratedAgain.state.avatarSymbol = "leaf.fill"
        await migratedAgain.flushStorage()
        let profile = AppStore(directory: legacyFolder, catalogURL: catalog)
        check(profile.state.school == "湖南大学" && profile.state.major == "工业设计" && profile.state.avatarSymbol == "leaf.fill", "学校、专业和头像正常保存")
        check(savedVisit.content(query: "RAG").contains { $0.id == "post:sample-0" }, "搜索能按关联资料缩写找到帖子")
        let sampleCount = savedVisit.published.count
        savedVisit.deletePost("sample-0")
        check(savedVisit.published.count == sampleCount && savedVisit.post("sample-0") != nil, "不能删除其他用户的示例帖子")
        let socialFolder = URL.temporaryDirectory.appending(path: "PaperFlow-Social-\(UUID().uuidString)")
        let social = AppStore(directory: socialFolder, catalogURL: catalog)
        let key = "post:sample-0"
        let root = social.rootComments(key).first!
        check(social.state.notices.isEmpty, "已有示例评论不会产生虚假的新消息")
        _ = social.receiveComment(key, author: "同学甲", text: "跟踪前的评论")!
        check(social.unreadNoticeCount == 0, "未跟踪的帖子不会发送普通评论提醒")
        social.toggleFollow(key)
        check(social.followedPosts.contains { $0.id == "sample-0" } && social.relatedPosts.contains { $0.id == "sample-0" }, "跟踪帖子后进入跟踪列表与动态")
        check(social.unreadNoticeCount == 0, "跟踪不会补发历史评论消息")
        let incoming = social.receiveComment(key, author: "同学乙", text: "跟踪后的新评论")!
        check(social.state.notices.count == 1 && social.unreadNoticeCount == 1, "新评论生成一条未读消息")
        let notice = social.state.notices.first!
        social.openNotice(notice)
        check(social.unreadNoticeCount == 0 && social.path.last == .discussion(key, incoming), "打开消息标记已读并定位对应评论")
        social.comment(key, text: "我来回复这条评论", parentID: root.id)
        let myReply = social.state.comments[key]!.last!
        check(myReply.parentID == root.id && social.isMyComment(myReply), "回复保存父评论与本人身份")
        check(social.state.notices.count == 1, "自己回复不会通知自己")
        check(social.replies(to: root, in: key).contains { $0.id == myReply.id }, "回复显示在正确讨论串")
        let secondReply = social.receiveComment(key, author: "同学丙", text: "回复你的想法", parentID: myReply.id)!
        check(social.rootID(for: social.comment(secondReply, in: key)!, in: key) == root.id, "回复的回复归入同一个讨论串")
        check(social.state.notices.count == 2 && social.state.notices.first!.title.contains("回复了你的评论"), "回复本人评论优先生成回复提醒且不重复通知")
        social.toggleCommentLike(root.id, in: key)
        check(social.state.likedCommentIDs.contains(root.id) && social.commentLikeCount(root) == (root.baseLikes ?? 0) + 1, "评论点赞与数量正确")
        check(social.commentActivities(replied: false).contains { $0.comment.id == root.id }, "我的点赞可回看原评论")
        check(social.commentActivities(replied: true).contains { $0.comment.id == root.id && $0.reply?.id == myReply.id }, "我的回复同时保留目标评论和回复内容")
        social.toggleCommentLike(root.id, in: key)
        check(!social.state.likedCommentIDs.contains(root.id) && social.commentActivities(replied: false).isEmpty, "取消点赞同步移除我的互动记录")
        social.toggleFollow(key)
        let noticeCount = social.state.notices.count
        social.receiveComment(key, author: "同学丁", text: "取消跟踪后的普通评论")
        check(social.state.notices.count == noticeCount, "取消跟踪后停止普通评论提醒")
        social.receiveComment(key, author: "同学戊", text: "直接回复你", parentID: myReply.id)
        check(social.state.notices.count == noticeCount + 1, "不跟踪帖子时仍能收到针对自己的回复")
        check(!social.simulateFollowedPostActivity(), "没有跟踪帖子时不生成演示更新")
        social.toggleFollow(key)
        let countBeforeDemo = social.state.comments[key]!.count
        check(social.simulateFollowedPostActivity() && social.state.comments[key]!.count == countBeforeDemo + 1, "演示更新添加评论并接入消息流程")
        check(social.simulateFollowedPostActivity() && social.state.comments[key]!.last!.parentID != nil, "演示更新也可产生回复")
        social.markAllMessagesRead()
        check(social.unreadNoticeCount == 0, "全部已读清除未读计数")
        let commentsBeforeInvalid = social.state.comments[key]!.count
        let invalidReply = social.receiveComment(key, author: "同学己", text: "无效回复", parentID: "missing-parent")
        let crossReply = social.receiveComment("post:sample-1", author: "同学己", text: "跨帖子回复", parentID: root.id)
        let invalidContent = social.receiveComment("post:missing", author: "同学己", text: "不存在的帖子")
        check(invalidReply == nil && crossReply == nil && invalidContent == nil && social.state.comments[key]!.count == commentsBeforeInvalid, "拒绝丢失父评论、跨帖回复和无效内容")
        social.comment(key, text: "   ", parentID: root.id)
        check(social.state.comments[key]!.count == commentsBeforeInvalid, "空白回复不会保存")
        social.toggleFollow("user:林间的笔记")
        check(social.route("user:林间的笔记") == .user("林间的笔记") && social.item(for: "user:林间的笔记") != nil, "作者跟踪记录可进入对应用户主页")
        social.toggleCommentLike(root.id, in: key)
        social.state.nickname = "改名后的读者"
        await social.flushStorage()
        let socialReopened = AppStore(directory: socialFolder, catalogURL: catalog)
        check(socialReopened.state.likedCommentIDs.contains(root.id) && socialReopened.commentActivities(replied: true).contains { $0.reply?.id == myReply.id }, "重启和改名后点赞与本人回复记录保留")
        check(socialReopened.state.notices.count == social.state.notices.count && socialReopened.unreadNoticeCount == 0, "消息及已读状态重启后保留")
        check(migrated.isMyComment(migrated.comment("my-old-comment", in: key)!), "升级时识别并保留旧版本人评论身份")
        var myPost = UserPost(); myPost.title = "本人的测试帖子"; myPost.body = "用于验证互动清理"
        socialReopened.savePost(myPost)
        let myPostKey = "post:\(myPost.id)"
        let ownNoticeCount = socialReopened.state.notices.count
        let commentOnMine = socialReopened.receiveComment(myPostKey, author: "同学庚", text: "给你的帖子留言")!
        check(socialReopened.state.notices.count == ownNoticeCount + 1, "自己的帖子收到新评论时不必先跟踪")
        socialReopened.toggleFollow(myPostKey)
        socialReopened.toggleCommentLike(commentOnMine, in: myPostKey)
        socialReopened.deletePost(myPost.id)
        check(socialReopened.state.comments[myPostKey] == nil && !socialReopened.state.likedCommentIDs.contains(commentOnMine) && !socialReopened.state.following.contains(myPostKey) && !socialReopened.state.notices.contains { $0.key == myPostKey }, "删除本人帖子会同步清理相关评论互动和提醒")
        let online = Paper(id: "arxiv-1706.03762", title: "Attention Is All You Need", hook: "original", subtitle: "online", author: "Ashish Vaswani", year: 2017, journalID: "arxiv", topics: [], sourceURL: "https://arxiv.org/abs/1706.03762v7", pdfURL: "https://arxiv.org/pdf/1706.03762", color: "FFFFFF", symbol: "doc", coverText: "arXiv", insights: [])
        let importCount = socialReopened.papers.count
        check(socialReopened.importPaper(online) == "attention" && socialReopened.papers.count == importCount, "在线版本与本机论文按原文身份去重")
        var newPaper = online; newPaper.id = "arxiv-9999.99999"; newPaper.sourceURL = "https://arxiv.org/abs/9999.99999"
        let newID = socialReopened.importPaper(newPaper)
        socialReopened.bookmark("paper:" + newID, folder: "待读")
        socialReopened.visit(newID)
        check(socialReopened.paper(newID) != nil && socialReopened.state.history.first == newID, "导入文献可参与收藏和阅读历史")
        socialReopened.state.avatarPhoto = Data([1, 2, 3])
        socialReopened.hideFromFeed("paper:attention")
        check(!socialReopened.recommendedContent(filter: ContentFilter()).contains { $0.id == "paper:attention" }, "减少首页推荐生效")
        check(socialReopened.content(query: "attention").contains { $0.id == "paper:attention" }, "减少推荐不影响主动搜索")
        await socialReopened.flushStorage()
        let newReopen = AppStore(directory: socialFolder, catalogURL: catalog)
        check(newReopen.state.avatarPhoto == Data([1, 2, 3]) && newReopen.paper(newID) != nil, "自定义头像与在线导入重启后保留")
        check(newReopen.state.aiConfiguration.model == "glm-5.2", "旧版数据升级后获得默认 AI 配置")
        // v1.4：同一论文跨语言缓存及跨源补全，仍使用原来的互动身份。
        let zh = GeneratedReading(title:"中文标题",clarification:"标题说明",body:"中文正文",sourceLabel:"摘要",sourceText:"source",model:"fixture",provider:"fixture.test",createdAt:1,language:"简体中文",coverText:"中文封面")
        var en = zh; en.title = "English title"; en.clarification = "A correction."; en.body = "English content."; en.language = "English"
        newReopen.saveReading(zh,for:"rag",language:"简体中文")
        newReopen.saveReading(en,for:"rag",language:"English")
        newReopen.state.targetLanguage = "English"
        check(newReopen.displayTitle(newReopen.paper("rag")!) == "English title", "切换语言读取对应缓存")
        check(newReopen.reading("rag",language:"简体中文")?.title == "中文标题", "英文生成不覆盖中文结果")
        check(newReopen.reading("clip") == nil && !newReopen.hasPreparedReading(newReopen.paper("clip")!), "没有英文解读时不把中文示例冒充英文")
        let oldID = newReopen.importPaper(online)
        var supplemented = online; supplemented.doi = "10.1234/test"; supplemented.retrievalSources = ["Crossref"]; supplemented.journalTitle = "New Journal"
        check(newReopen.importPaper(supplemented) == oldID && newReopen.paper(oldID)?.localPDF != nil, "跨源补全保留原 ID 与内置 PDF")
        check(newReopen.paper(oldID)?.retrievalSources?.contains("Crossref") == true, "补全元数据不丢失检索来源")
        let originalOrder = newReopen.recommendedContent(filter:ContentFilter()).map(\.id)
        newReopen.homeOrder = originalOrder
        newReopen.state.interests = ["计算机视觉"]
        check(newReopen.recommendedContent(filter:ContentFilter()).map(\.id) == originalOrder, "连续浏览保留已有卡片顺序")
        var sourceFilter = ContentFilter(); sourceFilter.kind = "文献"; sourceFilter.sources = ["Crossref"]
        check(newReopen.content(filter:sourceFilter).contains { $0.id == "paper:" + oldID }, "统一搜索按元数据来源筛选")
        await newReopen.flushStorage()
        let v14 = AppStore(directory:socialFolder,catalogURL:catalog)
        check(v14.reading("rag",language:"English")?.title == "English title" && v14.reading("rag",language:"简体中文")?.title == "中文标题", "多语言缓存重启后分别保留")
        var wronglyTagged = zh; wronglyTagged.language = "English"
        v14.state.generatedReadings["clip|English"] = wronglyTagged
        check(v14.reading("clip",language:"English") == nil, "旧缓存即使标注英文也不能显示中文正文")
        var balance = ImageCoverRecord(id:"recover-balance",contentID:"paper:rag",requestID:"unbilled-test",mode:"demo",status:"failed",message:"余额不足")
        balance.providerCode = "1113"
        v14.state.imageGenerations[balance.id] = balance
        v14.resolveBalanceFailure(balance.id)
        check(v14.state.imageGenerations[balance.id] == nil,"原图恢复后清除当前余额失败标记，不会一直重复提示")
        check(v14.state.imageCalls[balance.requestID] == balance,"恢复原图保留原来的失败调用历史")
        var uncertain = balance;uncertain.id = "recover-unknown";uncertain.requestID = "unknown-test";uncertain.status = "unknown"
        v14.state.imageGenerations[uncertain.id] = uncertain
        v14.resolveBalanceFailure(uncertain.id)
        check(v14.state.imageGenerations[uncertain.id] == uncertain,"恢复功能不清除结果不明的请求")
        await v14.flushStorage()
        let recoveredStore = AppStore(directory:socialFolder,catalogURL:catalog)
        check(recoveredStore.state.imageGenerations[balance.id] == nil && recoveredStore.state.imageCalls[balance.requestID] == balance && recoveredStore.state.imageGenerations[uncertain.id] == uncertain,"恢复结果和未处理请求重开后都正确保留")
        print("ALL STATE CHECKS PASSED")
    }
}
