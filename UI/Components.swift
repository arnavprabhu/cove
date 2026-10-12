import SwiftUI

/// Rounded "grouped cell" card (Library spec list, settings). Put `CardDivider()` between rows.
struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.cellBorder))
    }
}

/// Hairline between rows inside a `GroupedCard`.
struct CardDivider: View {
    var body: some View { Rectangle().fill(Theme.separator).frame(height: 1) }
}

/// Label on the left, value on the right.
struct SpecRow<Value: View>: View {
    var label: LocalizedStringKey
    @ViewBuilder var value: Value

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            value
        }
        .font(Theme.Font.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension SpecRow where Value == Text {
    init(_ label: LocalizedStringKey, _ value: String) {
        self.label = label
        self.value = Text(value)
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

struct SectionHeader: View {
    var title: LocalizedStringKey
    var body: some View {
        Text(title).font(Theme.Font.captionStrong).foregroundStyle(Theme.textTertiary)
    }
}

/// Blue filled button (`#0071E3`).
struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 24 : 18)
            .frame(height: large ? 44 : 32)
            .background(Theme.accentFill.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: large ? 10 : 8))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Gray filled button (`#3A3A3C`).
struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(destructive ? Theme.destructive : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Theme.control.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var coveprimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var coveprimaryLarge: PrimaryButtonStyle { PrimaryButtonStyle(large: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var covesecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// VM screen preview: last-frame thumbnail if available, else the wallpaper placeholder.
struct VMPreview: View {
    var image: NSImage?
    var cornerRadius: CGFloat = Theme.cornerRadius

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Theme.wallpaper
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.10)))
    }
}

/// Thin capsule progress/usage bar.
struct UsageBar: View {
    var fraction: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.control)
                Capsule().fill(tint).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

enum Durations {
    /// "about 4 min left"
    static func remaining(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite else { return nil }
        if seconds < 60 { return "less than a minute left" }
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .short
        return "about \(f.string(from: seconds) ?? "") left"
    }

    /// "Running for 42 minutes"
    static func elapsed(since date: Date, now: Date = Date()) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 1
        f.unitsStyle = .full
        return f.string(from: max(60, now.timeIntervalSince(date))) ?? ""
    }
}
