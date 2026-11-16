import Foundation
import PDFKit

extension AppStore {
    /// 先尝试所有已知开放版本，再按同一论文身份查其他仓储，保留旧收藏和笔记。
    func obtainFullText(_ id:String,allowLookup:Bool = true) async throws -> URL {
        guard let original = paper(id) else { throw ServiceError.message("文献不存在。") }
        var current = original
        do { return cacheReceipt(try await PaperFileService.downloadVerified(current,maxAttempts:allowLookup ? 4 : 3,timeout:allowLookup ? 25 : 18),paper:current) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            guard allowLookup, current.doi != nil else { throw error }
        }
        let service = FederatedLiteratureService.shared
        if !state.libraryConfiguration.contactEmail.isEmpty,
           let enriched = try? await service.findOpenVersion(current,email:state.libraryConfiguration.contactEmail) { current = PaperIdentity.merge(current,enriched) }
        var filter = ContentFilter(); filter.sources = ["HAL","Europe PMC","CORE","OpenAlex"]; filter.access = "开放全文"
        if let doi = current.doi {
            do {
                let results = try await service.search(query:doi,filter:filter,openAlexKey:LibraryKeyStore.read(),coreKey:LibraryKeyStore.read("CORE"))
                for candidate in results.papers where PaperIdentity.same(current,candidate) { current = PaperIdentity.merge(current,candidate) }
            } catch { if Task.isCancelled { throw CancellationError() } }
        }
        try Task.checkCancellation(); _ = importPaper(current)
        return cacheReceipt(try await PaperFileService.downloadVerified(current),paper:current)
    }
    private func cacheReceipt(_ receipt:PaperFileService.Download,paper:Paper) -> URL {
        if paper.hasCachedFullText == true, paper.verifiedPDFURL == receipt.remoteURL { return receipt.file }
        var updated = paper; updated.verifiedPDFURL = receipt.remoteURL; updated.fullTextCheckedAt = Date().timeIntervalSince1970
        updated.hasCachedFullText = true; updated.fullTextStatus = "可直接阅读全文"; _ = importPaper(updated)
        return receipt.file
    }
    func importFullText(_ id:String,from url:URL) throws -> URL {
        guard var paper = paper(id) else { throw ServiceError.message("文献不存在。") }
        let file = try PaperFileService.importPDF(url,for:paper)
        paper.hasCachedFullText = true; paper.fullTextCheckedAt = Date().timeIntervalSince1970; paper.fullTextStatus = "可直接阅读全文"; _ = importPaper(paper)
        return file
    }
    func recordCachedFullText(_ id:String) {
        guard let paper = paper(id),let url = PaperFileService.localURL(paper),PDFDocument(url:url)?.pageCount ?? 0 > 0 else { return }
        _ = cacheReceipt(PaperFileService.Download(file:url,remoteURL:paper.verifiedPDFURL),paper:paper)
    }
    func clearFullTextVerification() {
        var updated = state
        for i in updated.importedPapers.indices {
            updated.importedPapers[i].hasCachedFullText = false; updated.importedPapers[i].fullTextCheckedAt = nil; updated.importedPapers[i].verifiedPDFURL = nil
            if updated.importedPapers[i].fullTextStatus == "可直接阅读全文" {
                updated.importedPapers[i].fullTextStatus = (updated.importedPapers[i].pdfURL != nil || updated.importedPapers[i].versions?.contains(where: \.isOpen) == true) ? "开放全文" : "未确认"
            }
        }
        state = updated
    }
}
