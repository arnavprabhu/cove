import SwiftUI

/// Small screen glyph used in the Virtual Machines sidebar list.
struct VMGlyph: View {
    var isLive: Bool
    var selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(selected ? Color.white : Theme.textSecondary, lineWidth: 1.5)
                .frame(width: 34, height: 24)
            RoundedRectangle(cornerRadius: 2)
                .fill(isLive ? Color(hex: 0x5E8BD6) : Color(hex: 0x545458))
                .frame(width: 20, height: 12)
        }
        .frame(width: 34, height: 24)
        .accessibilityHidden(true)
    }
}
