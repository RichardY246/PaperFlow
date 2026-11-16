// 评论界面：回复关系与点赞状态由 AppStore 处理，页面只调用对应操作。
import SwiftUI
import PhotosUI

struct CommentRow: View {
    @Environment(AppStore.self) var store
    var key: String
    var comment: Comment
    var onReply: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: comment.author, size: 32, symbol: store.isMyComment(comment) ? store.state.avatarSymbol : "person.fill", photo: store.isMyComment(comment) ? store.state.avatarPhoto : nil)
            VStack(alignment: .leading, spacing: 7) {
                Text(store.isMyComment(comment) ? store.state.nickname : comment.author).flowFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
                if let parentID = comment.parentID, let parent = store.comment(parentID, in: key) {
                    Text("回复 \(store.isMyComment(parent) ? store.state.nickname : parent.author)").flowFont(.subheadline).foregroundStyle(Color.flow)
                }
                if !comment.text.isEmpty { Text(comment.text).flowFont(.body).lineSpacing(4).textSelection(.enabled) }
                if let images = comment.images { ForEach(Array(images.enumerated()),id:\.offset) { _,data in DiscussionImage(data:data) } }
                if let id = comment.paperID {
                    Button { store.go(.readerPage(id,comment.page ?? 1)) } label: { Text((store.paper(id)?.title ?? "原文") + " · 第 \(comment.page ?? 1) 页").flowFont(.subheadline).lineLimit(2) }
                }
                HStack(spacing: 12) {
                    Text(Date(timeIntervalSince1970: comment.timestamp).formatted(date: .abbreviated, time: .shortened)).flowFont(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("回复") {
                        if let onReply { onReply() } else { store.go(.reply(key, comment.id)) }
                    }.flowFont(.subheadline).frame(minHeight: 44).buttonStyle(.borderless).accessibilityIdentifier("reply-\(comment.id)")
                    Button { store.toggleCommentLike(comment.id, in: key) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.state.likedCommentIDs.contains(comment.id) ? "heart.fill" : "heart").font(.system(size: 17))
                            Text(String(store.commentLikeCount(comment))).flowFont(.subheadline)
                        }.foregroundStyle(store.state.likedCommentIDs.contains(comment.id) ? Color.pink : Color.secondary).frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.borderless).accessibilityLabel(store.state.likedCommentIDs.contains(comment.id) ? "取消评论点赞" : "点赞评论").accessibilityIdentifier("comment-like-\(comment.id)")
                }
            }
        }.padding(.vertical, 5)
    }
}

struct CommentThread: View {
    @Environment(AppStore.self) var store
    var key: String
    var root: Comment
    @Binding var replyingTo: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentRow(key: key, comment: root) { replyingTo = root.id }.id(root.id)
            ForEach(store.replies(to: root, in: key)) { reply in
                CommentRow(key: key, comment: reply) { replyingTo = reply.id }.padding(.leading, 22).id(reply.id)
            }
        }
    }
}

struct DiscussionContent: View {
    @Environment(AppStore.self) var store
    var key: String
    var focusID: String?
    var initialReplyID: String?
    var showContextLink = true
    @State private var text = ""
    @State private var replyingTo: String?
    @State private var newestID: String?
    @State private var initialized = false
    @State private var attachment:Data?
    @State private var attachmentPaper:String?
    @State private var attachmentPage:Int?
    @State private var photo:PhotosPickerItem?
    @State private var excerptPicking = false
    @State private var imageError = ""
    @FocusState private var editing: Bool
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !store.hasContent(key) { EmptyHint(title: "内容已移除", message: "这条内容暂时无法查看。") }
                    else {
                        if showContextLink {
                            Button { if let route = store.route(key) { store.go(route) } } label: { Label(store.label(key), systemImage: "arrow.up.right").flowFont(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                        }
                        if store.rootComments(key).isEmpty { Text("还没有评论，写下你的想法吧。").flowFont(.body).foregroundStyle(.secondary) }
                        ForEach(store.rootComments(key)) { root in
                            CommentThread(key: key, root: root, replyingTo: $replyingTo)
                            Divider()
                        }
                    }
                }.padding(18)
            }.scrollDismissesKeyboard(.interactively)
                .onAppear {
                    guard !initialized else { return }
                    initialized = true
                    if let initialReplyID, store.comment(initialReplyID, in: key) != nil { replyingTo = initialReplyID }
                    if let focusID { DispatchQueue.main.async { proxy.scrollTo(focusID, anchor: .center) } }
                    if let asset = store.pendingExcerpt { attachment = asset.image; attachmentPaper = store.excerptPaperID; attachmentPage = asset.page; store.pendingExcerpt = nil; store.excerptPaperID = nil }
                }
                .onChange(of: newestID) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                .onChange(of: replyingTo) { _, id in if id != nil { editing = true } }
        }.navigationTitle("讨论").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if store.hasContent(key) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let attachment {
                            HStack {
                                DiscussionImage(data:attachment)
                                Button("移除图片") { self.attachment = nil; attachmentPaper = nil; attachmentPage = nil }
                            }.frame(maxHeight:100)
                        }
                        if !imageError.isEmpty { Text(imageError).flowFont(.subheadline).foregroundStyle(.secondary) }
                        if let id = replyingTo, let target = store.comment(id, in: key) {
                            HStack(spacing: 8) {
                                Text("回复 \(store.isMyComment(target) ? store.state.nickname : target.author)：\(target.text)").flowFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                                Button { replyingTo = nil } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 36) }.accessibilityLabel("取消回复")
                            }
                        }
                        HStack(spacing: 12) {
                            Menu {
                                Button("从论文截取插图") { excerptPicking = true }
                            } label: { Image(systemName:"doc.richtext").frame(width:36,height:44) }.accessibilityLabel("截取论文图片")
                            PhotosPicker(selection:$photo,matching:.images) { Image(systemName:"photo").frame(width:36,height:44) }.accessibilityLabel("选择评论图片")
                            TextField(replyingTo == nil ? "写下你的想法…" : "写一条回复…", text: $text, axis: .vertical).flowFont(.body).lineLimit(1...4).textFieldStyle(.roundedBorder).focused($editing).accessibilityIdentifier("discussion-input")
                            Button("发送") {
                                newestID = store.receiveComment(key, author: store.state.nickname, text: text, parentID: replyingTo, isMine: true,images:attachment.map { [$0] } ?? [],paperID:attachmentPaper,page:attachmentPage)
                                if newestID != nil { text = ""; replyingTo = nil; editing = false; attachment = nil; attachmentPaper = nil; attachmentPage = nil }
                            }.flowFont(.body, weight: .semibold).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachment == nil).accessibilityIdentifier("discussion-send")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8).background(.regularMaterial)
                }
            }
            .sheet(isPresented:$excerptPicking) { PaperExcerptPicker { id,asset in attachment = asset.image; attachmentPaper = id; attachmentPage = asset.page; store.recordEvent("comment_excerpt") } }
            .onChange(of:photo) { _,value in
                Task {
                    do {
                        if let data = try await value?.loadTransferable(type:Data.self), let image = UIImage(data:data) {
                            let ratio = min(1,1200 / max(image.size.width,image.size.height))
                            let size = CGSize(width:image.size.width * ratio,height:image.size.height * ratio)
                            attachment = UIGraphicsImageRenderer(size:size).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }.jpegData(compressionQuality:0.8)
                            attachmentPaper = nil; attachmentPage = nil; imageError = ""
                        }
                    } catch { imageError = "图片读取失败，请重试。" }
                }
            }
    }
}

struct DiscussionImage: View {
    var data:Data
    @State private var opened = false
    var body: some View {
        if let image = UIImage(data:data) {
            Button { opened = true } label: { Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:140).clipShape(RoundedRectangle(cornerRadius:10)) }.buttonStyle(.plain).accessibilityLabel("查看讨论图片")
                .fullScreenCover(isPresented:$opened) { NavigationStack { ScrollView([.horizontal,.vertical]) { Image(uiImage:image).resizable().scaledToFit().frame(width:UIScreen.main.bounds.width) }.navigationTitle("图片").toolbar { Button("完成") { opened = false } } } }
        }
    }
}

struct CommentsView: View {
    @Environment(\.dismiss) var dismiss
    var key: String
    var focusID: String?
    var initialReplyID: String?
    var body: some View {
        NavigationStack {
            DiscussionContent(key: key, focusID: focusID, initialReplyID: initialReplyID, showContextLink: false)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct CommentActivityContent: View {
    @Environment(AppStore.self) var store
    @State private var kind = "点赞过的"
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("评论互动类型", selection: $kind) { Text("点赞过的").tag("点赞过的"); Text("回复过的").tag("回复过的") }.pickerStyle(.segmented)
            let activities = store.commentActivities(replied: kind == "回复过的")
            if activities.isEmpty { EmptyHint(title: kind == "回复过的" ? "还没有回复过评论" : "还没有点赞的评论", message: "在帖子讨论中点赞或回复后，会记录在这里。", symbol: "bubble.left.and.bubble.right") }
            ForEach(activities) { activity in
                VStack(alignment: .leading, spacing: 8) {
                    Button { store.go(.discussion(activity.key, activity.reply?.id ?? activity.comment.id)) } label: {
                        Label(store.label(activity.key), systemImage: "arrow.up.right").flowFont(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain).foregroundStyle(Color.flow)
                    CommentRow(key: activity.key, comment: activity.comment)
                    if let reply = activity.reply {
                        Text("我的回复：\(reply.text)").flowFont(.body).lineSpacing(4).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.flow.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

