import SwiftUI

enum ThemeTokens {
    enum Colors {
        static let appBackground = Color(hex: 0x1E2326)
        static let railSurface = Color(hex: 0x272E33)
        static let panelSurface = Color(hex: 0x2E383C)
        static let nestedSurface = Color(hex: 0x374145)
        static let fieldSurface = Color(hex: 0x1E2326)
        static let primaryText = Color(hex: 0xD3C6AA)
        static let secondaryText = Color(hex: 0x9DA9A0)
        static let supportText = Color(hex: 0x859289)
        static let mutedText = Color(hex: 0x7A8478)
        static let border = Color(hex: 0x414B50)
        static let accent = Color(hex: 0xE69875)
        static let warning = Color(hex: 0xDBBC7F)
        static let destructive = Color(hex: 0xE67E80)
        static let success = Color(hex: 0x83C092)
        static let info = Color(hex: 0x7FBBB3)
        static let terminalBackground = Color(hex: 0x1E2326)
    }

    enum Spacing {
        static let tight: CGFloat = 8
        static let normal: CGFloat = 12
        static let group: CGFloat = 16
        static let section: CGFloat = 24
    }

    enum Radius {
        static let panel: CGFloat = 16
        static let nested: CGFloat = 12
        static let field: CGFloat = 10
        static let button: CGFloat = 10
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

