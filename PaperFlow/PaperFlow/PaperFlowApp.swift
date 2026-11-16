// 程序入口：创建一份 AppStore，并通过 environment 分享给所有页面。
//
//  PaperFlowApp.swift
//  PaperFlow
//
//  Created by Richard Yang on 2026/10/21.
//

import SwiftUI

@main
struct PaperFlowApp: App {
    @State private var store: AppStore
    init() {
        FlowTypography.configure()
        #if DEBUG
        // 界面检查使用独立的临时数据，正常启动仍使用用户自己的数据。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--review-screen"), args.indices.contains(i + 1) {
            let review = AppStore(directory: URL.temporaryDirectory.appending(path: "PaperFlow-VisualReview"))
            review.state.completedOnboarding = true
            switch args[i + 1] {
            case "profile": review.tab = 4
            case "discussion": review.path = [.discussion("post:sample-0", nil)]
            case "messages":
                review.tab = 3
                if !review.state.following.contains("post:sample-0") { review.toggleFollow("post:sample-0") }
                if review.state.notices.isEmpty { review.simulateFollowedPostActivity() }
            case "activity":
                if let root = review.rootComments("post:sample-0").first {
                    if !review.state.likedCommentIDs.contains(root.id) { review.toggleCommentLike(root.id, in: "post:sample-0") }
                    if review.commentActivities(replied: true).isEmpty { review.comment("post:sample-0", text: "我也会先看实验条件，再回头理解方法。", parentID: root.id) }
                }
                review.tab = 4; review.profileSection = "评论"
            case "onboarding": review.state.completedOnboarding = false
            case "ai-settings": review.path = [.aiSettings]
            case "topics": review.path = [.topics]
            case "usage": review.path = [.usage]
            case "edit-profile": review.path = [.profile]
            case "online": review.path = [.search("人机交互")]
            case "preferences": review.path = [.preferences]
            case "libraries": review.path = [.libraries]
            case "post": review.path = [.post("sample-0")]
            case "publish": review.showingComposer = true
            case "search": review.path = [.search("")]
            default: break
            }
            _store = State(initialValue: review)
            return
        }
        #endif
        let app = AppStore(); app.recoverDemoSession()
        _store = State(initialValue: app)
    }
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store)
        }
    }
}
