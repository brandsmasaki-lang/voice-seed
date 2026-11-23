import UIKit

enum KeyboardPalette {
    static let background = color(0xF5FAF7, 0x34413A)
    static let paper = color(0xFDFFFE, 0x404D46)
    static let control = color(0xE6F0E9, 0x516158)
    static let ink = color(0x314D3F, 0xECF4EF)
    static let secondaryInk = color(0x52665A, 0xC9D9CE)
    static let mic = color(0xDBEDE1, 0xC4D9CB)
    static let micInk = rgb(0x355844)
    static let recording = rgb(0xBADCC7)
    static let onRecording = rgb(0x2D503D)

    private static func color(_ light: Int, _ dark: Int) -> UIColor {
        UIColor { traits in
            return rgb(traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    private static func rgb(_ value: Int) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
