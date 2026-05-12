import AppKit
import SwiftUI

struct TerminalPanelView: View {
    @ObservedObject var store: TerminalTranscriptStore
    @ObservedObject var runner: CommandRunner
    @Binding var input: String

    let focusRequest: Int
    let submitDraft: (String) -> Void

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
            .onChange(of: store.transcript) { _, _ in
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
                .foregroundStyle(canSendInput ? ThemeTokens.Colors.accent : ThemeTokens.Colors.mutedText)

            TerminalInputTextField(
                text: $input,
                placeholder: inputPlaceholder,
                focusRequest: focusRequest,
                onSubmit: sendInput
            )
            .frame(minHeight: 22)

            Button {
                sendInput()
            } label: {
                Image(systemName: "paperplane.fill")
                    .accessibilityLabel("Send input")
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSendInput ? ThemeTokens.Colors.accent : ThemeTokens.Colors.mutedText)
            .frame(width: 34, height: 34)
            .disabled(canSendInput == false)
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.normal)
        .background(ThemeTokens.Colors.panelSurface)
    }

    private var inputPlaceholder: String {
        if runner.isRunning {
            return "Type input for the running command"
        }

        return "Use Switch or Remove, then add an alias"
    }

    private var canSendInput: Bool {
        if runner.isRunning {
            return input.isEmpty == false
        }

        return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
        guard canSendInput else {
            return
        }

        if runner.isRunning {
            runner.sendInput(input + "\n")
            input = ""
        } else {
            submitDraft(input)
        }
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

private struct TerminalInputTextField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let focusRequest: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byClipping
        textField.font = Self.font
        textField.textColor = Self.textColor
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }

        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: Self.placeholderColor,
                .font: Self.font
            ]
        )

        guard context.coordinator.lastFocusRequest != focusRequest else {
            return
        }

        context.coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            Self.placeCursorAtEnd(of: textField)

            DispatchQueue.main.async {
                Self.placeCursorAtEnd(of: textField)
            }
        }
    }

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let textColor = NSColor(
        red: CGFloat(0xD3) / 255.0,
        green: CGFloat(0xC6) / 255.0,
        blue: CGFloat(0xAA) / 255.0,
        alpha: 1
    )
    private static let placeholderColor = NSColor(
        red: CGFloat(0x7A) / 255.0,
        green: CGFloat(0x84) / 255.0,
        blue: CGFloat(0x78) / 255.0,
        alpha: 1
    )

    private static func placeCursorAtEnd(of textField: NSTextField) {
        let end = textField.stringValue.utf16.count
        textField.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TerminalInputTextField
        var lastFocusRequest: Int

        init(_ parent: TerminalInputTextField) {
            self.parent = parent
            self.lastFocusRequest = parent.focusRequest
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            parent.onSubmit()
            return true
        }

        @objc func submit(_ sender: NSTextField) {
            parent.onSubmit()
        }
    }
}
