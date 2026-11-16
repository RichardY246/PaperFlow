import Foundation

/// 开放仓储的原文链接与题录分开保存；有链接仍需要下载验证。
enum OpenRepositoryDecoders {
    nonisolated static func hal(_ data:Data) throws -> ([Paper],Int,String?) {
        let root = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        guard let response = root?["response"] as? [String:Any], let docs = response["docs"] as? [[String:Any]] else { throw ServiceError.message("HAL 返回格式无法识别。") }
        let papers = docs.compactMap { item -> Paper? in
            guard let id = item["halId_s"] as? String, let title = (item["title_s"] as? [String])?.first else { return nil }
            let pdf = PaperIdentity.webURL(item["fileMain_s"] as? String)
            let source = PaperIdentity.webURL(item["uri_s"] as? String) ?? "https://hal.science/" + id
            let abstract = (item["abstract_s"] as? [String])?.first
            let journal = item["journalTitle_s"] as? String ?? "HAL 开放仓储"
            return Paper(id:PaperIdentity.stableID("hal",id),title:title,hook:title,subtitle:"来自 HAL",author:(item["authFullName_s"] as? [String])?.first ?? "作者未提供",year:item["producedDateY_i"] as? Int ?? 0,journalID:PaperIdentity.stableID("journal",journal),topics:PaperIdentity.topics(title + " " + (abstract ?? "")),sourceURL:source,pdfURL:pdf,color:"E7E9DF",symbol:"doc.text",coverText:"研究",insights:[],abstractText:abstract,publishedAt:item["producedDate_tdate"] as? String,doi:PaperIdentity.doi(item["doiId_s"] as? String),journalTitle:journal,retrievalSources:["HAL"],versions:[PaperVersion(label:"HAL 作者开放版本",url:source,pdfURL:pdf,isOpen:pdf != nil)],fullTextStatus:pdf == nil ? "未确认" : "开放全文",openHTMLURL:source)
        }
        let total = response["numFound"] as? Int ?? papers.count
        let start = response["start"] as? Int ?? 0
        return (papers,total,start + docs.count < total ? String(start + docs.count) : nil)
    }
    nonisolated static func europePMC(_ data:Data) throws -> ([Paper],Int,String?) {
        let root = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        guard let list = root?["resultList"] as? [String:Any], let items = list["result"] as? [[String:Any]] else { throw ServiceError.message("Europe PMC 返回格式无法识别。") }
        let papers = items.compactMap { item -> Paper? in
            guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
            let pmc = item["pmcid"] as? String
            let source = pmc.map { "https://europepmc.org/articles/" + $0 } ?? "https://europepmc.org/article/" + (item["source"] as? String ?? "MED") + "/" + id
            let links = ((item["fullTextUrlList"] as? [String:Any])?["fullTextUrl"] as? [[String:Any]] ?? []).compactMap { entry -> PaperVersion? in
                guard let url = PaperIdentity.webURL(entry["url"] as? String) else { return nil }
                let isOpen = entry["availabilityCode"] as? String == "OA" || entry["availability"] as? String == "Open access"
                return PaperVersion(label:entry["site"] as? String ?? "全文版本",url:url,pdfURL:entry["documentStyle"] as? String == "pdf" && isOpen ? url : nil,isOpen:isOpen)
            }
            let info = item["journalInfo"] as? [String:Any] ?? [:]
            let journal = (info["journal"] as? [String:Any])?["title"] as? String ?? "Europe PMC"
            let abstract = (item["abstractText"] as? String).map(LiteratureDecoders.plain)
            let authors = (item["authorList"] as? [String:Any])?["author"] as? [[String:Any]] ?? []
            let date = item["firstPublicationDate"] as? String
            let open = item["isOpenAccess"] as? String == "Y"
            return Paper(id:PaperIdentity.stableID("epmc",pmc ?? ((item["source"] as? String ?? "MED") + id)),title:title,hook:title,subtitle:"来自 Europe PMC",author:authors.first?["fullName"] as? String ?? item["authorString"] as? String ?? "作者未提供",year:Int(item["pubYear"] as? String ?? "") ?? 0,journalID:PaperIdentity.stableID("journal",journal),topics:PaperIdentity.topics(title + " " + (abstract ?? "")),sourceURL:source,pdfURL:links.first(where:{$0.pdfURL != nil})?.pdfURL,color:"E2EDE7",symbol:"doc.text",coverText:"研究",insights:[],abstractText:abstract,publishedAt:date.map { $0 + "T00:00:00Z" },doi:PaperIdentity.doi(item["doi"] as? String),journalTitle:journal,retrievalSources:["Europe PMC"],versions:links + (open ? [PaperVersion(label:"Europe PMC 开放全文",url:source,isOpen:true)] : []),fullTextStatus:open ? "开放全文" : "未确认",openHTMLURL:open ? source : nil)
        }
        return (papers,root?["hitCount"] as? Int ?? papers.count,root?["nextCursorMark"] as? String)
    }
    nonisolated static func core(_ data:Data) throws -> ([Paper],Int,String?) {
        let root = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        guard let docs = root?["results"] as? [[String:Any]] else { throw ServiceError.message("CORE 返回格式无法识别。") }
        let papers = docs.compactMap { item -> Paper? in
            guard let number = item["id"], let title = item["title"] as? String else { return nil }
            let id = String(describing:number), doi = PaperIdentity.doi(item["doi"] as? String)
            let download = PaperIdentity.webURL(item["downloadUrl"] as? String)
            let source = "https://core.ac.uk/works/" + id
            let authors = item["authors"] as? [[String:Any]] ?? []
            let abstract = item["abstract"] as? String
            let versions = (item["sourceFulltextUrls"] as? [String] ?? []).compactMap { PaperIdentity.webURL($0) }.map { PaperVersion(label:"仓储版本",url:$0,isOpen:true) }
            return Paper(id:PaperIdentity.stableID("core",id),title:title,hook:title,subtitle:"来自 CORE",author:authors.first?["name"] as? String ?? "作者未提供",year:item["yearPublished"] as? Int ?? 0,journalID:"core-repository",topics:PaperIdentity.topics(title + " " + (abstract ?? "")),sourceURL:source,pdfURL:download,color:"EAE5DC",symbol:"doc.text",coverText:"研究",insights:[],abstractText:abstract,doi:doi,journalTitle:"CORE 开放仓储",retrievalSources:["CORE"],versions:versions + (download.map { [PaperVersion(label:"CORE 开放版本",url:$0,pdfURL:$0,isOpen:true)] } ?? []),fullTextStatus:download == nil ? "未确认" : "开放全文")
        }
        return (papers,root?["totalHits"] as? Int ?? papers.count,nil)
    }
}
