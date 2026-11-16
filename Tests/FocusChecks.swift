import Foundation
import PDFKit
import SQLite3

@main struct FocusChecks {
    @MainActor static func main() async throws {
        let project = URL(fileURLWithPath:CommandLine.arguments[1]),root = URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        func check(_ condition:Bool,_ label:String) { precondition(condition,label);print("PASS: "+label) }
        let catalogURL = project.appending(path:"Tests/Fixtures/LegacyCatalog.json")
        let catalog = try JSONDecoder().decode(Catalog.self,from:Data(contentsOf:catalogURL))
        var legacy = LocalState();legacy.nickname = "迁移检查";legacy.bookmarks = ["paper:attention":"待读"];legacy.notes = ["attention":"保留我的笔记"]
        legacy.avatarPhoto = Data([1,2,3,4]);legacy.covers["attention"] = CoverAsset(image:Data([5,6,7]),page:3,caption:"本人封面",manual:true)
        let old = root.appending(path:"user-state-v1.json"),original = try JSONEncoder().encode(legacy)
        try original.write(to:old)
        let store = AppStore(directory:root,catalogURL:catalogURL)
        await store.flushStorage()
        check(store.storageError == nil && (try? Data(contentsOf:old)) == original,"迁移不覆盖旧 JSON")
        check((try? Data(contentsOf:root.appending(path:"user-state-v1.pre-sqlite.json"))) == original,"迁移前保留完整备份")
        let reopened = AppStore(directory:root,catalogURL:catalogURL)
        check(reopened.state.nickname == legacy.nickname && reopened.state.bookmarks == legacy.bookmarks && reopened.state.notes == legacy.notes,"SQLite 重开保留资料、收藏和笔记")
        check(reopened.state.avatarPhoto == legacy.avatarPhoto && reopened.state.covers["attention"]?.image == legacy.covers["attention"]?.image,"图片文件引用可完整还原")
        var db:OpaquePointer?;sqlite3_open(root.appending(path:"state-v2.sqlite").path,&db)
        var statement:OpaquePointer?;sqlite3_prepare_v2(db,"SELECT value FROM records WHERE key='covers:attention'",-1,&statement,nil);sqlite3_step(statement)
        let record = Data(bytes:sqlite3_column_blob(statement,0),count:Int(sqlite3_column_bytes(statement,0)))
        sqlite3_finalize(statement)
        sqlite3_exec(db,"CREATE TABLE audit(key TEXT); CREATE TRIGGER writes AFTER INSERT ON records BEGIN INSERT INTO audit VALUES(new.key); END;",nil,nil,nil)
        sqlite3_close(db)
        check(String(decoding:record,as:UTF8.self).contains("blob:"),"SQLite 图片只存文件引用")
        store.toggleLike("paper:attention");store.toggleLike("paper:resnet");await store.flushStorage()
        let saved = try StateDatabase.load(root)!
        check(saved.likes.contains("paper:attention") && saved.likes.contains("paper:resnet"),"连续小操作合并保存，不丢最后状态")
        sqlite3_open(root.appending(path:"state-v2.sqlite").path,&db)
        sqlite3_prepare_v2(db,"SELECT count(*) FROM audit WHERE key != 'metadata'",-1,&statement,nil);sqlite3_step(statement)
        check(sqlite3_column_int(statement,0) == 0,"点赞只更新元数据，不重写图片与论文记录")
        sqlite3_finalize(statement);sqlite3_close(db)
        var note = UserPost();note.title = "封面迁移";note.coverImage = Data([4,3,2,1]);note.coverSource = "photo";note.coverIndex = 0
        store.savePost(note)
        let imageRecord = ImageCoverRecord(id:"cache-test",contentID:"paper:attention",requestID:"local-test",mode:"demo",status:"download",remoteURL:"https://image.test/cover.jpg",counted:true)
        store.state.imageGenerations[imageRecord.id] = imageRecord;store.state.imageCalls[imageRecord.requestID] = imageRecord
        await store.flushStorage()
        let withImages = try StateDatabase.load(root)!
        check(withImages.posts.first(where:{$0.id == note.id})?.coverImage == note.coverImage,"笔记封面经 SQLite 图片引用重开后保留")
        check(withImages.imageGenerations[imageRecord.id] == imageRecord && withImages.imageCalls[imageRecord.requestID] == imageRecord,"生图结果 URL 与状态独立入库，下载失败不丢记录")
        store.resetDemo();await store.flushStorage()
        check(store.state.imageGenerations[imageRecord.id] == imageRecord,"普通重置保留已付费生图记录与缓存关联")
        let query = LiteratureQuery("可解释人工智能")
        check(query.english.contains("可解释") && query.english.contains("artificial"),"中文未匹配词不会丢失")
        check(LiteratureQuery("建筑设计").english.contains("architecture"),"建筑设计保留领域信息")
        var history = LocalState();let anchor = catalog.papers.first(where:{$0.id == "attention"})!
        var related = anchor;related.id = "related";var unrelated = anchor;unrelated.id = "unrelated";unrelated.title = "Ecology of coral reefs";unrelated.abstractText = "Marine biodiversity";unrelated.topics = [];unrelated.journalID = "other"
        history.interests = [];history.bookmarks["paper:"+anchor.id] = "待读"
        let ranked = RecommendationEngine.rank([unrelated,related],state:history,refresh:0,history:[anchor])
        check(ranked.first?.id == "related","历史论文不在新批次中，收藏仍可影响推荐")
        check(SearchRanking.rank([unrelated,anchor],query:"Attention Is All You Need").first?.id == anchor.id,"原标题搜索按相关性优先")
        let html = #"<figure id='fig1'><img src='/assets/core.png'><figcaption>Figure 1: Main architecture</figcaption></figure><figure><img src='/logo.png'></figure>"#
        let figures = try CoverPipeline.htmlCandidates(html,base:URL(string:"https://paper.test/html/main")!)
        check(figures.count == 1 && figures[0].0 == "https://paper.test/assets/core.png","网页原图关联图注与真实相对地址")
        // 对同一篇 Attention 额外验证实际网页请求；没有 HTML 时必须能回退原文 PDF。
        let online = CoverPipeline(directory:root.appending(path:"OnlineFigures"))
        let onlineCover = await online.prepare(paper:anchor,pdf:project.appending(path:"Tests/Fixtures/Papers/attention.pdf"))
        check(onlineCover.selected != nil,"真实来源请求后仍有原图或 PDF 回退封面")
        print("ONLINE: " + onlineCover.method + " · " + (onlineCover.candidates.first?.sourceURL ?? ""))
        let extractor = CoverPipeline(directory:root.appending(path:"Figures"),allowNetwork:false)
        var papers = catalog.papers
        for (id,title,code) in [("bert","BERT: Pre-training of Deep Bidirectional Transformers","1810.04805"),("gan","Generative Adversarial Nets","1406.2661")] {
            var paper = anchor;paper.id = id;paper.title = title;paper.sourceURL = "https://arxiv.org/abs/"+code;paper.pdfURL = "https://arxiv.org/pdf/"+code
            let downloads = URL.temporaryDirectory.appending(path:"paperflow-1.7-public-pdfs")
            try FileManager.default.createDirectory(at:downloads,withIntermediateDirectories:true)
            let file = root.appending(path:id+".pdf"),cached = downloads.appending(path:id+".pdf")
            if FileManager.default.fileExists(atPath:cached.path),(PDFDocument(url:cached)?.pageCount ?? 0) > 0 { try FileManager.default.copyItem(at:cached,to:file);papers.append(paper);continue }
            var request = URLRequest(url:URL(string:paper.pdfURL!)!);request.timeoutInterval = 40
            let (temporary,response) = try await URLSession.shared.download(for:request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,(PDFDocument(url:temporary)?.pageCount ?? 0) > 0 else { throw URLError(.cannotDecodeContentData) }
            try FileManager.default.moveItem(at:temporary,to:file);try? FileManager.default.copyItem(at:file,to:cached);papers.append(paper)
        }
        check(papers.count == 10,"只使用十篇真实论文")
        var manifest:[[String:Any]] = []
        for paper in papers {
            let fixture = project.appending(path:"Tests/Fixtures/Papers/"+paper.id+".pdf")
            let pdf = FileManager.default.fileExists(atPath:fixture.path) ? fixture : root.appending(path:paper.id+".pdf")
            let record = await extractor.prepare(paper:paper,pdf:pdf)
            let folder = extractor.folder(paper.id)
            check(record.candidates.count <= 3 && (record.failed ? record.selected == nil : record.selected != nil),"\(paper.title)：原图候选或等待生图，不使用首页截图")
            check(record.candidates.allSatisfy { FileManager.default.fileExists(atPath:folder.appending(path:$0.id+".jpg").path) },"\(paper.id)：候选可切换且文件存在")
            let cached = await extractor.prepare(paper:paper,pdf:pdf)
            check(cached.checkedAt == record.checkedAt,"\(paper.id)：重复打开复用缓存")
            manifest.append(["id":paper.id,"title":paper.title,"method":record.method,"file":folder.appending(path:(record.selected ?? "no-original")+".jpg").path,"candidates":record.candidates.count])
        }
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:root.appending(path:"ten-papers.json"))
        print("FINISHED: 10 real papers; no simulator or paid model; artifacts: "+root.path)
    }
}
