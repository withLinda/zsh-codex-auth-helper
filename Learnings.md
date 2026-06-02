---
title: "Learnings"
description: "Repo-specific lessons for future agents working on zsh-codexauth-helper."
last_updated: "2026-06-02"
---

# Learnings

This file captures practical lessons from debugging, tool use, and implementation work in this repo. Future agents should read it before starting non-trivial work, and update it when they hit a problem or bug that takes extra effort to solve.

## Table Of Contents

- [How To Update This File](#how-to-update-this-file)
- [Tooling Lessons](#tooling-lessons)
- [Auth Refresh And Switch Lessons](#auth-refresh-and-switch-lessons)
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

- 2026-06-02: Symptom: Swift Testing produced recursive macro expansion when nesting `#require`.
  Root cause: nested `#require(...)` calls inside another `#require(...)` can trip macro expansion.
  Guardrail: unwrap optional values in separate steps or use safe force unwraps in controlled test fixture setup.

## Auth Refresh And Switch Lessons

- 2026-06-02: Symptom: switch appeared successful even for an account that needed re-login.
  Root cause: upstream `codex-auth switch <query>` is local-only; it copies a saved snapshot and does not ask OpenAI whether the refresh token still works.
  Guardrail: switch preflight must validate or refresh before running `codex-auth switch` when Codex would need renewal.

- 2026-06-02: Symptom: preflight only checked that a refresh-token string existed.
  Root cause: local presence is not the same as server acceptance; expired, reused, or revoked refresh tokens still exist on disk.
  Guardrail: keep refresh-token acceptance behind `OAuthTokenRefresher` and the shared `AuthAccountRefreshCoordinator`.

- 2026-06-02: Symptom: it was easy for Health Check and Switch to drift.
  Root cause: refresh, locking, repair, validation, and persistence logic had separate owners.
  Guardrail: centralize account-file locking, freshest matching active snapshot sync, conditional refresh, stale-token repair, response validation, and atomic persistence in `AuthAccountRefreshCoordinator`.

- 2026-06-02: Symptom: official Codex refresh behavior needed exact matching.
  Root cause: the timing rules are specific: refresh when access-token JWT expiry is `<= now + 5 minutes`; if expiry cannot be read, use `last_refresh < now - 8 days`.
  Guardrail: preserve the exact boundary behavior in tests, especially the strict eight-day fallback comparison.

- 2026-06-02: Symptom: known permanent refresh failures can come back as HTTP `400`, not only `401`.
  Root cause: official Codex treats known refresh-token codes as permanent regardless of the non-success status.
  Guardrail: classify `refresh_token_expired`, `refresh_token_reused`, and `refresh_token_invalidated` as re-login required before falling back to transient HTTP handling.

## Testing Lessons

- 2026-06-02: Symptom: tests could accidentally try real OAuth refreshes if fixture access tokens looked stale.
  Root cause: unreadable fake access tokens trigger the eight-day fallback, and old `last_refresh` values can require refresh.
  Guardrail: default switch-preflight fixtures to a parseable fresh access-token JWT, and inject fake refreshers for all refresh-path tests.

- 2026-06-02: Symptom: a successful local switch test could hide a broken server-side login.
  Root cause: a local snapshot can be copied even when the refresh token is dead.
  Guardrail: include tests for fresh local success, near-expiry refresh success, permanent re-login failures, transient failures, invalid refresh responses, active-token repair, different-account rejection, API-key skip, and lock behavior.

- 2026-06-02: Symptom: verification needed to avoid touching personal saved accounts.
  Root cause: live OAuth refreshes rotate real tokens.
  Guardrail: use injected request transports and fake `OAuthTokenRefreshing` implementations in tests; never use saved personal auth files for verification.

## Documentation Lessons

- 2026-06-02: Symptom: old wording said normal switch did not refresh OAuth tokens.
  Root cause: after the fix, switch usually stays local, but it can refresh when Codex would need renewal now.
  Guardrail: README and transcript text must say conditional refresh, not "always local" and not "always refreshed".

- 2026-06-02: Symptom: re-login guidance could overstate the need for Save / Update Login.
  Root cause: the isolated `codex-auth login` flow saves the account itself; Save / Update Login is mainly for aliases or chosen auth files.
  Guardrail: for switch preflight permanent failures, tell the user to click **Login**, finish browser login, then switch again. Mention Save / Update Login only as optional for aliases.
