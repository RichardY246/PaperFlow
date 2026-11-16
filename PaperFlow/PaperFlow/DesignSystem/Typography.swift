import SwiftUI
import UIKit
import CoreText

/// 一份字体同时覆盖中英文，避免系统为中文回退到无衬线字体。
enum FlowTypography {
    static let name = "NotoSerifCJKsc-Regular"
    static func configure() {
        if let url = Bundle.main.url(forResource:name,withExtension:"otf") ?? Bundle.main.url(forResource:name,withExtension:"otf",subdirectory:"Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        }
        let font = uiFont(17)
        UITextField.appearance().font = font; UITextView.appearance().font = font
        UILabel.appearance().font = font
        UINavigationBar.appearance().titleTextAttributes = [.font:uiFont(18)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font:uiFont(32)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font:font],for:.normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font:uiFont(15)],for:.normal)
        UISearchTextField.appearance().font = font
    }
    static func uiFont(_ size: CGFloat) -> UIFont {
        UIFont(name:name,size:size) ?? UIFont(descriptor:UIFont.systemFont(ofSize:size).fontDescriptor.withDesign(.serif)!,size:size)
    }
}
