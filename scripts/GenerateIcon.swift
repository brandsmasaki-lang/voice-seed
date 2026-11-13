import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let resources = root.appendingPathComponent("Resources")
let concepts = resources.appendingPathComponent("IconConcepts")
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: concepts, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let emerald = NSColor(srgbRed: 0.09, green: 0.27, blue: 0.22, alpha: 1)
let mint = NSColor(srgbRed: 0.63, green: 0.90, blue: 0.73, alpha: 1)
let coral = NSColor(srgbRed: 0.98, green: 0.62, blue: 0.35, alpha: 1)

func glyph(in rect: CGRect, color: NSColor) {
    let font = CTFontCreateWithName("HiraginoSans-W8" as CFString, 1000, nil)
    var character: UniChar = 0x58F0 // 声 — preserve the exact kanji outline.
    var glyph: CGGlyph = 0
    precondition(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
    let path = CTFontCreatePathForGlyph(font, glyph, nil)!
    let bounds = path.boundingBoxOfPath
    let scale = min(rect.width / bounds.width, rect.height / bounds.height)
    let cg = NSGraphicsContext.current!.cgContext
    cg.saveGState()
    cg.translateBy(x: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale)
    cg.scaleBy(x: scale, y: scale)
    cg.addPath(path); cg.setFillColor(color.cgColor); cg.fillPath()
    cg.restoreGState()
}

func icon(_ variant: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(srgbRed: 0.17, green: 0.40, blue: 0.31, alpha: 1), ending: emerald)!.draw(in: background, angle: -65)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    background.lineWidth = 3; background.stroke()
    if variant == 0 {
        glyph(in: CGRect(x: 158, y: 208, width: 620, height: 628), color: .white)
        for radius in [64.0, 114.0] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 730, y: 490), radius: radius, startAngle: -51, endAngle: 51)
            arc.lineWidth = 28; arc.lineCapStyle = .round
            mint.setStroke(); arc.stroke()
        }
    } else if variant == 1 {
        glyph(in: CGRect(x: 190, y: 190, width: 644, height: 644), color: .white)
        let dot = NSBezierPath(ovalIn: NSRect(x: 735, y: 755, width: 110, height: 110))
        coral.setFill(); dot.fill()
    } else {
        let bubble = NSBezierPath(roundedRect: NSRect(x: 155, y: 225, width: 714, height: 620), xRadius: 118, yRadius: 118)
        bubble.move(to: NSPoint(x: 285, y: 260)); bubble.line(to: NSPoint(x: 245, y: 145)); bubble.line(to: NSPoint(x: 432, y: 260)); bubble.close()
        mint.setFill(); bubble.fill()
        glyph(in: CGRect(x: 292, y: 320, width: 440, height: 440), color: emerald)
    }
    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

let names = ["声と音波", "声と録音点", "声と吹き出し"]
let images = (0..<3).map(icon)
for (i, image) in images.enumerated() { try png(image, pixels: 1024, to: concepts.appendingPathComponent("\(i + 1)-\(names[i]).png")) }
try png(images[0], pixels: 1024, to: resources.appendingPathComponent("AppIcon1024.png"))
for size in [16, 32, 128, 256, 512] {
    try png(images[0], pixels: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(images[0], pixels: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let sheet = NSImage(size: NSSize(width: 1320, height: 520))
sheet.lockFocus()
NSColor(srgbRed: 0.96, green: 0.96, blue: 0.93, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1320, height: 520)).fill()
for i in 0..<3 {
    images[i].draw(in: NSRect(x: 36 + i * 432, y: 94, width: 384, height: 384))
    let title = "\(i + 1). \(names[i])" + (i == 0 ? " 〔採用案〕" : "")
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 25, weight: .semibold), .foregroundColor: emerald]
    let label = NSAttributedString(string: title, attributes: attrs)
    label.draw(at: NSPoint(x: CGFloat(36 + i * 432) + (384 - label.size().width) / 2, y: 45))
}
sheet.unlockFocus()
let sheetRep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try sheetRep.representation(using: .png, properties: [:])!.write(to: concepts.appendingPathComponent("アイコン比較.png"))
print("Created 声 icon assets and three concepts")
