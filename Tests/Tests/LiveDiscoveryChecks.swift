import Foundation
import PDFKit

/// 主动运行才联网。只访问公共文献服务，不读取用户密钥；临时内容全部放在独立目录。
@main struct LiveDiscoveryChecks {
    @MainActor static func main() async {
        let folder = URL.temporaryDirectory.appending(path:"PaperFlow-Live-" + UUID().uuidString)
        let service = FederatedLiteratureService(directory:folder)
        await withTaskGroup(of:Void.self) { group in
        for provider in LiteratureProvider.allCases { group.addTask { @MainActor in
            var filter = ContentFilter(); filter.sources = [provider.rawValue]
            do {
                let first = try await service.search(query:provider == .europePMC ? "machine learning" : "human computer interaction",filter:filter,refresh:true)
                guard !first.papers.isEmpty else { throw ServiceError.message("实际返回为空。") }
                print("PASS: \(provider.rawValue) 真实检索，\(first.papers.count) 篇")
                if (provider == .hal || provider == .core),let paper = first.papers.first(where:{$0.pdfURL != nil}) {
                    do {
                        let result = try await PaperFileService.downloadVerified(paper,directory:folder.appending(path:provider.rawValue))
                        print("PASS: \(provider.rawValue) 真实开放原文取得并通过 PDFKit，\(PDFDocument(url:result.file)?.pageCount ?? 0) 页")
                    } catch { print("LIMITED: \(provider.rawValue) 原文 · \(error.localizedDescription)") }
                }
                if provider != .openalex && provider != .core, !first.next.isEmpty {
                    let second = try await service.search(query:provider == .europePMC ? "machine learning" : "human computer interaction",filter:filter,cursors:first.next,refresh:true)
                    let firstIDs = Set(first.papers.map(\.id))
                    guard second.papers.contains(where:{!firstIDs.contains($0.id)}) else { throw ServiceError.message("下一页没有新论文。") }
                    print("PASS: \(provider.rawValue) 下一页得到不同文献")
                }
            } catch { print("LIMITED: \(provider.rawValue) · \(error.localizedDescription)") }
        }
        }
        }
        do {
            var request = URLRequest(url:URL(string:"https://arxiv.org/pdf/1706.03762")!); request.timeoutInterval = 90
            let (file,response) = try await URLSession.shared.download(for:request)
            defer { try? FileManager.default.removeItem(at:file) }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let pdf = PDFDocument(url:file), pdf.pageCount > 1,
                  pdf.page(at:0)?.string?.contains("Attention") == true else { throw ServiceError.message("未取得完整有效原文。") }
            print("PASS: 真实开放 PDF 下载并由 PDFKit 解析，\(pdf.pageCount) 页")
        } catch { print("LIMITED: PDF · \(error.localizedDescription)") }
        try? FileManager.default.removeItem(at:folder)
    }
}
