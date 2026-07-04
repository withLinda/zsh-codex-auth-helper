# Restart Codex Availability Design

## Goal

Reduce unnecessary choice when Codex App is closed.

## Behavior

- When Codex App is open, **Restart Codex** is active.
- When Codex App is closed or still starting, **Restart Codex** is disabled.
- **Open Codex** remains active while Codex App is closed.
- Existing command-running state still disables the whole Commands group.
- The existing `CodexAppMonitor` remains the source of truth.

## Visual Design

- Keep **Restart Codex** in its current position so the command list does not move.
- Show disabled command buttons with muted grey text and icon colors.
- Keep the same size, shape, and label.
- Add no helper text, badge, animation, or new control.

## Implementation Shape

- Give `CodexAppState` a small tested availability rule for restart.
- Apply that rule to the **Restart Codex** button with SwiftUI `disabled(_:)`.
- Make the shared `CommandButton` appearance read SwiftUI's `isEnabled` environment value.
- Use existing semantic theme colors. Do not add raw colors to the view.

## Accessibility

- A disabled button must not run its action.
- The text label and SF Symbol remain visible, so meaning does not depend on color alone.
- Native SwiftUI disabled state remains available to accessibility tools.

## Tests And Verification

- Add a focused unit test: restart is available only for `.open`.
- First run it before implementation and confirm that it fails for the missing rule.
- Run the focused test again after implementation.
- Build the macOS app.
- Launch the app and verify both closed and open Codex states when safe.

## Scope

Do not change command order, labels, Codex process detection, or restart command behavior.
