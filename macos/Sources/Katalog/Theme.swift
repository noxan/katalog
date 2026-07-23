import SwiftUI

// System semantic colors — follow the OS light/dark theme.
enum Theme {
    static let bg = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .underPageBackgroundColor)
    static let text = Color.primary
    static let subtle = Color.secondary
    static let accent = Color.accentColor

    static let spacing: CGFloat = 20
    static let radius: CGFloat = 10
    static let coverWidth: CGFloat = 150
    static let coverHeight: CGFloat = coverWidth * 1.5
}
