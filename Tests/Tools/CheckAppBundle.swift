import Foundation
import CoreText

// 检查真正的构建产物，而非仅检查源码目录。不会启动模拟器或读取个人数据。
@main struct CheckAppBundle {
    static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let files = FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)!.allObjects.compactMap { $0 as? URL }
        func check(_ value:Bool,_ name:String) { precondition(value,name); print("PASS: " + name) }
        check(!files.contains { $0.pathExtension.lowercased() == "pdf" },"App 安装包没有演示 PDF")
        check(!files.contains { $0.lastPathComponent == "LegacyCatalog.json" || $0.lastPathComponent == "PapersManifest.json" },"App 不包含历史测试夹具")
        let catalog = files.first { $0.lastPathComponent == "DemoCatalog.json" }!
        let raw = try JSONSerialization.jsonObject(with:Data(contentsOf:catalog)) as! [String:Any]
        check((raw["papers"] as? [Any])?.isEmpty == true,"安装包不预置论文")
        let font = files.first { $0.lastPathComponent == "NotoSerifCJKsc-Regular.otf" }!
        var error:Unmanaged<CFError>?
        check(CTFontManagerRegisterFontsForURL(font as CFURL,.process,&error),"衬线字体能注册")
        let ct = CTFontCreateWithName("NotoSerifCJKsc-Regular" as CFString,17,nil)
        check((CTFontCopyPostScriptName(ct) as String) == "NotoSerifCJKsc-Regular","界面字体名称匹配真实字体")
        let characters = Array("学术阅读Aa123".utf16)
        var glyphs = Array<CGGlyph>(repeating:0,count:characters.count)
        check(CTFontGetGlyphsForCharacters(ct,characters,&glyphs,characters.count) && !glyphs.contains(0),"同一衬线字体覆盖中文、英文和数字")
        check(files.contains { $0.lastPathComponent == "LICENSE.txt" },"附带字体许可")
        let plist = try PropertyListSerialization.propertyList(from:Data(contentsOf:root.appending(path:"Info.plist")),format:nil) as! [String:Any]
        check(plist["CFBundleShortVersionString"] as? String == "1.8.2","安装包版本为 1.8.2")
        let orientations = (plist["UISupportedInterfaceOrientations~iphone"] ?? plist["UISupportedInterfaceOrientations"]) as? [String]
        check(orientations?.contains("UIInterfaceOrientationLandscapeLeft") == true,"iPhone 支持横屏阅读")
        print("ALL 9 BUNDLE CHECKS PASSED")
    }
}
