import Foundation
import SQLite3
import CryptoKit

/// 单写入者：后台按记录增量更新 SQLite，照片以散列文件引用保存。
actor StateDatabase {
    let directory: URL
    private var previous: LocalState?
    private var saved: [String:Data] = [:]
    init(directory:URL) { self.directory = directory }

    nonisolated static func open(_ directory:URL) throws -> OpaquePointer {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var db:OpaquePointer?
        guard sqlite3_open(directory.appending(path:"state-v2.sqlite").path,&db) == SQLITE_OK,let db else { throw CocoaError(.fileReadCorruptFile) }
        sqlite3_busy_timeout(db,3000)
        do { try execute(db,"PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS records (key TEXT PRIMARY KEY, value BLOB NOT NULL);") } catch { sqlite3_close(db);throw error }
        return db
    }
    nonisolated static func execute(_ db:OpaquePointer,_ sql:String) throws {
        guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw NSError(domain:"PaperFlow.SQLite",code:Int(sqlite3_errcode(db)),userInfo:[NSLocalizedDescriptionKey:String(cString:sqlite3_errmsg(db))]) }
    }
    nonisolated static func decoder(_ directory:URL) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if value.hasPrefix("blob:") {
                let name = String(value.dropFirst(5))
                guard name.count == 64,name.allSatisfy({$0.isHexDigit}) else { throw CocoaError(.fileReadCorruptFile) }
                return try Data(contentsOf:directory.appending(path:"Media/"+name))
            }
            guard let data = Data(base64Encoded:value) else { throw CocoaError(.fileReadCorruptFile) };return data
        };return decoder
    }
    /// 仅启动时读取一次；后续交互不再读取整个数据库。
    nonisolated static func load(_ directory:URL) throws -> LocalState? {
        guard FileManager.default.fileExists(atPath:directory.appending(path:"state-v2.sqlite").path) else { return nil }
        let db = try open(directory);defer { sqlite3_close(db) }
        var statement:OpaquePointer?;defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db,"SELECT key,value FROM records",-1,&statement,nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        var rows:[String:Any] = [:]
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let key = String(cString:sqlite3_column_text(statement,0))
            let data = Data(bytes:sqlite3_column_blob(statement,1),count:Int(sqlite3_column_bytes(statement,1)))
            rows[key] = try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
        guard var root = rows["metadata"] as? [String:Any] else { return nil }
        let order = root.removeValue(forKey:"_order") as? [String:[String]] ?? [:]
        for group in ["importedPapers","posts"] {
            let ids = order[group] ?? [],values = ids.compactMap { rows[group+":"+$0] }
            guard ids.count == values.count else { throw CocoaError(.fileReadCorruptFile) };root[group] = values
        }
        for group in ["generatedReadings","comments","covers","translations","imageGenerations","imageCalls"] {
            root[group] = Dictionary(uniqueKeysWithValues:rows.compactMap { key,value in key.hasPrefix(group+":") ? (String(key.dropFirst(group.count+1)),value) : nil })
        }
        root["avatarPhoto"] = rows["avatarPhoto"]
        return try decoder(directory).decode(LocalState.self,from:JSONSerialization.data(withJSONObject:root))
    }
    func save(_ state:LocalState) throws {
        let mediaChanged = previous?.covers != state.covers || previous?.posts != state.posts || previous?.comments != state.comments || previous?.avatarPhoto != state.avatarPhoto
        let db = try Self.open(directory);defer { sqlite3_close(db) }
        let encoder = JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        let media = directory.appending(path:"Media")
        try FileManager.default.createDirectory(at:media,withIntermediateDirectories:true)
        encoder.dataEncodingStrategy = .custom { data,encoder in
            let name = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
            let file = media.appending(path:name)
            if !FileManager.default.fileExists(atPath:file.path) { try data.write(to:file,options:.atomic) }
            var container = encoder.singleValueContainer();try container.encode("blob:"+name)
        }
        var rows = saved
        var active:Set<String> = ["metadata"]
        func put<T:Encodable>(_ key:String,_ value:T,_ unchanged:Bool) throws {
            active.insert(key)
            if !unchanged || rows[key] == nil { rows[key] = try encoder.encode(value) }
        }
        let oldPapers = Dictionary((previous?.importedPapers ?? []).map { ($0.id,$0) },uniquingKeysWith:{$1})
        for paper in state.importedPapers { try put("importedPapers:"+paper.id,paper,oldPapers[paper.id] == paper) }
        let oldPosts = Dictionary((previous?.posts ?? []).map { ($0.id,$0) },uniquingKeysWith:{$1})
        for post in state.posts { try put("posts:"+post.id,post,oldPosts[post.id] == post) }
        for (key,value) in state.generatedReadings { try put("generatedReadings:"+key,value,previous?.generatedReadings[key] == value) }
        for (key,value) in state.comments { try put("comments:"+key,value,previous?.comments[key] == value) }
        for (key,value) in state.covers { try put("covers:"+key,value,previous?.covers[key] == value) }
        for (key,value) in state.imageCalls { try put("imageCalls:"+key,value,previous?.imageCalls[key] == value) }
        for (key,value) in state.imageGenerations { try put("imageGenerations:"+key,value,previous?.imageGenerations[key] == value) }
        for (key,value) in state.translations { try put("translations:"+key,value,previous?.translations[key] == value) }
        if let avatar = state.avatarPhoto { try put("avatarPhoto",avatar,previous?.avatarPhoto == avatar) }
        var metadata = state
        metadata.importedPapers = [];metadata.generatedReadings = [:];metadata.posts = [];metadata.comments = [:];metadata.covers = [:];metadata.translations = [:];metadata.avatarPhoto = nil;metadata.imageGenerations = [:];metadata.imageCalls = [:]
        var root = try JSONSerialization.jsonObject(with:encoder.encode(metadata)) as! [String:Any]
        root["_order"] = ["importedPapers":state.importedPapers.map(\.id),"posts":state.posts.map(\.id)]
        rows["metadata"] = try JSONSerialization.data(withJSONObject:root,options:.sortedKeys)
        rows = rows.filter { active.contains($0.key) }
        try Self.execute(db,"BEGIN IMMEDIATE")
        do {
            // 首次保存时同样清理旧行，保证重置/删除不会在重启后复活。
            var oldKeys:Set<String> = []
            var query:OpaquePointer?;sqlite3_prepare_v2(db,"SELECT key FROM records",-1,&query,nil)
            while sqlite3_step(query) == SQLITE_ROW { oldKeys.insert(String(cString:sqlite3_column_text(query,0))) };sqlite3_finalize(query)
            for key in oldKeys.subtracting(active) { try write(db,key:key,value:nil) }
            for (key,value) in rows where saved[key] != value { try write(db,key:key,value:value) }
            try Self.execute(db,"COMMIT");saved = rows;previous = state
            if mediaChanged {
                let regex = try NSRegularExpression(pattern:"blob:([a-f0-9]{64})")
                var referenced:Set<String> = []
                for bytes in rows.values {
                    let text = String(decoding:bytes,as:UTF8.self)
                    for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)) { if let range = Range(match.range(at:1),in:text) { referenced.insert(String(text[range])) } }
                }
                for file in (try? FileManager.default.contentsOfDirectory(at:media,includingPropertiesForKeys:nil)) ?? [] where !referenced.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at:file) }
            }
        } catch { try? Self.execute(db,"ROLLBACK");throw error }
    }
    private func write(_ db:OpaquePointer,key:String,value:Data?) throws {
        var statement:OpaquePointer?;defer { sqlite3_finalize(statement) }
        let sql = value == nil ? "DELETE FROM records WHERE key=?" : "INSERT OR REPLACE INTO records(key,value) VALUES(?,?)"
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        let transient = unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        sqlite3_bind_text(statement,1,key,-1,transient)
        if let value { _ = value.withUnsafeBytes { sqlite3_bind_blob(statement,2,$0.baseAddress,Int32(value.count),transient) } }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
    }
}
