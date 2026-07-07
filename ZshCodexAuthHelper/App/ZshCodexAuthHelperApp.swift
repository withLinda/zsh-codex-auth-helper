import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppRuntime.isRunningUnitTests == false else {
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum AppRuntime {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil
    }
}

@main
struct ZshCodexAuthHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppThemeSettings.presetKey) private var appThemePresetRaw = AppThemePreset.fallback.rawValue

    private var selectedThemePreset: AppThemePreset {
        AppThemePreset(storedValue: appThemePresetRaw)
    }

    var body: some Scene {
        WindowGroup("Codex Auth Helper") {
            if AppRuntime.isRunningUnitTests {
                UnitTestHostView()
            } else {
                ContentView()
                    .frame(minWidth: 980, minHeight: 640)
                    .preferredColorScheme(selectedThemePreset.colorScheme)
            }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            CodexResourceSettingsView()
                .preferredColorScheme(selectedThemePreset.colorScheme)
        }
    }
}

private struct UnitTestHostView: View {
    var body: some View {
        EmptyView()
    }
}
