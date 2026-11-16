import Foundation

/// 保留原词；识别文献编号、扩展常见中文方向，去掉口语检索前缀。
nonisolated struct LiteratureQuery {
    var original:String
    var english:String
    var identifier:String?
    var isDOI:Bool
    init(_ value:String) {
        original = String(value.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300))
        let raw = original.replacingOccurrences(of:#"^doi:\s*"#,with:"",options:[.regularExpression,.caseInsensitive])
        let doi = PaperIdentity.doi(raw)
        let arxiv = PaperIdentity.arxiv(raw) ?? Self.arxivID(raw)
        identifier = doi ?? arxiv; isDOI = doi != nil
        let aliases = [("生成式人工智能","generative artificial intelligence"),("生成式AI","generative AI"),("生成式 AI","generative AI"),("人工智能","artificial intelligence"),("人机交互","human computer interaction"),("交互设计","interaction design"),("机器学习","machine learning"),("计算机视觉","computer vision"),("大语言模型","large language model"),("大模型","language model"),("扩散模型","diffusion model"),("可持续设计","sustainable design"),("用户体验","user experience"),("设计方法","design methods"),("工业设计","industrial design"),("产品设计","product design"),("认知科学","cognitive science"),("机器人","robotics"),("医疗健康","healthcare"),("虚拟现实","virtual reality"),("增强现实","augmented reality"),("建筑","architecture"),("设计","design")]
        var translated = original
        for prefix in ["请帮我搜索","请帮我找","帮我找","搜索一下","我想找","我想了解","关于","有关"] { translated = translated.replacingOccurrences(of:prefix,with:" ") }
        for suffix in ["相关的论文","相关论文","的文献","的论文","方面的研究","方面","有哪些","论文","文献"] { translated = translated.replacingOccurrences(of:suffix,with:" ") }
        for (zh,en) in aliases { translated = translated.replacingOccurrences(of:zh,with:" " + en + " ",options:.caseInsensitive) }
        let latin = translated.components(separatedBy:CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator:" ").split(whereSeparator:{$0.isWhitespace}).map(String.init)
        let meaningful = latin // 未命中词表的中文也保留，不能静默丢失检索条件。
        english = meaningful.isEmpty ? original : Array(NSOrderedSet(array:meaningful)) .compactMap { $0 as? String }.joined(separator:" ")
        if let identifier { english = identifier }
    }
    static func arxivID(_ raw:String) -> String? {
        let text = raw.replacingOccurrences(of:#"^(arxiv:|https?://arxiv.org/pdf/)"#,with:"",options:[.regularExpression,.caseInsensitive]).replacingOccurrences(of:".pdf",with:"")
        guard text.range(of:#"^(\d{4}\.\d{4,5}|[a-z-]+/\d{7})(v\d+)?$"#,options:.regularExpression) != nil else { return nil }
        return text.replacingOccurrences(of:#"v\d+$"#,with:"",options:.regularExpression)
    }
    var words:[String] { english.split(whereSeparator:{$0.isWhitespace}).prefix(10).map(String.init) }
}
