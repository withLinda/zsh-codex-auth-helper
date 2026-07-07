import SwiftUI

struct CodexResourceSettingsView: View {
    @AppStorage(CodexResourceSettings.userDefaultsKey) private var codexResourceDirectory = CodexResourceSettings.defaultDirectory
    @AppStorage(CodexAuthToolSettings.releaseChannelKey) private var codexAuthReleaseChannelRaw = CodexAuthReleaseChannel.stable.rawValue
    @AppStorage(AppThemeSettings.presetKey) private var appThemePresetRaw = AppThemePreset.fallback.rawValue

    private let codexAuthToolManager = CodexAuthToolManager.live()

    private var normalizedDirectory: String {
        CodexResourceSettings.normalizedDirectory(codexResourceDirectory)
    }

    private var selectedCodexAuthReleaseChannel: CodexAuthReleaseChannel {
        CodexAuthReleaseChannel(storedValue: codexAuthReleaseChannelRaw)
    }

    private var selectedThemePreset: AppThemePreset {
        AppThemePreset(storedValue: appThemePresetRaw)
    }

    private var appearanceBinding: Binding<AppThemeAppearance> {
        Binding {
            selectedThemePreset.appearance
        } set: { newAppearance in
            appThemePresetRaw = AppThemePreset(
                appearance: newAppearance,
                contrast: selectedThemePreset.contrast
            ).rawValue
        }
    }

    private var contrastBinding: Binding<AppThemeContrast> {
        Binding {
            selectedThemePreset.contrast
        } set: { newContrast in
            appThemePresetRaw = AppThemePreset(
                appearance: selectedThemePreset.appearance,
                contrast: newContrast
            ).rawValue
        }
    }

    private var codexExecutablePath: String {
        CodexResourceSettings.codexExecutablePath(in: codexResourceDirectory)
    }

    private var codexExecutableExists: Bool {
        FileManager.default.isExecutableFile(atPath: codexExecutablePath)
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: appearanceBinding) {
                    ForEach(AppThemeAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Contrast", selection: contrastBinding) {
                    ForEach(AppThemeContrast.allCases) { contrast in
                        Text(contrast.displayName).tag(contrast)
                    }
                }
                .pickerStyle(.segmented)

                ThemePreviewStrip(preset: selectedThemePreset)
            } header: {
                Text("Theme")
            }

            Section {
                VStack(alignment: .leading, spacing: ThemeTokens.Spacing.tight) {
                    Text("Codex resources path")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ThemeTokens.Colors.supportText)

                    TextField("Codex resources path", text: $codexResourceDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Default: \(CodexResourceSettings.defaultDirectory)")
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.Colors.secondaryText)

                    Spacer()

                    Button("Reset") {
                        codexResourceDirectory = CodexResourceSettings.defaultDirectory
                    }
                }

                if codexExecutableExists == false {
                    Label {
                        Text("No runnable codex file found at \(codexExecutablePath). Login will try codex from PATH instead.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.Colors.warning)
                }
            } header: {
                Text("Codex")
            } footer: {
                if normalizedDirectory != codexResourceDirectory {
                    Text("Using \(normalizedDirectory)")
                }
            }

            Section {
                Picker("Update channel", selection: $codexAuthReleaseChannelRaw) {
                    ForEach(CodexAuthReleaseChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: ThemeTokens.Spacing.tight) {
                    Text(selectedCodexAuthReleaseChannel.detail)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.Colors.secondaryText)

                    Text("The app installs codex-auth into \(codexAuthToolManager.toolRoot.path). The app uses this copy before global PATH.")
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.Colors.secondaryText)
                        .textSelection(.enabled)
                }
            } header: {
                Text("codex-auth")
            }
        }
        .formStyle(.grouped)
        .padding(ThemeTokens.Spacing.section)
        .frame(width: 560)
        .background(ThemeTokens.Colors.appBackground)
    }
}

private struct ThemePreviewStrip: View {
    let preset: AppThemePreset

    private var colors: AppThemeSemanticColors {
        preset.semanticColors
    }

    private var palette: AppThemeRawPalette {
        preset.palette
    }

    var body: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            previewSwatch(colors.panelSurface)
            previewSwatch(colors.fieldSurface)
            previewSwatch(palette.orange)
            previewSwatch(palette.yellow)
            previewSwatch(palette.aqua)
            previewSwatch(palette.blue)
            previewSwatch(palette.red)
            previewSwatch(palette.purple)
        }
        .padding(ThemeTokens.Spacing.tight)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color(hex: colors.panelSurface))
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.field, style: .continuous)
                .stroke(Color(hex: colors.border), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preset.displayName)
    }

    private func previewSwatch(_ hex: UInt32) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: hex))
            .frame(width: 34, height: 20)
    }
}
