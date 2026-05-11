import AppKit
import SwiftUI

struct TerminalPanelView: View {
    @ObservedObject var store: TerminalTranscriptStore
    @ObservedObject var runner: CommandRunner

    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader

            Divider()
                .overlay(ThemeTokens.Colors.border)

            terminalBody

            Divider()
                .overlay(ThemeTokens.Colors.border)

            inputBar
        }
        .background(ThemeTokens.Colors.panelSurface)
    }

    private var terminalHeader: some View {
        HStack(spacing: ThemeTokens.Spacing.normal) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Terminal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Colors.primaryText)

                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if let url = store.latestURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open Link", systemImage: "safari")
                }
                .buttonStyle(ToolbarButtonStyle(tint: ThemeTokens.Colors.accent))
            }

            Button {
                runner.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(ToolbarButtonStyle(tint: ThemeTokens.Colors.destructive))
            .disabled(runner.isRunning == false)

            Button {
                store.clear()
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .buttonStyle(ToolbarButtonStyle(tint: ThemeTokens.Colors.info))
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.group)
        .background(.regularMaterial)
    }

    private var terminalBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.transcript.isEmpty ? "Output will appear here." : store.transcript)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(store.transcript.isEmpty ? ThemeTokens.Colors.mutedText : ThemeTokens.Colors.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(ThemeTokens.Spacing.group)

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
            }
            .background(ThemeTokens.Colors.terminalBackground)
            .onChange(of: store.transcript) { _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: ThemeTokens.Spacing.normal) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(runner.isRunning ? ThemeTokens.Colors.accent : ThemeTokens.Colors.mutedText)

            TextField("Type input for the running command", text: $input)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(ThemeTokens.Colors.primaryText)
                .disabled(runner.isRunning == false)
                .onSubmit(sendInput)

            Button {
                sendInput()
            } label: {
                Image(systemName: "paperplane.fill")
                    .accessibilityLabel("Send input")
            }
            .buttonStyle(.plain)
            .foregroundStyle(runner.isRunning ? ThemeTokens.Colors.accent : ThemeTokens.Colors.mutedText)
            .frame(width: 34, height: 34)
            .disabled(runner.isRunning == false || input.isEmpty)
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.normal)
        .background(ThemeTokens.Colors.panelSurface)
    }

    private var statusText: String {
        if let runningTitle = store.runningCommandTitle {
            return "Running \(runningTitle)"
        }

        if let exitCode = store.lastExitCode {
            return exitCode == 0 ? "Last command finished" : "Last command exited with \(exitCode)"
        }

        return "No command running"
    }

    private var statusColor: Color {
        if store.runningCommandTitle != nil {
            return ThemeTokens.Colors.warning
        }

        if let exitCode = store.lastExitCode {
            return exitCode == 0 ? ThemeTokens.Colors.success : ThemeTokens.Colors.destructive
        }

        return ThemeTokens.Colors.secondaryText
    }

    private func sendInput() {
        guard input.isEmpty == false else {
            return
        }

        runner.sendInput(input + "\n")
        input = ""
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(ThemeTokens.Colors.primaryText)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, ThemeTokens.Spacing.normal)
            .frame(minHeight: 34)
            .background(tint.opacity(configuration.isPressed ? 0.28 : 0.16))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.button, style: .continuous))
    }
}

