import SwiftUI

/// Visual tokens from the mockups (§5). Dark values match the designs; light values are system-like
/// counterparts so light mode works. Prefer semantic system colors where a token isn't needed.
enum Theme {
    static let windowBackground = Color(light: 0xF5F5F7, dark: 0x1E1E1E)
    static let sidebar = Color(light: 0xEBEBED, dark: 0x28282A)
    static let toolbar = Color(light: 0xF2F2F4, dark: 0x262628)
    static let cell = Color(light: 0xFFFFFF, dark: 0x262628)
    static let cellBorder = Color.primary.opacity(0.07)
    static let separator = Color.primary.opacity(0.06)
    static let control = Color(light: 0xE5E5EA, dark: 0x3A3A3C)
    static let field = Color(light: 0xFFFFFF, dark: 0x2C2C2E)

    static let textPrimary = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let textSecondary = Color(light: 0x6E6E73, dark: 0xA1A1A6)
    static let textTertiary = Color(light: 0x8E8E93, dark: 0x8E8E93)

    /// Fills under white text (primary buttons).
    static let accentFill = Color(hex: 0x0071E3)
    /// Icons and links.
    static let accent = Color(light: 0x0066CC, dark: 0x0A84FF)
    static let link = Color(light: 0x0066CC, dark: 0x4DA3FF)
    static let sidebarSelection = Color(hex: 0x0058D0)

    static let running = Color(light: 0x28A745, dark: 0x30D158)
    static let suspended = Color(light: 0xE68600, dark: 0xFF9F0A)
    static let stopped = Color(hex: 0x8E8E93)
    static let destructive = Color(light: 0xD70015, dark: 0xFF6961)
    static let warning = Color(light: 0xE68600, dark: 0xFF9F0A)

    static let cornerRadius: CGFloat = 12

    /// Placeholder "desktop" gradient used for VM previews without a thumbnail.
    static let wallpaper = LinearGradient(
        stops: [.init(color: Color(hex: 0x3E5C9A), location: 0),
                .init(color: Color(hex: 0x1B2238), location: 0.55),
                .init(color: Color(hex: 0x8A4F6E), location: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    enum Font {
        static let body = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 11)
        static let captionStrong = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let small = SwiftUI.Font.system(size: 12)
        static let sectionTitle = SwiftUI.Font.system(size: 15, weight: .bold)
        static let title = SwiftUI.Font.system(size: 22, weight: .bold)
        static let largeTitle = SwiftUI.Font.system(size: 34, weight: .bold)
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
