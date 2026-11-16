import SwiftUI

/// AI 文献和用户笔记共享页面骨架与互动状态；只有媒体、正文和关联资料不同。
struct ContentDetailPage<Media:View,Identity:View,Article:View,Related:View>: View {
    @Environment(AppStore.self) private var store
    let key: String
    let title: String
    let media: Media
    let identity: Identity
    let article: Article
    let related: Related
    @State private var saving = false
    @State private var comments = false
    @State private var replyID: String?
    init(key:String,title:String,@ViewBuilder media:()->Media,@ViewBuilder identity:()->Identity,@ViewBuilder article:()->Article,@ViewBuilder related:()->Related) {
        self.key = key; self.title = title; self.media = media(); self.identity = identity(); self.article = article(); self.related = related()
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                media
                identity
                Text(title).flowFont(.title2,weight:.bold).textSelection(.enabled)
                article
                related
                Divider()
                HStack { Text("讨论").flowFont(.headline); Spacer(); Button("写评论") { openComments(nil) } }
                if store.rootComments(key).isEmpty { Text("说说你的想法。").flowFont(.body).foregroundStyle(.secondary) }
                ForEach(store.rootComments(key).prefix(3)) { comment in
                    CommentRow(key:key,comment:comment) { openComments(comment.id) }
                    let replies = store.replies(to:comment,in:key)
                    if !replies.isEmpty { Button("查看 \(replies.count) 条回复") { openComments(nil) }.flowFont(.body) }
                }
                if store.state.comments[key,default:[]].count > 3 { Button("查看全部评论") { openComments(nil) } }
            }.padding(18)
        }.navigationTitle("内容").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {
                HStack(spacing:12) {
                    LikeButton(key:key)
                    Button { saving = true } label: { Image(systemName:store.state.bookmarks[key] == nil ? "bookmark" : "bookmark.fill").flowFont(.title3).frame(width:44,height:44) }.accessibilityLabel("收藏当前内容")
                    Spacer(minLength:0)
                    FollowButton(key:key)
                    Button { openComments(nil) } label: { Label("评论",systemImage:"bubble").flowFont(.body).frame(minHeight:44) }
                }.padding(.horizontal,16).padding(.vertical,6).background(.regularMaterial)
            }
            .sheet(isPresented:$saving) { BookmarkPicker(key:key) }
            .sheet(isPresented:$comments) { CommentsView(key:key,focusID:replyID,initialReplyID:replyID) }
    }
    private func openComments(_ id:String?) { replyID = id; comments = true }
}
