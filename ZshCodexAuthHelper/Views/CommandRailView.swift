import SwiftUI

struct CommandRailView: View {
    @Binding var alias: String
    @Binding var authFilePath: String

    let authSession: AuthSessionInfo
    let isRunning: Bool
    let runLogin: () -> Void
    let runImport: () -> Void
    let runSwitch: () -> Void
    let runRestart: () -> Void
    let runList: () -> Void
    let requestRemove: () -> Void

    private var canImport: Bool {
        alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        authFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeTokens.Spacing.section) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Codex Auth")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Colors.primaryText)

                Text(isRunning ? "Command running" : "Ready")
                    .font(.callout)
                    .foregroundStyle(isRunning ? ThemeTokens.Colors.warning : ThemeTokens.Colors.secondaryText)
            }

            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.normal) {
                Text("Import")
                    .font(.headline)
                    .foregroundStyle(ThemeTokens.Colors.primaryText)

                VStack(alignment: .leading, spacing: ThemeTokens.Spacing.tight) {
                    AuthSessionIndicatorView(info: authSession)
                    LabeledTextField(title: "Alias", text: $alias)
                    LabeledTextField(title: "Auth file", text: $authFilePath, monospaced: true)
                }

                CommandButton(
                    title: "Import Auth",
                    systemImage: "tray.and.arrow.down",
                    tint: ThemeTokens.Colors.accent,
                    action: runImport
                )
                .disabled(isRunning || canImport == false)
            }

            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.normal) {
                Text("Commands")
                    .font(.headline)
                    .foregroundStyle(ThemeTokens.Colors.primaryText)

                CommandButton(title: "Login", systemImage: "person.crop.circle.badge.plus", action: runLogin)
                CommandButton(title: "Switch Account", systemImage: "arrow.triangle.2.circlepath", action: runSwitch)
                CommandButton(title: "Restart Codex", systemImage: "power", tint: ThemeTokens.Colors.warning, action: runRestart)
                CommandButton(title: "List Accounts", systemImage: "list.bullet.rectangle", action: runList)
            }
            .disabled(isRunning)

            Spacer(minLength: ThemeTokens.Spacing.group)

            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.normal) {
                Divider()
                    .overlay(ThemeTokens.Colors.border)

                CommandButton(
                    title: "Remove Account",
                    systemImage: "trash",
                    tint: ThemeTokens.Colors.destructive,
                    action: requestRemove
                )
                .disabled(isRunning)
            }
        }
        .padding(ThemeTokens.Spacing.section)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(ThemeTokens.Colors.railSurface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ThemeTokens.Colors.border)
                .frame(width: 1)
        }
    }
}

private struct AuthSessionIndicatorView: View {
    let info: AuthSessionInfo

    var body: some View {
        HStack(spacing: ThemeTokens.Spacing.normal) {
            Image(systemName: info.needsAttention ? "exclamationmark.triangle" : "person.crop.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(info.needsAttention ? ThemeTokens.Colors.warning : ThemeTokens.Colors.info)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(ThemeTokens.Colors.primaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .layoutPriority(1)

                Text(info.detail)
                    .font(.caption)
                    .foregroundStyle(info.needsAttention ? ThemeTokens.Colors.warning : ThemeTokens.Colors.supportText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ThemeTokens.Spacing.normal)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(ThemeTokens.Colors.fieldSurface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.field, style: .continuous)
                .stroke(info.needsAttention ? ThemeTokens.Colors.warning.opacity(0.55) : ThemeTokens.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Auth account")
        .accessibilityValue("\(info.title), \(info.detail)")
    }
}

private struct LabeledTextField: View {
    let title: String
    @Binding var text: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ThemeTokens.Colors.supportText)

            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(ThemeTokens.Colors.primaryText)
                .padding(.horizontal, ThemeTokens.Spacing.normal)
                .frame(minHeight: 38)
                .background(ThemeTokens.Colors.fieldSurface)
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ThemeTokens.Radius.field, style: .continuous)
                        .stroke(ThemeTokens.Colors.border, lineWidth: 1)
                }
        }
    }
}

private struct CommandButton: View {
    let title: String
    let systemImage: String
    var tint = ThemeTokens.Colors.info
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThemeTokens.Spacing.normal) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)

                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(ThemeTokens.Colors.primaryText)

                Spacer()
            }
            .padding(.horizontal, ThemeTokens.Spacing.normal)
            .frame(minHeight: 44)
            .background(ThemeTokens.Colors.nestedSurface)
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .opacity(0.95)
    }
}
