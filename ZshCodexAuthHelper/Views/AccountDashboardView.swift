import SwiftUI

struct AccountDashboardView: View {
    @ObservedObject var store: AccountListStore

    let isRunning: Bool
    let refresh: () -> Void
    let switchAccount: (AccountListItem) -> Void
    let requestRemove: (AccountListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(ThemeTokens.Colors.border)

            content
        }
        .background(ThemeTokens.Colors.panelSurface)
    }

    private var header: some View {
        HStack(spacing: ThemeTokens.Spacing.normal) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved Accounts")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Colors.primaryText)

                Text(accountCountText)
                    .font(.callout)
                    .foregroundStyle(ThemeTokens.Colors.secondaryText)
            }

            Spacer()

            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(AccountHeaderButtonStyle(tint: ThemeTokens.Colors.info))
            .disabled(isRunning)
            .help("Refresh saved accounts")
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.group)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            AccountEmptyStateView(
                systemImage: "hourglass",
                title: "Loading accounts",
                detail: "Reading local registry."
            )
        case .missingRegistry:
            AccountEmptyStateView(
                systemImage: "tray",
                title: "No account list found",
                detail: "No saved registry exists yet."
            )
        case .unreadableRegistry:
            AccountEmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Account list unreadable",
                detail: "The registry file could not be read."
            )
        case .empty:
            AccountEmptyStateView(
                systemImage: "person.crop.circle.badge.questionmark",
                title: "No saved accounts",
                detail: "The saved account list is empty."
            )
        case .loaded(let items):
            ScrollView {
                LazyVStack(spacing: ThemeTokens.Spacing.tight) {
                    ForEach(items) { item in
                        AccountRowView(
                            item: item,
                            isRunning: isRunning,
                            switchAccount: switchAccount,
                            requestRemove: requestRemove
                        )
                    }
                }
                .padding(ThemeTokens.Spacing.group)
            }
            .background(ThemeTokens.Colors.terminalBackground)
        }
    }

    private var accountCountText: String {
        switch store.state {
        case .loaded(let items):
            return "\(items.count) saved account\(items.count == 1 ? "" : "s")"
        case .empty:
            return "0 saved accounts"
        case .missingRegistry:
            return "No registry"
        case .unreadableRegistry:
            return "Needs attention"
        case .loading:
            return "Loading"
        }
    }
}

private struct AccountRowView: View {
    let item: AccountListItem
    let isRunning: Bool
    let switchAccount: (AccountListItem) -> Void
    let requestRemove: (AccountListItem) -> Void

    var body: some View {
        HStack(spacing: ThemeTokens.Spacing.normal) {
            Text("\(item.rowNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThemeTokens.Colors.supportText)
                .frame(width: 28, alignment: .center)

            Image(systemName: item.isActive ? "checkmark.circle.fill" : "person.crop.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.isActive ? ThemeTokens.Colors.success : ThemeTokens.Colors.info)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: ThemeTokens.Spacing.tight) {
                    Text(item.email)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ThemeTokens.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    if item.isActive {
                        AccountStatusBadge(title: "Active", systemImage: "checkmark.circle.fill", tint: ThemeTokens.Colors.success)
                    }
                }

                HStack(spacing: ThemeTokens.Spacing.tight) {
                    AccountStatusBadge(title: item.planLabel, systemImage: item.isAPIKeyAccount ? "key.fill" : "creditcard", tint: ThemeTokens.Colors.warning)

                    ForEach(item.subtitleParts, id: \.self) { part in
                        Text(part)
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ThemeTokens.Spacing.tight) {
                if item.isActive {
                    AccountStatusBadge(title: "Current", systemImage: "checkmark", tint: ThemeTokens.Colors.success)
                        .frame(width: 92, alignment: .center)
                } else {
                    Button {
                        switchAccount(item)
                    } label: {
                        Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(AccountRowButtonStyle(tint: ThemeTokens.Colors.info))
                    .disabled(isRunning)
                    .accessibilityLabel("Switch account")
                    .accessibilityHint("Switch to this saved account.")
                    .help("Switch to \(item.email)")
                    .frame(width: 92)
                }

                Button {
                    requestRemove(item)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(AccountRowButtonStyle(tint: ThemeTokens.Colors.destructive))
                .disabled(isRunning)
                .accessibilityLabel("Remove account")
                .accessibilityHint("Show a confirmation before removing this saved account.")
                .help("Remove \(item.email)")
                .frame(width: 96)
            }
            .frame(width: 200, alignment: .trailing)
        }
        .padding(.horizontal, ThemeTokens.Spacing.group)
        .padding(.vertical, ThemeTokens.Spacing.normal)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.nested, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.nested, style: .continuous)
                .stroke(item.isActive ? ThemeTokens.Colors.success.opacity(0.45) : ThemeTokens.Colors.border, lineWidth: 1)
        }
    }

    private var rowBackground: Color {
        item.isActive
            ? ThemeTokens.Colors.nestedSurface.opacity(0.95)
            : ThemeTokens.Colors.panelSurface
    }
}

private struct AccountStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, ThemeTokens.Spacing.tight)
            .padding(.vertical, 4)
            .background(ThemeTokens.Colors.fieldSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            }
    }
}

private struct AccountEmptyStateView: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: ThemeTokens.Spacing.normal) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ThemeTokens.Colors.info)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ThemeTokens.Colors.primaryText)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(ThemeTokens.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeTokens.Colors.terminalBackground)
    }
}

private struct AccountHeaderButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(ThemeTokens.Colors.primaryText)
            .padding(.horizontal, ThemeTokens.Spacing.normal)
            .frame(minHeight: 36)
            .background(tint.opacity(configuration.isPressed ? 0.24 : 0.16))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct AccountRowButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, ThemeTokens.Spacing.tight)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(tint.opacity(configuration.isPressed ? 0.22 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ThemeTokens.Radius.button, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}
