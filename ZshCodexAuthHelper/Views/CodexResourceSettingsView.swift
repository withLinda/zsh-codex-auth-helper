import SwiftUI

struct CodexResourceSettingsView: View {
    @AppStorage(CodexResourceSettings.userDefaultsKey) private var codexResourceDirectory = CodexResourceSettings.defaultDirectory

    private var normalizedDirectory: String {
        CodexResourceSettings.normalizedDirectory(codexResourceDirectory)
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
        }
        .formStyle(.grouped)
        .padding(ThemeTokens.Spacing.section)
        .frame(width: 560)
    }
}
