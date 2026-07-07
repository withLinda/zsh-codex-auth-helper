import SwiftUI

enum AppThemeSettings {
    static let presetKey = "appThemePreset"
}

enum AppThemeAppearance: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }
}

enum AppThemeContrast: String, CaseIterable, Identifiable {
    case hard
    case medium
    case soft

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .hard:
            return "Hard"
        case .medium:
            return "Medium"
        case .soft:
            return "Soft"
        }
    }
}

enum AppThemePreset: String, CaseIterable, Identifiable {
    case darkHard = "everforest.dark.hard"
    case darkMedium = "everforest.dark.medium"
    case darkSoft = "everforest.dark.soft"
    case lightHard = "everforest.light.hard"
    case lightMedium = "everforest.light.medium"
    case lightSoft = "everforest.light.soft"

    static let fallback: AppThemePreset = .darkHard

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? Self.fallback
    }

    init(appearance: AppThemeAppearance, contrast: AppThemeContrast) {
        switch (appearance, contrast) {
        case (.dark, .hard):
            self = .darkHard
        case (.dark, .medium):
            self = .darkMedium
        case (.dark, .soft):
            self = .darkSoft
        case (.light, .hard):
            self = .lightHard
        case (.light, .medium):
            self = .lightMedium
        case (.light, .soft):
            self = .lightSoft
        }
    }

    var id: String {
        rawValue
    }

    var appearance: AppThemeAppearance {
        switch self {
        case .darkHard, .darkMedium, .darkSoft:
            return .dark
        case .lightHard, .lightMedium, .lightSoft:
            return .light
        }
    }

    var contrast: AppThemeContrast {
        switch self {
        case .darkHard, .lightHard:
            return .hard
        case .darkMedium, .lightMedium:
            return .medium
        case .darkSoft, .lightSoft:
            return .soft
        }
    }

    var colorScheme: ColorScheme {
        switch appearance {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    var displayName: String {
        "Everforest \(appearance.displayName) \(contrast.displayName)"
    }

    var palette: AppThemeRawPalette {
        switch self {
        case .darkHard:
            return .init(
                bgDim: 0x1E2326,
                bg0: 0x272E33,
                bg1: 0x2E383C,
                bg2: 0x374145,
                bg3: 0x414B50,
                bg4: 0x495156,
                bg5: 0x4F5B58,
                bgVisual: 0x4C3743,
                bgRed: 0x493B40,
                bgYellow: 0x45443C,
                bgGreen: 0x3C4841,
                bgBlue: 0x384B55,
                bgPurple: 0x463F48,
                fg: 0xD3C6AA,
                red: 0xE67E80,
                orange: 0xE69875,
                yellow: 0xDBBC7F,
                green: 0xA7C080,
                aqua: 0x83C092,
                blue: 0x7FBBB3,
                purple: 0xD699B6,
                grey0: 0x7A8478,
                grey1: 0x859289,
                grey2: 0x9DA9A0,
                statusline1: 0xA7C080,
                statusline2: 0xD3C6AA,
                statusline3: 0xE67E80
            )
        case .darkMedium:
            return .init(
                bgDim: 0x232A2E,
                bg0: 0x2D353B,
                bg1: 0x343F44,
                bg2: 0x3D484D,
                bg3: 0x475258,
                bg4: 0x4F585E,
                bg5: 0x56635F,
                bgVisual: 0x543A48,
                bgRed: 0x514045,
                bgYellow: 0x4D4C43,
                bgGreen: 0x425047,
                bgBlue: 0x3A515D,
                bgPurple: 0x4A444E,
                fg: 0xD3C6AA,
                red: 0xE67E80,
                orange: 0xE69875,
                yellow: 0xDBBC7F,
                green: 0xA7C080,
                aqua: 0x83C092,
                blue: 0x7FBBB3,
                purple: 0xD699B6,
                grey0: 0x7A8478,
                grey1: 0x859289,
                grey2: 0x9DA9A0,
                statusline1: 0xA7C080,
                statusline2: 0xD3C6AA,
                statusline3: 0xE67E80
            )
        case .darkSoft:
            return .init(
                bgDim: 0x293136,
                bg0: 0x333C43,
                bg1: 0x3A464C,
                bg2: 0x434F55,
                bg3: 0x4D5960,
                bg4: 0x555F66,
                bg5: 0x5D6B66,
                bgVisual: 0x5C3F4F,
                bgRed: 0x59464C,
                bgYellow: 0x55544A,
                bgGreen: 0x48584E,
                bgBlue: 0x3F5865,
                bgPurple: 0x4E4953,
                fg: 0xD3C6AA,
                red: 0xE67E80,
                orange: 0xE69875,
                yellow: 0xDBBC7F,
                green: 0xA7C080,
                aqua: 0x83C092,
                blue: 0x7FBBB3,
                purple: 0xD699B6,
                grey0: 0x7A8478,
                grey1: 0x859289,
                grey2: 0x9DA9A0,
                statusline1: 0xA7C080,
                statusline2: 0xD3C6AA,
                statusline3: 0xE67E80
            )
        case .lightHard:
            return .init(
                bgDim: 0xF2EFDF,
                bg0: 0xFFFBEF,
                bg1: 0xF8F5E4,
                bg2: 0xF2EFDF,
                bg3: 0xEDEADA,
                bg4: 0xE8E5D5,
                bg5: 0xBEC5B2,
                bgVisual: 0xF0F2D4,
                bgRed: 0xFFE7DE,
                bgYellow: 0xFEF2D5,
                bgGreen: 0xF3F5D9,
                bgBlue: 0xECF5ED,
                bgPurple: 0xFCECED,
                fg: 0x5C6A72,
                red: 0xF85552,
                orange: 0xF57D26,
                yellow: 0xDFA000,
                green: 0x8DA101,
                aqua: 0x35A77C,
                blue: 0x3A94C5,
                purple: 0xDF69BA,
                grey0: 0xA6B0A0,
                grey1: 0x939F91,
                grey2: 0x829181,
                statusline1: 0x93B259,
                statusline2: 0x708089,
                statusline3: 0xE66868
            )
        case .lightMedium:
            return .init(
                bgDim: 0xEFEBD4,
                bg0: 0xFDF6E3,
                bg1: 0xF4F0D9,
                bg2: 0xEFEBD4,
                bg3: 0xE6E2CC,
                bg4: 0xE0DCC7,
                bg5: 0xBDC3AF,
                bgVisual: 0xEAEDC8,
                bgRed: 0xFDE3DA,
                bgYellow: 0xFAEDCD,
                bgGreen: 0xF0F1D2,
                bgBlue: 0xE9F0E9,
                bgPurple: 0xFAE8E2,
                fg: 0x5C6A72,
                red: 0xF85552,
                orange: 0xF57D26,
                yellow: 0xDFA000,
                green: 0x8DA101,
                aqua: 0x35A77C,
                blue: 0x3A94C5,
                purple: 0xDF69BA,
                grey0: 0xA6B0A0,
                grey1: 0x939F91,
                grey2: 0x829181,
                statusline1: 0x93B259,
                statusline2: 0x708089,
                statusline3: 0xE66868
            )
        case .lightSoft:
            return .init(
                bgDim: 0xE5DFC5,
                bg0: 0xF3EAD3,
                bg1: 0xEAE4CA,
                bg2: 0xE5DFC5,
                bg3: 0xDDD8BE,
                bg4: 0xD8D3BA,
                bg5: 0xB9C0AB,
                bgVisual: 0xE1E4BD,
                bgRed: 0xFADBD0,
                bgYellow: 0xF1E4C5,
                bgGreen: 0xE5E6C5,
                bgBlue: 0xE1E7DD,
                bgPurple: 0xF1DDD4,
                fg: 0x5C6A72,
                red: 0xF85552,
                orange: 0xF57D26,
                yellow: 0xDFA000,
                green: 0x8DA101,
                aqua: 0x35A77C,
                blue: 0x3A94C5,
                purple: 0xDF69BA,
                grey0: 0xA6B0A0,
                grey1: 0x939F91,
                grey2: 0x829181,
                statusline1: 0x93B259,
                statusline2: 0x708089,
                statusline3: 0xE66868
            )
        }
    }

    var semanticColors: AppThemeSemanticColors {
        let palette = palette
        switch appearance {
        case .dark:
            let railSurface = contrast == .hard ? palette.bgDim : palette.bg0
            let raisedSurface = contrast == .hard ? palette.bg0 : palette.bg1
            let fieldSurface = contrast == .hard ? palette.bg0 : palette.bg2

            return AppThemeSemanticColors(
                appBackground: palette.bgDim,
                railSurface: railSurface,
                panelSurface: palette.bg0,
                nestedSurface: raisedSurface,
                fieldSurface: fieldSurface,
                chromeSurface: raisedSurface,
                terminalBackground: palette.bgDim,
                primaryText: palette.fg,
                secondaryText: palette.grey2,
                supportText: palette.grey2,
                mutedText: palette.grey1,
                disabledText: palette.grey0,
                border: darkBorderColor(from: palette),
                focusBorder: palette.grey2,
                accent: palette.orange,
                onAccentText: 0x1E2326,
                warning: palette.yellow,
                destructive: palette.red,
                success: palette.aqua,
                info: palette.blue
            )
        case .light:
            return AppThemeSemanticColors(
                appBackground: palette.bgDim,
                railSurface: palette.bg0,
                panelSurface: palette.bg0,
                nestedSurface: palette.bg1,
                fieldSurface: palette.bg1,
                chromeSurface: palette.bg1,
                terminalBackground: palette.bgDim,
                primaryText: strongLightText,
                secondaryText: palette.fg,
                supportText: palette.fg,
                mutedText: palette.grey2,
                disabledText: palette.grey1,
                border: lightBorderColor(from: palette),
                focusBorder: palette.fg,
                accent: palette.orange,
                onAccentText: 0x1E2326,
                warning: palette.fg,
                destructive: palette.fg,
                success: palette.fg,
                info: palette.fg
            )
        }
    }

    private var strongLightText: UInt32 {
        switch contrast {
        case .hard:
            return 0x1E2326
        case .medium:
            return 0x232A2E
        case .soft:
            return 0x293136
        }
    }

    private func darkBorderColor(from palette: AppThemeRawPalette) -> UInt32 {
        switch contrast {
        case .hard:
            return palette.bg1
        case .medium:
            return palette.grey2
        case .soft:
            return palette.grey2
        }
    }

    private func lightBorderColor(from palette: AppThemeRawPalette) -> UInt32 {
        switch contrast {
        case .hard:
            return palette.grey2
        case .medium:
            return palette.grey1
        case .soft:
            return palette.fg
        }
    }
}

struct AppThemeRawPalette: Equatable {
    let bgDim: UInt32
    let bg0: UInt32
    let bg1: UInt32
    let bg2: UInt32
    let bg3: UInt32
    let bg4: UInt32
    let bg5: UInt32
    let bgVisual: UInt32
    let bgRed: UInt32
    let bgYellow: UInt32
    let bgGreen: UInt32
    let bgBlue: UInt32
    let bgPurple: UInt32
    let fg: UInt32
    let red: UInt32
    let orange: UInt32
    let yellow: UInt32
    let green: UInt32
    let aqua: UInt32
    let blue: UInt32
    let purple: UInt32
    let grey0: UInt32
    let grey1: UInt32
    let grey2: UInt32
    let statusline1: UInt32
    let statusline2: UInt32
    let statusline3: UInt32
}

struct AppThemeSemanticColors: Equatable {
    let appBackground: UInt32
    let railSurface: UInt32
    let panelSurface: UInt32
    let nestedSurface: UInt32
    let fieldSurface: UInt32
    let chromeSurface: UInt32
    let terminalBackground: UInt32
    let primaryText: UInt32
    let secondaryText: UInt32
    let supportText: UInt32
    let mutedText: UInt32
    let disabledText: UInt32
    let border: UInt32
    let focusBorder: UInt32
    let accent: UInt32
    let onAccentText: UInt32
    let warning: UInt32
    let destructive: UInt32
    let success: UInt32
    let info: UInt32
}

enum ThemeTokens {
    enum Colors {
        static var currentPreset: AppThemePreset {
            AppThemePreset(storedValue: UserDefaults.standard.string(forKey: AppThemeSettings.presetKey))
        }

        static var currentSemanticColors: AppThemeSemanticColors {
            currentPreset.semanticColors
        }

        static var appBackground: Color {
            color(\.appBackground)
        }

        static var railSurface: Color {
            color(\.railSurface)
        }

        static var panelSurface: Color {
            color(\.panelSurface)
        }

        static var nestedSurface: Color {
            color(\.nestedSurface)
        }

        static var fieldSurface: Color {
            color(\.fieldSurface)
        }

        static var chromeSurface: Color {
            color(\.chromeSurface)
        }

        static var primaryText: Color {
            color(\.primaryText)
        }

        static var primaryTextHex: UInt32 {
            currentSemanticColors.primaryText
        }

        static var secondaryText: Color {
            color(\.secondaryText)
        }

        static var supportText: Color {
            color(\.supportText)
        }

        static var mutedText: Color {
            color(\.mutedText)
        }

        static var disabledText: Color {
            color(\.disabledText)
        }

        static var disabledTextHex: UInt32 {
            currentSemanticColors.disabledText
        }

        static var border: Color {
            color(\.border)
        }

        static var focusBorder: Color {
            color(\.focusBorder)
        }

        static var accent: Color {
            color(\.accent)
        }

        static var onAccentText: Color {
            color(\.onAccentText)
        }

        static var warning: Color {
            color(\.warning)
        }

        static var destructive: Color {
            color(\.destructive)
        }

        static var success: Color {
            color(\.success)
        }

        static var info: Color {
            color(\.info)
        }

        static var terminalBackground: Color {
            color(\.terminalBackground)
        }

        private static func color(_ keyPath: KeyPath<AppThemeSemanticColors, UInt32>) -> Color {
            Color(hex: currentSemanticColors[keyPath: keyPath])
        }
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

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
