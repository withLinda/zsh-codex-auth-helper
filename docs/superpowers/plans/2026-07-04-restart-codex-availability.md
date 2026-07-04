# Restart Codex Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disable and visually mute **Restart Codex** whenever Codex App is not open.

**Architecture:** Keep `CodexAppMonitor` as the only source of app-open state. Add a small availability rule to `CodexAppState`, use it in `CommandRailView`, and make the shared `CommandButton` render SwiftUI's disabled environment state consistently.

**Tech Stack:** Swift 5, SwiftUI, macOS 26, Swift Testing, XcodeGen

---

### Task 1: Define and test restart availability

**Files:**
- Modify: `ZshCodexAuthHelperTests/Stores/CodexAppMonitorTests.swift`
- Modify: `ZshCodexAuthHelper/Stores/CodexAppMonitor.swift`

- [ ] **Step 1: Write the failing test**

Add this test inside `CodexAppMonitorTests`:

```swift
@Test func restartIsAvailableOnlyWhenCodexIsOpen() {
    #expect(CodexAppState.open.canRestart)
    #expect(CodexAppState.closed.canRestart == false)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test \
  -project ZshCodexAuthHelper.xcodeproj \
  -scheme ZshCodexAuthHelper \
  -destination 'platform=macOS' \
  -only-testing:ZshCodexAuthHelperTests/CodexAppMonitorTests
```

Expected: build failure because `CodexAppState` has no member `canRestart`.

- [ ] **Step 3: Add the minimal availability rule**

Change `CodexAppState` to:

```swift
enum CodexAppState: Equatable {
    case open
    case closed

    var canRestart: Bool {
        self == .open
    }
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the same focused `xcodebuild test` command.

Expected: all 6 `CodexAppMonitorTests`, including `restartIsAvailableOnlyWhenCodexIsOpen`, pass.

### Task 2: Connect the button behavior and disabled appearance

**Files:**
- Modify: `ZshCodexAuthHelper/Views/CommandRailView.swift`

- [ ] **Step 1: Disable Restart from the tested state rule**

Change the restart button to:

```swift
CommandButton(
    title: "Restart Codex",
    systemImage: "power",
    tint: ThemeTokens.Colors.warning,
    action: runRestart
)
.disabled(codexAppState.canRestart == false)
```

The existing `.disabled(isRunning)` on the Commands group remains in place. A parent disabled state still wins.

- [ ] **Step 2: Read the native enabled state in the shared button**

Add this property to `CommandButton`:

```swift
@Environment(\.isEnabled) private var isEnabled
```

- [ ] **Step 3: Use quiet semantic colors when disabled**

Change the icon, label, and background styles:

```swift
Image(systemName: systemImage)
    .font(.system(size: 15, weight: .semibold))
    .foregroundStyle(isEnabled ? tint : ThemeTokens.Colors.mutedText)
    .frame(width: 20)

Text(title)
    .font(.callout.weight(.medium))
    .foregroundStyle(isEnabled ? ThemeTokens.Colors.primaryText : ThemeTokens.Colors.mutedText)

// ...

.background(isEnabled ? ThemeTokens.Colors.nestedSurface : ThemeTokens.Colors.panelSurface)
```

Keep the existing button size, shape, label, and order.

- [ ] **Step 4: Build the app**

Run:

```bash
xcodebuild build \
  -project ZshCodexAuthHelper.xcodeproj \
  -scheme ZshCodexAuthHelper \
  -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

### Task 3: Verify behavior and record the durable lesson

**Files:**
- Modify: `Learnings.md`

- [ ] **Step 1: Verify the closed state**

Launch Codex Auth Helper while Codex App is closed.

Expected:

- **Open Codex** is active.
- **Restart Codex** uses muted grey text and icon.
- Clicking **Restart Codex** does nothing.

- [ ] **Step 2: Verify the open state**

Open Codex App and wait for `CodexAppMonitor` to receive the launch notification.

Expected:

- **Force Close Codex** replaces **Open Codex**.
- **Restart Codex** returns to its normal warning icon and primary text.
- **Restart Codex** is active.

- [ ] **Step 3: Add the project lesson**

Add this bullet under `## UI Lessons`:

```markdown
- 2026-07-04: Symptom: **Restart Codex** looked available while Codex App was closed, even though **Open Codex** was the only useful action.
  Root cause: the command rail showed the restart action without connecting it to `CodexAppMonitor.state`, and the custom plain button did not define a clear disabled appearance.
  Guardrail: derive restart availability from `CodexAppState.canRestart`, use SwiftUI `disabled(_:)` for interaction, and let `CommandButton` read `EnvironmentValues.isEnabled` for one consistent muted state.
```

- [ ] **Step 4: Run final checks**

Run:

```bash
xcodebuild test \
  -project ZshCodexAuthHelper.xcodeproj \
  -scheme ZshCodexAuthHelper \
  -destination 'platform=macOS' \
  -only-testing:ZshCodexAuthHelperTests/CodexAppMonitorTests

git diff --check
```

Expected: the focused test suite passes and `git diff --check` prints no errors.

- [ ] **Step 5: Review the final diff**

Run:

```bash
git diff -- \
  Learnings.md \
  ZshCodexAuthHelper/Stores/CodexAppMonitor.swift \
  ZshCodexAuthHelper/Views/CommandRailView.swift \
  ZshCodexAuthHelperTests/Stores/CodexAppMonitorTests.swift
```

Expected: only the tested availability rule, disabled button behavior and style, one focused test, and one learning entry are present.
