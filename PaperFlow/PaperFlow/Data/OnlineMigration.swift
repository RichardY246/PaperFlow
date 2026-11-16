import Foundation

// 仅用于恢复旧用户已经保存的文献身份；新安装不会注入这些论文，也没有内置 PDF。
extension AppStore {
    func migrateOnlineState() {
        guard storageError == nil, state.revision < 2 else { return }
        var updated = state
        let legacy: [String:(String,String,Int,String,String,String)] = [
        "attention": ("Attention Is All You Need","Ashish Vaswani",2017,"arxiv","https://arxiv.org/abs/1706.03762","https://arxiv.org/pdf/1706.03762"),
        "rag": ("Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks","Patrick Lewis",2020,"arxiv","https://arxiv.org/abs/2005.11401","https://arxiv.org/pdf/2005.11401"),
        "lora": ("LoRA: Low-Rank Adaptation of Large Language Models","Edward J. Hu",2021,"arxiv","https://arxiv.org/abs/2106.09685","https://arxiv.org/pdf/2106.09685"),
        "clip": ("Learning Transferable Visual Models From Natural Language Supervision","Alec Radford",2021,"arxiv","https://arxiv.org/abs/2103.00020","https://arxiv.org/pdf/2103.00020"),
        "ddpm": ("Denoising Diffusion Probabilistic Models","Jonathan Ho",2020,"arxiv","https://arxiv.org/abs/2006.11239","https://arxiv.org/pdf/2006.11239"),
        "resnet": ("Deep Residual Learning for Image Recognition","Kaiming He",2015,"arxiv","https://arxiv.org/abs/1512.03385","https://arxiv.org/pdf/1512.03385"),
        "deep": ("Deep learning","Yann LeCun",2015,"nature","https://doi.org/10.1038/nature14539","https://www.cs.toronto.edu/~hinton/absps/NatureDeepReview.pdf"),
        "folk": ("A Few Useful Things to Know about Machine Learning","Pedro Domingos",2012,"cacm","https://doi.org/10.1145/2347736.2347755","https://homes.cs.washington.edu/~pedrod/papers/cacm12.pdf"),
        ]
        let postReferences = updated.posts.flatMap(\.links).filter { $0.hasPrefix("paper:") }.map { String($0.dropFirst(6)) }
        let followedReferences = updated.following.filter { $0.hasPrefix("paper:") }.map { String($0.dropFirst(6)) }
        let references = Set(postReferences + followedReferences + updated.history + Array(updated.notes.keys) + updated.bookmarks.keys.filter { $0.hasPrefix("paper:") }.map { String($0.dropFirst(6)) } + updated.reads.values.flatMap { $0 })
        for (id,v) in legacy where references.contains(id) && !catalog.papers.contains(where: { $0.id == id }) && !updated.importedPapers.contains(where: { $0.id == id }) {
            updated.importedPapers.append(Paper(id:id,title:v.0,hook:v.0,subtitle:"",author:v.1,year:v.2,journalID:v.3,topics:[],sourceURL:v.4,pdfURL:v.5,color:"DDEAE4",symbol:"doc.text",coverText:"PAPER",insights:[],retrievalSources:[v.3 == "arxiv" ? "arXiv" : "出版社"],fullTextStatus:"未确认"))
        }
        for i in updated.importedPapers.indices { updated.importedPapers[i].localPDF = nil }
        updated.following.remove("user:PaperFlow AI")
        if updated.apiProfiles.isEmpty { updated.apiProfiles = [updated.aiConfiguration] }
        updated.revision = 2; state = updated
    }
}
