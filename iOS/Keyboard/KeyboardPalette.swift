import UIKit

enum KeyboardPalette {
    static let background = color(0xE4F2E9, 0x193228, tablet: .systemGray4)
    static let paper = color(0xFAFFFB, 0x243F32, tablet: .secondarySystemGroupedBackground)
    static let control = color(0xC5E0CF, 0x375847, tablet: .systemGray3)
    static let ink = color(0x153E2C, 0xE3F5E8, tablet: .label)
    static let secondaryInk = color(0x395C48, 0xBEDAC8, tablet: .secondaryLabel)
    static let mic = color(0xA8D8B9, 0xA8D8B9, tablet: .label)
    static let micInk = rgb(0x123C29)
    static let recording = rgb(0x215E42)
    static let onRecording = rgb(0xF4FFF7)

    private static func color(_ light: Int, _ dark: Int, tablet: UIColor) -> UIColor {
        UIColor { traits in
            guard traits.userInterfaceIdiom == .phone else { return tablet.resolvedColor(with: traits) }
            return rgb(traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    private static func rgb(_ value: Int) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
