---
title: "Learnings"
description: "Repo-specific lessons for future agents working on zsh-codexauth-helper."
last_updated: "2026-07-08"
---

# Learnings

This file captures practical lessons from debugging, tool use, and implementation work in this repo. Future agents should read it before starting non-trivial work, and update it when they hit a problem or bug that takes extra effort to solve.

## Table Of Contents

- [How To Update This File](#how-to-update-this-file)
- [Tooling Lessons](#tooling-lessons)
- [Auth Refresh And Switch Lessons](#auth-refresh-and-switch-lessons)
- [UI Lessons](#ui-lessons)
- [Testing Lessons](#testing-lessons)
- [Documentation Lessons](#documentation-lessons)

## How To Update This File

- Add new learnings as short bullets under the closest matching section.
- If no section fits, add a new section and add it to the table of contents.
- Include the date, the symptom, the root cause, and the guardrail for future work.
- Prefer simple English and concrete commands or file paths.
- Do not include private tokens, account secrets, raw auth files, or personal request dumps.

Template:

```markdown
- YYYY-MM-DD: Symptom: ...
  Root cause: ...
  Guardrail: ...
```

## Tooling Lessons

- 2026-06-02: Symptom: notarization could not start with common profile names like `notary-tool`, `linda-notary`, or `notary`.
  Root cause: this repo uses the saved notarytool Keychain profile `codex-auth-helper-notary`.
  Guardrail: for Codex Auth Helper DMG notarization, first check `xcrun notarytool history --keychain-profile codex-auth-helper-notary`, then submit with that same profile. Do not write Apple ID passwords or app-specific passwords into scripts or docs.

- 2026-06-02: Symptom: `./script/test_signing_common.sh` failed with `permission denied`.
  Root cause: the checked-in script is not executable (`644`), even though it is a shell script.
  Guardrail: run it with `bash script/test_signing_common.sh` when verifying, and do not change file mode unless the user asks.

- 2026-06-02: Symptom: `zsh script/test_signing_common.sh` failed with `BASH_SOURCE[0]: parameter not set`.
  Root cause: the script uses Bash-only `BASH_SOURCE`.
  Guardrail: if the direct command is not executable, use `bash`, not `zsh`.

- 2026-06-02: Symptom: new Swift files were not enough by themselves for Xcode project wiring.
  Root cause: this repo is XcodeGen-managed, and generated project files must be refreshed.
  Guardrail: after adding Swift source or test files, run `xcodegen generate` before final verification.

- 2026-07-08: Symptom: mounted-DMG verification failed at `mkdir /Volumes/CodexAuthHelper-v2026.07.08.1` with `Permission denied` after stapling and Gatekeeper checks had already passed.
  Root cause: the managed shell could not create a custom folder directly under `/Volumes`.
  Guardrail: for release verification, create the mount point under `/private/tmp`, then run `hdiutil attach -nobrowse -mountpoint /private/tmp/<name> dist/<dmg>` and detach it after checking the app inside the DMG.

- 2026-06-02: Symptom: Swift Testing produced recursive macro expansion when nesting `#require`.
  Root cause: nested `#require(...)` calls inside another `#require(...)` can trip macro expansion.
  Guardrail: unwrap optional values in separate steps or use safe force unwraps in controlled test fixture setup.

- 2026-06-04: Symptom: full `xcodebuild test` restarted the test host and reported crashes in existing async auth tests, including Swift Testing `#expect` macro lines and `outlined destroy of AuthSwitchPreflightResult`.
  Root cause: the unit-test target is app-hosted, and Swift Testing 1902 on macOS 26.5 can crash these async auth tests inside the app host. Blank `TEST_HOST` does not work in this app target because the test bundle then loses app symbols at link time.
  Guardrail: inspect the `.xcresult` and `~/Library/Logs/DiagnosticReports/ZshCodexAuthHelper-*.ips` before blaming a new UI change. For account-list or command-factory work, also run focused suites such as `xcodebuild test -project ZshCodexAuthHelper.xcodeproj -scheme ZshCodexAuthHelper -destination 'platform=macOS' -only-testing:ZshCodexAuthHelperTests/AccountListStoreTests -only-testing:ZshCodexAuthHelperTests/CodexCommandFactoryTests`.

## Auth Refresh And Switch Lessons

- 2026-06-02: Symptom: switch appeared successful even for an account that needed re-login.
  Root cause: upstream `codex-auth switch <query>` is local-only; it copies a saved snapshot and does not ask OpenAI whether the refresh token still works.
  Guardrail: Switch preflight must check the selected saved login before running `codex-auth switch`. For OAuth accounts, refresh only when Codex would need renewal now. API-key accounts can skip this because they do not use OAuth refresh tokens.

- 2026-06-02: Symptom: preflight only checked that a refresh-token string existed.
  Root cause: local presence is not the same as server acceptance; expired, reused, or revoked refresh tokens still exist on disk.
  Guardrail: keep refresh-token acceptance behind `OAuthTokenRefresher` and the shared `AuthAccountRefreshCoordinator`.

- 2026-06-02: Symptom: it was easy for Health Check and Switch to drift.
  Root cause: refresh, locking, repair, validation, and persistence logic had separate owners.
  Guardrail: centralize account-file locking, freshest matching active snapshot sync, stale-token repair, response validation, and atomic persistence in `AuthAccountRefreshCoordinator`.

- 2026-06-02: Symptom: old Switch preflight tried to match official Codex refresh timing.
  Root cause: the timing rules say when Codex would refresh later. They do not prove whether the saved refresh token is already expired, already used, or revoked now.
  Guardrail: keep the five-minute access-token window and strict eight-day `last_refresh` fallback for Switch. This avoids spending one-use refresh tokens on normal switches. Health Check can still always validate every saved OAuth account.

- 2026-06-02: Symptom: known permanent refresh failures can come back as HTTP `400`, not only `401`.
  Root cause: official Codex treats known refresh-token codes as permanent regardless of the non-success status.
  Guardrail: classify `refresh_token_expired`, `refresh_token_reused`, and `refresh_token_invalidated` as re-login required before falling back to transient HTTP handling.

- 2026-06-03: Symptom: Switch did not explain repeated `already used` results or stale saved-account files.
  Root cause: Switch had no safe debug event stream, and refresh-token checks could hide whether active auth was newer, the saved account file was wrong, saving failed, or another process used the token first.
  Guardrail: Switch must print safe `Switch check:` lines through `AuthAccountRefreshCoordinator`. Log paths and short token fingerprints only. Never log full tokens.

- 2026-06-03: Symptom: Switch blocked normal account changes with `active auth ~/.codex/auth.json does not match selected account` followed by `refresh token was already used`.
  Root cause: Switch was asking OpenAI to refresh the selected saved account every time. Refresh tokens are one-use, so this spent or rejected tokens before `codex-auth switch` could do its own safe active-account sync.
  Guardrail: Switch should treat a different active auth file as normal while switching. It should refresh only when the selected saved access token is expired, within five minutes of expiry, or unreadable with `last_refresh` older than eight days. Use Health Check for strict validation of all saved OAuth accounts.

## UI Lessons

- 2026-07-10: Symptom: **Force Close Codex** stopped closing the app after OpenAI renamed `Codex.app` to `ChatGPT.app`.
  Root cause: the bundle ID stayed `com.openai.codex`, but the force-close script only matched process paths under `Codex.app`. The new processes run under `/Applications/ChatGPT.app/Contents/`.
  Guardrail: resolve the current app bundle through `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`, build the process marker from that real path, keep the old resource path migration in `CodexResourceSettings`, and use the visible app name in lifecycle buttons. Verify safely with `plutil -p /Applications/ChatGPT.app/Contents/Info.plist` and a read-only `ps -axo pid=,command=` matcher. Do not run the real force-close command from inside the Codex task that is doing the verification.

- 2026-07-08: Symptom: adding accent fills made some light-mode buttons and badges colorful but risked weak text/icon contrast.
  Root cause: Everforest Light accent colors are not safe as normal text on pale tinted surfaces, and some Dark Soft tinted surfaces need stronger text than the default foreground.
  Guardrail: keep accent colors as rails, borders, fills, and state cues; use `coloredSurfaceText` for text/icons on tinted surfaces. Verify with `ThemeTokensTests.coloredSurfaceTextPassesWCAGAndDeltaLStarOnTintedSurfaces`.

- 2026-07-08: Symptom: visual verification could not find the launched app under `ZshCodexAuthHelper`, and `screencapture -l` failed after a relaunch with an old window id.
  Root cause: the running window/app owner is named `Codex Auth Helper`, and macOS assigns a new window id after each relaunch.
  Guardrail: after relaunching, query windows with `Codex Auth Helper`, then capture the fresh window id. Do not reuse a previous `screencapture -l` id.

- 2026-07-07: Symptom: Everforest Dark Hard looked too bright after adding theme presets.
  Root cause: calm surfaces used too many raised roles (`bg1`, `bg2`, and `bg3`), so the rail, fields, chrome, and rows felt closer to Medium than Hard.
  Guardrail: for Dark Hard, keep the app canvas, rail, and terminal well on `bg_dim`; keep panels, cards, fields, and chrome on `bg0`; use `bg1` for quiet borders; reserve brighter layers for hover, focus, or selected states. Verify with `ThemeTokensTests.darkHardCalmSurfacesUseOnlyBgDimAndBg0` and a real window screenshot.

- 2026-07-04: Symptom: **Restart Codex** looked available while Codex App was closed, even though **Open Codex** was the only useful action.
  Root cause: the command rail showed the restart action without connecting it to `CodexAppMonitor.state`, and the custom plain button did not define a clear disabled appearance.
  Guardrail: derive restart availability from `CodexAppState.canRestart`, use SwiftUI `disabled(_:)` for interaction, and let `CommandButton` read `EnvironmentValues.isEnabled` for one consistent muted state.

- 2026-07-04: Symptom: command rail buttons looked correct, but `take_ax_snapshot` showed unnamed `button` elements, making automation and accessibility weaker than the visible UI.
  Root cause: the custom plain SwiftUI `Button` label did not reliably become the button's accessibility name.
  Guardrail: set `.accessibilityLabel(title)` inside reusable custom button components, then verify important controls through AX attributes. If `take_ax_snapshot` prints only `button`, check `AXDescription` before assuming labels are missing.

- 2026-06-04: Symptom: the account row looked correct, but automation could not press the row-level Remove button reliably.
  Root cause: the row used `.accessibilityElement(children: .combine)`, so SwiftUI exposed the whole row as one accessibility element and hid the real Switch and Remove buttons inside it.
  Guardrail: do not combine a SwiftUI row when it contains real buttons. Keep row buttons as separate accessibility elements, then verify with `take_ax_snapshot` and a native alert Cancel check.

- 2026-06-04: Symptom: AX verification changed the account search text field value, but the saved-account list did not filter.
  Root cause: `ax_set_value` writes the accessibility value directly and can skip SwiftUI text-input events, so `@State` live filtering may not update.
  Guardrail: for live SwiftUI search fields, verify the user path with coordinate click plus `type_text`, then confirm the filtered count and rows with `take_ax_snapshot`.

## Testing Lessons

- 2026-07-07: Symptom: after adding a new Swift Testing file, the focused `xcodebuild test` path can look useful while the new tests are not wired into the generated Xcode project yet.
  Root cause: this repo uses XcodeGen, so new source and test files are invisible to Xcode until `xcodegen generate` refreshes `ZshCodexAuthHelper.xcodeproj`.
  Guardrail: after adding Swift source or test files, run `xcodegen generate`, then run a suite-level filter and confirm the Swift Testing log says `Test run with N tests`.

- 2026-07-04: Symptom: a method-level `xcodebuild -only-testing` filter printed `TEST SUCCEEDED` but ran zero Swift Testing tests.
  Root cause: the method selector did not match the Swift Testing function in this app-hosted test target, so it proved compilation only.
  Guardrail: filter this target at suite level, for example `-only-testing:ZshCodexAuthHelperTests/CodexAppMonitorTests`, and confirm the log says `Test run with N tests` before treating the run as proof.

- 2026-06-02: Symptom: tests could accidentally try real OAuth refreshes.
  Root cause: Switch can refresh OAuth accounts when conditional renewal is needed, so any OAuth refresh-path test without a fake refresher can fall through to the live refresher.
  Guardrail: inject fake `OAuthTokenRefreshing` implementations for all Switch OAuth success and failure tests. Never use saved personal auth files for verification.

- 2026-06-02: Symptom: a successful local switch test could hide a broken server-side login.
  Root cause: a local snapshot can be copied even when the refresh token is dead.
  Guardrail: include tests for conditional OAuth Switch, permanent re-login failures when refresh is needed, transient failures, invalid refresh responses, stale active-auth repair, wrong-file identity blocks, save failures, safe debug logs, API-key skip, and lock behavior.

- 2026-06-02: Symptom: verification needed to avoid touching personal saved accounts.
  Root cause: live OAuth refreshes rotate real tokens.
  Guardrail: use injected request transports and fake `OAuthTokenRefreshing` implementations in tests; never use saved personal auth files for verification.

## Documentation Lessons

- 2026-06-02: Symptom: old wording said normal switch did not refresh OAuth tokens.
  Root cause: Switch behavior is conditional: it refreshes only when Codex would need renewal now, while Health Check always validates saved OAuth accounts.
  Guardrail: README and transcript text must say OAuth Switch is conditional. Do not say "always local" or "always refreshed".

- 2026-06-02: Symptom: re-login guidance could overstate the need for Save / Update Login.
  Root cause: the isolated `codex-auth login` flow saves the account itself; Save / Update Login is mainly for aliases or chosen auth files.
  Guardrail: for switch preflight permanent failures, tell the user to click **Login**, finish browser login, then switch again. Mention Save / Update Login only as optional for aliases.
