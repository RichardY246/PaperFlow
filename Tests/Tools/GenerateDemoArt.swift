// 可复现的原生插画资源：4:3 横版、无文字，不依赖远程图片或生图密钥。
import AppKit
import Foundation
let root = URL(fileURLWithPath:CommandLine.arguments[1])
let canvas = CGRect(x:0,y:0,width:1200,height:900)
func color(_ hex:UInt32,_ alpha:CGFloat = 1) -> NSColor { NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:alpha) }
func round(_ rect:CGRect,_ radius:CGFloat,_ fill:NSColor) { fill.setFill();NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill() }
func circle(_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ fill:NSColor) { fill.setFill();NSBezierPath(ovalIn:CGRect(x:x,y:y,width:size,height:size)).fill() }
func path(_ points:[CGPoint],_ stroke:NSColor,_ width:CGFloat) {
    guard let first = points.first else { return };let p = NSBezierPath();p.move(to:first)
    for point in points.dropFirst() { p.line(to:point) };p.lineWidth = width;p.lineJoinStyle = .round;p.lineCapStyle = .round;stroke.setStroke();p.stroke()
}
func shadow(_ blur:CGFloat = 35,_ offset:CGSize = CGSize(width:0,height:-25),_ alpha:CGFloat = 0.24) { let s = NSShadow();s.shadowBlurRadius = blur;s.shadowOffset = offset;s.shadowColor = NSColor.black.withAlphaComponent(alpha);s.set() }
func rotated(_ angle:CGFloat,_ center:CGPoint,_ body:() -> Void) {
    NSGraphicsContext.saveGraphicsState();let t = NSAffineTransform();t.translateX(by:center.x,yBy:center.y);t.rotate(byDegrees:angle);t.translateX(by:-center.x,yBy:-center.y);t.concat();body();NSGraphicsContext.restoreGraphicsState()
}
func background(_ a:UInt32,_ b:UInt32) {
    NSGradient(starting:color(a),ending:color(b))!.draw(in:canvas,angle:32)
    circle(-100,560,530,color(0xFFFFFF,0.06));circle(870,-180,650,color(0xFFFFFF,0.08))
    for i in 0..<12 { circle(CGFloat(80+i*91),CGFloat(60+(i*127)%780),3,color(0xFFFFFF,0.25)) }
}
func paper(_ rect:CGRect,_ tint:UInt32 = 0xFFF9ED) {
    NSGraphicsContext.saveGraphicsState();shadow();round(rect,22,color(tint));NSGraphicsContext.restoreGraphicsState()
    round(CGRect(x:rect.minX+26,y:rect.minY+20,width:8,height:rect.height-40),4,color(0x29304D,0.08))
}
func reading(_ variant:Int) {
    background([UInt32(0x123D58),0x512779,0x72543B][variant],[UInt32(0x23B1B0),0xF48082,0xF3B94F][variant])
    rotated(CGFloat(-11+variant*8),CGPoint(x:600,y:460)) {
        paper(CGRect(x:270,y:170,width:640,height:560))
        // 页面只用抽象短线表示纹理，不绘制文字。
        for column in 0..<2 { for line in 0..<12 { round(CGRect(x:CGFloat(330+column*265),y:CGFloat(240+line*33),width:CGFloat(160+(line*37)%62),height:5),2,color(0x60797A,0.18)) } }
        round(CGRect(x:600,y:480,width:175,height:30),5,color(0xFFD15F,0.8))
        round(CGRect(x:330,y:370,width:200,height:30),5,color(0x47CECA,0.45))
        for (i,c) in [UInt32(0xFF795E),0xFFCD5C,0x50CFC4].enumerated() {
            NSGraphicsContext.saveGraphicsState();shadow(12,CGSize(width:0,height:-6),0.12);round(CGRect(x:CGFloat(420+i*125),y:650,width:80,height:115),10,color(c));NSGraphicsContext.restoreGraphicsState()
        }
    }
    rotated(22,CGPoint(x:900,y:340)) { shadow(10,CGSize(width:6,height:-6),0.2);round(CGRect(x:880,y:180,width:25,height:340),10,color(0xFD785F));round(CGRect(x:886,y:180,width:8,height:330),4,color(0xFFA891)) }
    NSShadow().set();circle(85,115,180,color(0xE8FAE3));circle(108,138,134,color(0x246E73));circle(120,151,110,color(0x153D4C));path([CGPoint(x:250,y:185),CGPoint(x:295,y:185),CGPoint(x:300,y:225),CGPoint(x:253,y:235)],color(0xE8FAE3),18)
}
func attention(_ variant:Int) {
    background(variant == 0 ? 0x151D50 : 0x253E5A,variant == 0 ? 0x5041A7 : 0x35A798)
    let colors:[UInt32] = [0x5AF1DE,0x97B9FF,0xFF9A93,0xFFD784]
    for a in 0..<4 { for b in 0..<4 {
        let opacity:CGFloat = a == b || b == (a+1)%4 ? 0.7 : 0.12
        let p = NSBezierPath();p.move(to:CGPoint(x:285,y:CGFloat(210+a*160)));p.curve(to:CGPoint(x:900,y:CGFloat(210+b*160)),controlPoint1:CGPoint(x:510,y:CGFloat(220+a*160)),controlPoint2:CGPoint(x:660,y:CGFloat(230+b*160)));p.lineWidth = a == b ? 10 : 3;color(colors[a],opacity).setStroke();p.stroke()
    } }
    for column in 0..<2 { for i in 0..<4 { let x:CGFloat = column == 0 ? 210 : 840,y = CGFloat(170+i*160)
        NSGraphicsContext.saveGraphicsState();shadow(24,.zero,0.18);round(CGRect(x:x,y:y,width:125,height:90),24,color(colors[i]));NSGraphicsContext.restoreGraphicsState();circle(x+35,y+19,50,color(0xFFFFFF,0.4))
    } }
    circle(507,343,180,color(0xAFA5FF,0.14));circle(543,379,108,color(0xF2EAFE,0.9));circle(566,402,62,color(0x8576EA))
}
func pairing(_ variant:Int) {
    background([UInt32(0x642E78),0x163B71,0x584E8F][variant],[UInt32(0xFC866C),0x48C2BA,0xEEB574][variant])
    rotated(CGFloat(-13+variant*8),CGPoint(x:370,y:450)) {
        paper(CGRect(x:135,y:210,width:420,height:480),0xFFF1DD)
        round(CGRect(x:165,y:285,width:360,height:365),16,color(0xA4DCD7));circle(415,530,65,color(0xFFE6A0))
        let hill = NSBezierPath();hill.move(to:CGPoint(x:165,y:285));hill.line(to:CGPoint(x:165,y:380));hill.curve(to:CGPoint(x:525,y:420),controlPoint1:CGPoint(x:300,y:620),controlPoint2:CGPoint(x:420,y:280));hill.line(to:CGPoint(x:525,y:285));hill.close();color(0x347A82).setFill();hill.fill()
        let front = NSBezierPath();front.move(to:CGPoint(x:165,y:285));front.line(to:CGPoint(x:165,y:340));front.curve(to:CGPoint(x:525,y:345),controlPoint1:CGPoint(x:325,y:450),controlPoint2:CGPoint(x:430,y:280));front.line(to:CGPoint(x:525,y:285));front.close();color(0xE7B878).setFill();front.fill()
    }
    rotated(12,CGPoint(x:860,y:460)) {
        paper(CGRect(x:665,y:250,width:390,height:420),0xF4ECFE)
        for row in 0..<5 { let w = CGFloat(180+(row*33)%120);round(CGRect(x:710,y:CGFloat(320+row*62),width:w,height:18),9,color(0x846CC4,CGFloat(0.3+Double(row)*0.1))) }
    }
    path([CGPoint(x:525,y:465),CGPoint(x:680,y:465)],color(0xFFF9D6),13);circle(573,436,60,color(0xFFE49A))
}
func folders() {
    background(0x43317B,0xEA7591)
    for (index,tint) in [UInt32(0x6CCDD4),0xFFD16A,0xFF875F].enumerated() {
        let x = CGFloat(200+index*165),y = CGFloat(170+index*90)
        rotated(CGFloat(-12+index*10),CGPoint(x:x+250,y:y+180)) {
            NSGraphicsContext.saveGraphicsState();shadow();round(CGRect(x:x,y:y,width:490,height:310),28,color(tint));round(CGRect(x:x,y:y+250,width:210,height:115),22,color(tint));NSGraphicsContext.restoreGraphicsState()
            round(CGRect(x:x+22,y:y+55,width:440,height:225),14,color(0xFFFBE9));round(CGRect(x:x+30,y:y+65,width:425,height:185),14,color(tint));path([CGPoint(x:x+60,y:y+130),CGPoint(x:x+400,y:y+130)],color(0xFFFFFF,0.25),5)
        }
    }
}
func calendar() {
    background(0x143D60,0x239B9E)
    rotated(-9,CGPoint(x:600,y:450)) {
        paper(CGRect(x:215,y:155,width:770,height:580),0xE6F5E9)
        let colors:[UInt32] = [0xD1E5D9,0xA6DCC0,0x64C7A7,0x1B9E85,0x126E6C]
        for row in 0..<6 { for col in 0..<10 { let i = (row*13+col*7)%5
            round(CGRect(x:CGFloat(255+col*69),y:CGFloat(220+row*74),width:51,height:53),10,color(colors[i]))
            if i > 2 { round(CGRect(x:CGFloat(259+col*69),y:CGFloat(260+row*74),width:43,height:4),2,color(0xFFFFFF,0.3)) }
        } }
        for x in [340,850] { round(CGRect(x:x,y:680,width:26,height:105),13,color(0xF9CD7B)) }
    }
    circle(925,70,140,color(0xFFD67D));path([CGPoint(x:960,y:133),CGPoint(x:987,y:108),CGPoint(x:1030,y:160)],color(0x1B676A),12)
}
let names = ["NotesQuestions","NotesMethod","NotesMargin","AttentionMap","AttentionNote","ClipPair","ClipQuestions","ClipPlan","FolderNotes","DailyReading"]
for (index,name) in names.enumerated() {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:900,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    switch index { case 0...2: reading(index);case 3...4: attention(index%2);case 5...7: pairing(index-5);case 8: folders();default: calendar() }
    NSGraphicsContext.restoreGraphicsState()
    let directory = root.appending(path:name+".imageset");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appending(path:name+".png"))
    let json:[String:Any] = ["images":[["filename":name+".png","idiom":"universal"]],"info":["author":"xcode","version":1]]
    try JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appending(path:"Contents.json"))
}
