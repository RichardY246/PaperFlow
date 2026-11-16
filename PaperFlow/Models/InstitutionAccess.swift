import Foundation

nonisolated struct LibrarySite: Identifiable {
    var id:String
    var name:String
    var url:String
    var detail:String = ""
    static let hnuLogin = "https://cas.hnu.edu.cn/cas/login?service=https%3A%2F%2Funified-auth.chaoxing.com%2Flogin_auth%2Fcas%2Fhnu%2Findex"
    static let all = [
        LibrarySite(id:"hnu",name:"湖南大学 · 统一身份认证",url:hnuLogin,detail:"个人门户账号；登录后继续访问图书馆。"),
        LibrarySite(id:"hnu-vpn",name:"湖南大学 · WebVPN",url:"https://webvpn.hnu.edu.cn/",detail:"校外访问校内资源；在学校页面选择数据库。"),
        LibrarySite(id:"hnu-guide",name:"湖南大学 · 校外访问说明",url:"https://lib.hnu.edu.cn/engine2/d/9873452/1681726/0",detail:"校方发布的访问指南与资源入口。"),
        LibrarySite(id:"carsi",name:"CARSI · 学校与机构",url:"https://ds.carsi.edu.cn/",detail:"选择湖南大学或自己的机构，再进入已订购的数据库。"),
        LibrarySite(id:"elsevier",name:"ScienceDirect",url:"https://www.sciencedirect.com/",detail:"选择机构登录；能否阅读全文取决于学校订购范围。"),
        LibrarySite(id:"cnki",name:"中国知网",url:"https://www.cnki.net/",detail:"使用学校提供的机构访问方式。")
    ]
    static func profile(for url:URL) -> String {
        let host = (url.host ?? "").lowercased()
        func matches(_ domain:String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if matches("sciencedirect.com") || matches("elsevier.com") { return "elsevier" }
        if matches("cnki.net") { return "cnki" }
        if matches("hnu.edu.cn") || matches("chaoxing.com") { return "hnu" }
        if matches("carsi.edu.cn") { return "carsi" }
        return "public"
    }
    static func domains(_ id:String) -> [String] {
        if id.hasPrefix("hnu") { return ["hnu.edu.cn","chaoxing.com"] }
        return ["carsi":["carsi.edu.cn"],"elsevier":["elsevier.com","sciencedirect.com"],"cnki":["cnki.net"]][id] ?? []
    }
}
