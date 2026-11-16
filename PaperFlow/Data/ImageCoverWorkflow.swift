import Foundation

extension AppStore {
    var balanceRecoveryPapers:[Paper] {
        ImageRecoverySelection.papers(records:state.imageGenerations,papers:papers,manual:Set(state.covers.keys))
    }
    /// 用户点击后只重试这一次列出的余额失败项；不清空缓存或未知请求，也不取消已付费的当前任务。
    func startBalanceRecovery() {
        guard !imageRecoveryRunning else { return }
        refreshQuota()
        guard imageKeyAvailable else { imageRecoveryStatus = ImageCoverError.missingKey.localizedDescription;return }
        let candidates = balanceRecoveryPapers
        let selected = Array(candidates.prefix(isDemo ? imageBudget.remaining : candidates.count))
        guard !selected.isEmpty else { imageRecoveryStatus = candidates.isEmpty ? "没有需要重试的余额失败封面。" : ImageCoverError.quota.localizedDescription;return }
        let demo = isDemo,profile = imageProfile
        imageRecoveryRunning = true;imageRecoveryStopRequested = false
        imageRecoveryStatus = "准备恢复 \(selected.count) 张封面…"
        imageRecoveryTask = Task { @MainActor [self] in
            var recovered = 0,attempted = 0,reason = ""
            defer {
                imageRecoveryStatus = "已恢复 \(recovered) / \(selected.count) 张封面" + (reason.isEmpty ? "。" : "；"+reason)
                imageRecoveryRunning = false;imageRecoveryTask = nil
            }
            for paper in selected {
                guard self.paper(paper.id) != nil else { continue }
                if imageRecoveryStopRequested { reason = "已停止后续重试。";break }
                guard demo == isDemo,profile == imageProfile else { reason = "API 配置已变更，后续重试暂停。";break }
                let input = paperImageInput(paper)
                guard state.imageGenerations[input.cacheID]?.isUnbilledBalanceFailure == true else { continue }
                imageRecoveryStatus = "正在恢复第 \(attempted+1) / \(selected.count) 张；生图可能需要 1–3 分钟。"
                // 先查原图，余额恢复后也不把已有论文图表替换成付费生图。
                await PaperArtwork.prepare(paper:paper,url:PaperFileService.localURL(paper))
                if imageRecoveryStopRequested { reason = "已停止后续重试。";break }
                guard demo == isDemo,profile == imageProfile else { reason = "API 配置已变更，后续重试暂停。";break }
                if state.covers[paper.id] != nil || PaperArtwork.hasOriginal(paper.id) {
                    resolveBalanceFailure(input.cacheID)
                    recovered += 1;attempted += 1;recordEvent("cover_retry");continue
                }
                do {
                    _ = try await generateImage(input,retry:true)
                    recovered += 1;attempted += 1;recordEvent("cover_retry")
                } catch {
                    reason = error.localizedDescription + " 后续重试已暂停。";break
                }
            }
        }
    }
    /// 只解析智谱配置；永远不把当前其他厂商的 Key 当作智谱 Key。
    var imageProfile:AIConfiguration? {
        guard !isDemo else { return nil }
        if let id = state.imageConfiguration.profileID {
            return state.apiProfiles.first { $0.id == id && ImageConfiguration.accepts($0) }
        }
        if ImageConfiguration.accepts(state.aiConfiguration) { return state.aiConfiguration }
        return state.apiProfiles.first { ImageConfiguration.accepts($0) }
    }
    var imageKeyAvailable:Bool {
        if isDemo { return !((try? DemoAccess.key()) ?? "").isEmpty }
        guard let profile = imageProfile else { return false }
        return !((try? APIKeyStore.read(profile)) ?? "").isEmpty
    }
    func paperImageInput(_ paper:Paper) -> ImageCoverInput {
        ImageCoverInput(contentID:"paper:"+paper.id,title:paper.title,summary:(paper.abstractText ?? "") + "\n" + (reading(paper.id)?.body ?? ""),paper:true)
    }
    func postImageInput(_ post:UserPost) -> ImageCoverInput {
        ImageCoverInput(contentID:"post:"+post.id,title:post.title,summary:post.body,paper:false)
    }
    func generatedImageURL(_ input:ImageCoverInput) -> URL? {
        guard state.imageGenerations[input.cacheID]?.status == "ready" else { return nil }
        let url = ImageGenerationService.file(input.cacheID)
        return FileManager.default.fileExists(atPath:url.path) ? url : nil
    }
    /// Jobs 由 Store 持有，卡片离屏不取消付费请求。全局排队，最多一个生图/下载任务。
    func generateImage(_ input:ImageCoverInput,retry:Bool = false) async throws -> ImageCoverRecord {
        let id = input.cacheID
        if let job = imageJobs[id] { return try await job.value }
        if let record = state.imageGenerations[id],generatedImageURL(input) != nil { return record }
        if let record = state.imageGenerations[id],record.remoteURL == nil {
            if record.status == "unknown" || record.status == "requesting" { throw ImageCoverError.uncertain }
            if !retry { throw ImageCoverError.message(record.message ?? "上次生成未完成，请手动重试。") }
        }
        // 模式与配置在点击/自动触发时捕获，排队期间切换账号也不会错用密钥。
        let demo = isDemo,profile = imageProfile,previous = imageTail
        let job = Task { @MainActor [self] () throws -> ImageCoverRecord in
            await previous?.value
            imageActivity.insert(id);defer { imageActivity.remove(id) }
            return try await runImage(input,demo:demo,profile:profile)
        }
        imageJobs[id] = job;imageTail = Task { _ = try? await job.value }
        defer { imageJobs[id] = nil }
        return try await job.value
    }
    private func runImage(_ input:ImageCoverInput,demo:Bool,profile:AIConfiguration?) async throws -> ImageCoverRecord {
        guard storageError == nil else { throw ImageCoverError.message("请先解决本地保存问题，生图尚未提交。") }
        let id = input.cacheID
        if input.paper,state.covers[String(input.contentID.dropFirst(6))] != nil { throw ImageCoverError.message("已选择手动封面，取消尚未发送的生图任务。") }
        var record:ImageCoverRecord
        // 已拿到 URL 的结果只重试下载，绝不重新提交生图。
        if let old = state.imageGenerations[id],old.remoteURL != nil { record = old }
        else {
            let key:String
            if demo { key = try DemoAccess.key() }
            else if let profile,ImageConfiguration.accepts(profile) { key = try APIKeyStore.read(profile) }
            else { throw ImageCoverError.missingKey }
            guard !key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw ImageCoverError.missingKey }
            guard key.rangeOfCharacter(from:.controlCharacters) == nil else { throw ImageCoverError.message("密钥包含无效字符，请重新保存。") }
            record = ImageCoverRecord(id:id,contentID:input.contentID,requestID:UUID().uuidString,mode:demo ? "demo" : "personal")
            if demo { try changeImageBudget { try $0.reserve(record.requestID,content:id) } }
            saveImageRecord(record)
            await flushStorage()
            if storageError != nil {
                if demo { try changeImageBudget { $0.settle(record.requestID,billed:false) } }
                record.status = "failed";record.message = "本地保存失败，未发送生图请求。";saveImageRecord(record)
                throw ImageCoverError.message(record.message!)
            }
            do {
                record.remoteURL = try await ImageGenerationService.shared.generate(prompt:input.prompt,key:key)
            } catch {
                if let rejection = error as? ImageGenerationService.Rejection {
                    if demo { try changeImageBudget { $0.settle(record.requestID,billed:false) } }
                    record.status = "failed";record.message = rejection.localizedDescription
                    record.providerCode = rejection.code;record.httpStatus = rejection.httpStatus
                } else {
                    // 超时、断网、服务端异常可能已经产生费用：不释放预占，不自动重发。
                    record.status = "unknown";record.message = ImageCoverError.uncertain.localizedDescription
                }
                saveImageRecord(record);await flushStorage()
                throw ImageCoverError.message(record.message!)
            }
            record.status = "download";record.counted = true;saveImageRecord(record)
            // 先保留 URL，再结算额度；进程在两步之间退出也能在重试下载时幂等结算。
            await flushStorage()
        }
        if record.mode == "demo" { try changeImageBudget { $0.settle(record.requestID,billed:true) } }
        do {
            _ = try await ImageGenerationService.shared.download(record.remoteURL!,id:id)
            record.status = "ready";record.message = nil
        } catch {
            record.status = "download";record.message = "图片尚未下载成功。重试只下载已有结果，不重新生图。"
            saveImageRecord(record);await flushStorage();throw ImageCoverError.message(record.message!)
        }
        saveImageRecord(record);await flushStorage();return record
    }
    func saveImageRecord(_ record:ImageCoverRecord) {
        var updated = state
        updated.imageGenerations[record.id] = record;updated.imageCalls[record.requestID] = record
        state = updated
    }
    private func changeImageBudget(_ action:(inout ImageBudget) throws -> Void) throws {
        var ledger = try DemoAccess.load(),budget = ledger.imageBudget ?? ImageBudget()
        try action(&budget);ledger.imageBudget = budget;try DemoAccess.save(ledger);imageBudget = budget
    }
    /// 用户核对控制台后结束不明请求；保守按已使用计次，不返还可能花掉的额度。
    func closeUnknownImage(_ id:String) throws {
        guard imageJobs[id] == nil,var record = state.imageGenerations[id],["requesting","unknown"].contains(record.status) else { return }
        if record.mode == "demo" { try changeImageBudget { $0.settle(record.requestID,billed:true) } }
        record.status = "failed";record.counted = true;record.message = "已手动结束待确认请求，按使用 1 次记录；实际账单请在智谱核对。"
        saveImageRecord(record)
    }
}
