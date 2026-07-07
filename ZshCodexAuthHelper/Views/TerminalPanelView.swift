import AppKit
import SwiftUI

struct TerminalPanelView: View {
    @ObservedObject var store: TerminalTranscriptStore
    @ObservedObject var runner: CommandRunner
    @Binding var input: String

    let focusRequest: Int
    let submitDraft: (String) -> Void
    let openURL: (URL) -> Void

    @State private var copiedDeviceCode: String?
    @State private var copyFeedbackTask: Task<Void, Never>?

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
        .onChange(of: store.latestDeviceCode) { _, _ in
            copiedDeviceCode = nil
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
    }

    private var terminalHeader: some View {
        HStack(spacing: ThemeTokens.Spacing.normal) {
            Capsule(style: .continuous)
                .fill(ThemeTokens.Colors.accent)
                .frame(width: 4, height: 34)

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
                    openURL(url)
                } label: {
                    Label("Open Incognito", systemImage: "eye.slash")
                }
                .buttonStyle(ToolbarButtonStyle(tint: ThemeTokens.Colors.accent, surface: ThemeTokens.Colors.accentSurface))
                .help("Open login link in Chrome Incognito")
                .accessibilityLabel("Open login link in Chrome Incognito")
            }

            if let deviceCode = store.latestDeviceCode {
                Button {
                    copyDeviceCode(deviceCode)
                } label: {
                    Label(
                        "Copy Code",
                        systemImage: copiedDeviceCode == deviceCode ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(
                    ToolbarButtonStyle(
                        tint: copiedDeviceCode == deviceCode ? ThemeTokens.Colors.successAccent : ThemeTokens.Colors.infoAccent,
                        surface: copiedDeviceCode == deviceCode ? ThemeTokens.Colors.successSurface : ThemeTokens.Colors.infoSurface
                    )
                )
                .help("Copy one-time code")
                .accessibilityLabel("Copy one-time code")
            }

            Button {
                runner.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(ToolbarButtonStyle(tint: ThemeTokens.Colors.destructiveAccent, surface: ThemeTokens.Colors.destructiveSurface))
            .disabled(runner.isRunning == false)

            Button {
                store.clear()
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .buttonStyle(ToolbarButtonStyle(tint: ThemeTokens.Colors.infoAccent, surface: ThemeTokens.Colors.infoSurface))
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.group)
        .background(ThemeTokens.Colors.chromeSurface)
    }

    private var terminalBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(terminalOutputAttributedText)
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

    private var terminalOutputText: String {
        store.displayTranscript.isEmpty ? "Output will appear here." : store.displayTranscript
    }

    private var terminalOutputAttributedText: AttributedString {
        let text = terminalOutputText
        var output = AttributedString(text)
        output.font = .system(.callout, design: .monospaced)
        output.foregroundColor = store.displayTranscript.isEmpty
            ? ThemeTokens.Colors.mutedText
            : ThemeTokens.Colors.primaryText

        guard store.displayTranscript.isEmpty == false else {
            return output
        }

        for highlight in TerminalTranscriptParser.accountHighlights(in: text) {
            guard let lowerBound = AttributedString.Index(highlight.range.lowerBound, within: output),
                  let upperBound = AttributedString.Index(highlight.range.upperBound, within: output) else {
                continue
            }

            output[lowerBound..<upperBound].foregroundColor = highlight.tone.terminalColor
            output[lowerBound..<upperBound].font = .system(.callout, design: .monospaced).weight(.semibold)
        }

        return output
    }

    private var inputBar: some View {
        HStack(spacing: ThemeTokens.Spacing.normal) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSendInput ? ThemeTokens.Colors.accent : ThemeTokens.Colors.mutedText)

            TerminalInputTextField(
                text: $input,
                placeholder: inputPlaceholder,
                textColorHex: ThemeTokens.Colors.primaryTextHex,
                placeholderColorHex: ThemeTokens.Colors.disabledTextHex,
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

        return "Type switch/remove command"
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

    private func copyDeviceCode(_ deviceCode: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(deviceCode, forType: .string) else {
            return
        }

        copiedDeviceCode = deviceCode
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard Task.isCancelled == false else {
                return
            }
            await MainActor.run {
                if copiedDeviceCode == deviceCode {
                    copiedDeviceCode = nil
                }
                copyFeedbackTask = nil
            }
        }
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let tint: Color
    let surface: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(ThemeTokens.Colors.coloredSurfaceText)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, ThemeTokens.Spacing.normal)
            .frame(minHeight: 34)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ThemeTokens.Radius.button, style: .continuous)
                    .stroke(tint.opacity(configuration.isPressed ? 0.42 : 0.28), lineWidth: 1)
            }
    }
}

private extension TerminalTranscriptAccountTone {
    var terminalColor: Color {
        switch self {
        case .success:
            return ThemeTokens.Colors.success
        case .warning:
            return ThemeTokens.Colors.warning
        case .destructive:
            return ThemeTokens.Colors.destructive
        }
    }
}

private struct TerminalInputTextField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let textColorHex: UInt32
    let placeholderColorHex: UInt32
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
        textField.textColor = NSColor(hex: textColorHex)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }

        textField.textColor = NSColor(hex: textColorHex)
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(hex: placeholderColorHex),
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
