import SwiftUI

/// The Android app's palette, at tvOS's 1920×1080 points (about twice the Fire TV stick's dp).
enum Theme {
    static let background = Color(red: 0x0D / 255, green: 0x0B / 255, blue: 0x14 / 255)
    static let surface = Color(red: 0x1A / 255, green: 0x16 / 255, blue: 0x26 / 255)
    static let surfaceHigh = Color(red: 0x26 / 255, green: 0x20 / 255, blue: 0x36 / 255)
    static let text = Color(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xFA / 255)
    static let textDim = Color(red: 0xA5 / 255, green: 0x9D / 255, blue: 0xB8 / 255)
    static let pink = Color(red: 1, green: 0x4F / 255, blue: 0xA3 / 255)
    static let orange = Color(red: 1, green: 0x9A / 255, blue: 0x3D / 255)
    static let accent = LinearGradient(colors: [pink, orange], startPoint: .leading, endPoint: .trailing)
}

struct KeyChip: View {
    let key: Int
    var big = false

    var body: some View {
        Text(Key.label(key))
            .font(.system(size: big ? 44 : 28, weight: .bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, big ? 36 : 20)
            .padding(.vertical, big ? 12 : 6)
            .background(Theme.surfaceHigh, in: Capsule())
    }
}

/// Centered pill for key changes and notices.
struct NoticeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 56, weight: .bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 56)
            .padding(.vertical, 24)
            .background(Theme.surface.opacity(0.92), in: Capsule())
    }
}
