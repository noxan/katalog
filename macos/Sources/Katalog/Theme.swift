import SwiftUI

// Nord palette — restrained, cool, one frost accent. Zen by omission.
enum Theme {
    static let bg = Color(red: 0.180, green: 0.204, blue: 0.251)      // nord0
    static let surface = Color(red: 0.231, green: 0.259, blue: 0.322) // nord1
    static let text = Color(red: 0.925, green: 0.937, blue: 0.957)    // nord6
    static let subtle = Color(red: 0.616, green: 0.663, blue: 0.741)  // nord4-ish
    static let accent = Color(red: 0.533, green: 0.753, blue: 0.816)  // nord8 frost

    static let spacing: CGFloat = 20
    static let radius: CGFloat = 10
    static let coverWidth: CGFloat = 150
}
