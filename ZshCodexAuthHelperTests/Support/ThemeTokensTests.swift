import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct ThemeTokensTests {
    @Test func everforestPresetCatalogHasEveryAppearanceAndContrastPair() {
        #expect(AppThemePreset.allCases == [
            .darkHard,
            .darkMedium,
            .darkSoft,
            .lightHard,
            .lightMedium,
            .lightSoft
        ])

        #expect(AppThemePreset(appearance: .dark, contrast: .hard) == .darkHard)
        #expect(AppThemePreset(appearance: .dark, contrast: .medium) == .darkMedium)
        #expect(AppThemePreset(appearance: .dark, contrast: .soft) == .darkSoft)
        #expect(AppThemePreset(appearance: .light, contrast: .hard) == .lightHard)
        #expect(AppThemePreset(appearance: .light, contrast: .medium) == .lightMedium)
        #expect(AppThemePreset(appearance: .light, contrast: .soft) == .lightSoft)
    }

    @Test func invalidStoredThemeFallsBackToDarkHard() {
        #expect(AppThemePreset(storedValue: nil) == .darkHard)
        #expect(AppThemePreset(storedValue: "unknown-theme") == .darkHard)
    }

    @Test func presetPalettesKeepRequestedRawColorsAndAccents() {
        #expect(AppThemePreset.darkHard.palette.bg0 == 0x272E33)
        #expect(AppThemePreset.darkHard.palette.fg == 0xD3C6AA)
        #expect(AppThemePreset.darkHard.palette.orange == 0xE69875)
        #expect(AppThemePreset.darkHard.palette.aqua == 0x83C092)
        #expect(AppThemePreset.darkHard.palette.statusline3 == 0xE67E80)

        #expect(AppThemePreset.lightSoft.palette.bg0 == 0xF3EAD3)
        #expect(AppThemePreset.lightSoft.palette.fg == 0x5C6A72)
        #expect(AppThemePreset.lightSoft.palette.orange == 0xF57D26)
        #expect(AppThemePreset.lightSoft.palette.purple == 0xDF69BA)
        #expect(AppThemePreset.lightSoft.palette.statusline1 == 0x93B259)
    }

    @Test func cardSurfacesUseBg0ForEveryPreset() {
        for preset in AppThemePreset.allCases {
            #expect(preset.semanticColors.panelSurface == preset.palette.bg0)
        }
    }

    @Test func darkHardCalmSurfacesUseOnlyBgDimAndBg0() {
        let palette = AppThemePreset.darkHard.palette
        let colors = AppThemePreset.darkHard.semanticColors

        #expect(colors.appBackground == palette.bgDim)
        #expect(colors.terminalBackground == palette.bgDim)
        #expect(colors.railSurface == palette.bgDim)

        #expect(colors.panelSurface == palette.bg0)
        #expect(colors.nestedSurface == palette.bg0)
        #expect(colors.fieldSurface == palette.bg0)
        #expect(colors.chromeSurface == palette.bg0)
        #expect(colors.border == palette.bg1)
    }

    @Test func textTokensPassWCAGAndDeltaLStarOnCardSurface() {
        for preset in AppThemePreset.allCases {
            let colors = preset.semanticColors
            let requiredTextRoles = [
                colors.primaryText,
                colors.secondaryText,
                colors.supportText
            ]

            for role in requiredTextRoles {
                #expect(ThemeContrastAudit.contrastRatio(foreground: role, background: colors.panelSurface) >= 4.5)
                #expect(ThemeContrastAudit.deltaLStar(foreground: role, background: colors.panelSurface) >= 40)
            }
        }
    }

    @Test func onAccentTextPassesWCAGOnPrimaryAccent() {
        for preset in AppThemePreset.allCases {
            let colors = preset.semanticColors
            #expect(ThemeContrastAudit.contrastRatio(foreground: colors.onAccentText, background: colors.accent) >= 4.5)
        }
    }

    @Test func semanticAccentRolesUseRequestedPaletteAccentsAndTints() {
        for preset in AppThemePreset.allCases {
            let palette = preset.palette
            let colors = preset.semanticColors

            #expect(colors.accent == palette.orange)
            #expect(colors.accentSurface == palette.bgYellow)
            #expect(colors.warningAccent == palette.yellow)
            #expect(colors.warningSurface == palette.bgYellow)
            #expect(colors.destructiveAccent == palette.red)
            #expect(colors.destructiveSurface == palette.bgRed)
            #expect(colors.successAccent == palette.aqua)
            #expect(colors.successSurface == palette.bgGreen)
            #expect(colors.infoAccent == palette.blue)
            #expect(colors.infoSurface == palette.bgBlue)
            #expect(colors.purpleAccent == palette.purple)
            #expect(colors.purpleSurface == palette.bgPurple)
        }
    }

    @Test func coloredSurfaceTextPassesWCAGAndDeltaLStarOnTintedSurfaces() {
        for preset in AppThemePreset.allCases {
            let colors = preset.semanticColors
            let tintedSurfaces = [
                colors.accentSurface,
                colors.warningSurface,
                colors.destructiveSurface,
                colors.successSurface,
                colors.infoSurface,
                colors.purpleSurface
            ]

            for surface in tintedSurfaces {
                #expect(ThemeContrastAudit.contrastRatio(foreground: colors.coloredSurfaceText, background: surface) >= 4.5)
                #expect(ThemeContrastAudit.deltaLStar(foreground: colors.coloredSurfaceText, background: surface) >= 40)
            }
        }
    }
}

private enum ThemeContrastAudit {
    static func contrastRatio(foreground: UInt32, background: UInt32) -> Double {
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func deltaLStar(foreground: UInt32, background: UInt32) -> Double {
        abs(lStar(foreground) - lStar(background))
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        let rgb = rgbComponents(hex)
        return 0.2126 * linearSRGB(rgb.red) +
            0.7152 * linearSRGB(rgb.green) +
            0.0722 * linearSRGB(rgb.blue)
    }

    private static func lStar(_ hex: UInt32) -> Double {
        let rgb = rgbComponents(hex)
        let y = 0.2126729 * linearSRGB(rgb.red) +
            0.7151522 * linearSRGB(rgb.green) +
            0.0721750 * linearSRGB(rgb.blue)
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        let f = y > epsilon ? pow(y, 1.0 / 3.0) : ((kappa * y) + 16.0) / 116.0
        return (116.0 * f) - 16.0
    }

    private static func linearSRGB(_ channel: Double) -> Double {
        let value = channel / 255.0
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private static func rgbComponents(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (
            red: Double((hex >> 16) & 0xFF),
            green: Double((hex >> 8) & 0xFF),
            blue: Double(hex & 0xFF)
        )
    }
}
