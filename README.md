# Codex Auth Helper

**Codex Auth Helper** is a small macOS app for managing Codex accounts without memorizing `codex-auth` commands.

It gives Codex App users a simple interface for login, save/update, switch, list, remove, restart, open, and force-close flows, while still showing the real terminal output so you always know what is happening.

![Codex Auth Helper app showing account list output](docs/codex-auth-helper-screenshot.png)

## Why Use It

- Switch Codex accounts faster from a desktop app.
- Use `codex-auth` without typing the same commands again and again.
- Save or update an auth file. You can add a clear alias, such as `main`, `work`, or `personal`, but the alias is optional when updating an existing account.
- See command output inside the app, including prompts you may need to answer.
- Open detected login links in Chrome Incognito from the built-in terminal panel.
- Restart, open, or force-close Codex App without mixing those actions together.

Think of it as a control panel for `codex-auth`: the app gives you buttons and a terminal view, while `codex-auth` still does the account management.

## Features

- **Login**: runs `codex-auth login --device-auth`, which saves the account through codex-auth's isolated login flow.
- **Save / Update Login**: saves an auth JSON file. Leave the alias blank to update an existing saved account without changing its alias.
- **Switch Account**: prepares `codex-auth switch` so you can type the alias.
- **Open Blank Incognito**: opens a blank Chrome Incognito window from the sidebar, using your normal Chrome profile so Chrome can still offer saved passwords and passkeys.
- **List Accounts**: shows accounts managed by `codex-auth`.
- **Health Check**: checks every saved ChatGPT OAuth account one at a time, refreshes valid tokens, and ends with sorted account summaries.
- **Remove Account**: prepares `codex-auth remove` so you can type the alias.
- **Restart Codex**: quits Codex App, waits for its helper processes to exit, and then reopens it after account changes.
- **Open / Force Close Codex**: shows the right action for the current Codex App state.
- **Interactive terminal**: send input to running commands from the app.
- **Link detection**: open the latest detected login link in Chrome Incognito with one click.
- **One-time code detection**: copy detected login codes with one click.
- **Configurable Codex path**: set the Codex resources path in Settings if Codex App is installed somewhere else.

## Requirements

- macOS 26 or newer.
- Codex App installed.
- Node.js and npm.
- [`codex-auth`](https://github.com/loongphy/codex-auth) installed first. Use the latest stable version.
- For source builds: Xcode 26 and XcodeGen.

Install `codex-auth`:

```bash
npm install -g @loongphy/codex-auth@latest
```

## Install

### Install From DMG

For most users, this is the easiest way to install the app. You do not need Xcode.

Open the [latest GitHub release](https://github.com/withLinda/zsh-codex-auth-helper/releases/latest), then go to **Assets** and download the newest DMG file. For this release, download:

- `CodexAuthHelper-v2026.06.02.1.dmg`

Do not use the **Source code** downloads for normal installation. Those files are only the project source.

If you also want to check the download, download the matching checksum file too:

- `CodexAuthHelper-v2026.06.02.1.dmg.sha256`

The `.dmg` file is the installer. The `.sha256` file lets you check that the download was not damaged. Put both files in the same folder, then run this command from that folder:

```bash
shasum -a 256 -c CodexAuthHelper-v*.dmg.sha256
```

Then install it:

1. Open the downloaded `.dmg` file.
2. Drag `ZshCodexAuthHelper.app` to the `Applications` shortcut in the DMG window.
3. If Finder asks whether to replace an older copy, choose **Replace**.
4. Open `Codex Auth Helper` from `Applications`.

The DMG is Developer ID-signed and notarized. If macOS still shows a warning on first launch, right-click `Codex Auth Helper`, choose **Open**, then choose **Open** again.

If macOS says `ZshCodexAuthHelper` was blocked, open **System Settings > Privacy & Security**, then click **Open Anyway**.

![macOS Privacy & Security showing the Open Anyway button for ZshCodexAuthHelper](docs/images/dmg-install-open-anyway.png)

### Build From Source

Install XcodeGen if you do not already have it:

```bash
brew install xcodegen
```

Then build and run the app from the project folder:

```bash
./script/build_and_run.sh
```

## Quick Start

Use this flow the first time:

1. Install `codex-auth`:

   ```bash
   npm install -g @loongphy/codex-auth@latest
   ```

2. Open **Codex Auth Helper**.
3. Click **Login**.
4. If the terminal shows a login link, click **Open Incognito**. If it shows a one-time code, click **Copy Code** and paste it into the browser page.
5. Finish the login in the browser. When login succeeds, `codex-auth` saves the account automatically.
6. If you want to set or change an alias, use **Save / Update Login**. The default auth file is `~/.codex/auth.json`.
7. Click **List Accounts** to confirm the saved account appears.
8. Click **Switch Account...**, type the alias, email, account name, or row number, then press Return.
9. Click **Restart Codex** so Codex App fully reloads with the selected account.

## Complete Usage Guide

### Saved Login Area

- **Auth account status** shows the account found in the selected auth file. If it says **No auth file**, **Unreadable auth**, or **No signed-in account**, the selected auth file needs attention.
- **Alias (optional)** is a short name for a saved account, such as `main`, `work`, or `personal`. For a new account, a clear alias makes switching easier. For an existing account, you can leave the alias blank to update the saved login without changing its alias.
- **Auth file** is the file to save or update. The normal Codex file is `~/.codex/auth.json`.
- **Save / Update Login** runs `codex-auth import <auth-file>`. Use it after logging in, after reauthenticating, or after changing the auth file path.

### Command Buttons

- **Login** runs `codex-auth login --device-auth`. It signs in through the browser using an isolated codex-auth login flow, then saves the finished login through `codex-auth`. Use **Save / Update Login** only when you want to set an alias manually or update a chosen auth file.
- **Open Blank Incognito** opens a blank Chrome Incognito window. It uses the same Chrome profile as your normal Chrome app, so saved passwords and passkeys can still be offered by Chrome.
- **Switch Account...** prepares `codex-auth switch` in the terminal input. Add an alias, full email, email fragment, account name, or row number from **List Accounts**, then press Return. The app checks the selected saved login before switching and syncs a newer matching active auth file back into the saved account. It refreshes OAuth only when Codex would need renewal now: normally when the access token is expired or within five minutes of expiry, with an eight-day fallback when expiry cannot be read. If more than one account matches, use a more specific value.
- **Restart Codex** quits Codex App, waits for its helper processes to exit, and opens it again. Use this after switching accounts. A simple way to think about it: switching changes the key on disk, and restarting makes Codex pick up the new key.
- **Open Codex** appears when Codex App is closed. It opens Codex without changing accounts.
- **Force Close Codex** appears when Codex App is open. Use it only when Codex is stuck, did not close during restart, or still seems to be using the wrong account. It can kill Codex processes directly.
- **List Accounts** runs `codex-auth list`. Use it to see saved accounts and row numbers.
- **Health Check** checks saved ChatGPT OAuth accounts. See the next section for details and timing.
- **Remove Account** prepares `codex-auth remove` in the terminal input. Add the alias or selector, then press Return. This removes the saved account from `codex-auth`; it does not delete your OpenAI account.

### Terminal Panel

- The terminal shows the real command and output. Read it when something fails, because it usually explains the next step.
- When a command is running, the input box sends text to that command. Use it for prompts that need an answer.
- When no command is running, the input box accepts only prepared **Switch Account...** or **Remove Account** commands.
- **Open Incognito** appears when the terminal detects a login link. It opens the latest detected HTTP or HTTPS link in Google Chrome Incognito.
- **Copy Code** appears when the terminal detects a one-time login code.
- **Stop** stops the running command.
- **Clear** clears the terminal output in the app. It does not delete saved accounts.

### Settings

If Codex App is not installed at `/Applications/Codex.app`, open **Codex Auth Helper > Settings** and update **Codex resources path**.

The default path is:

```text
/Applications/Codex.app/Contents/Resources
```

## Health Check

**Health Check** is for saved ChatGPT OAuth accounts. API-key accounts are skipped because they do not use OAuth refresh tokens.

What it does:

- Reads the accounts saved by `codex-auth`.
- Checks each saved ChatGPT OAuth account one at a time.
- Sends a refresh request to OpenAI's auth server for each OAuth account.
- Writes the new rotated refresh token immediately when the refresh succeeds.
- Updates `~/.codex/auth.json` too when the refreshed account is the active account.
- Prints sorted summaries for accounts that need attention, accounts that were refreshed, and accounts that were skipped.

Rule of thumb:

- Run **Health Check about once per week** for normal multi-account use.
- Also run it before a long or important Codex session, after adding or updating accounts, after a failed switch or login, or before using an account that has been idle for a long time.
- Do not run it after every small switch. **Switch Account...** usually does a local saved-login check. It refreshes only when Codex would need renewal now. **Health Check** proactively validates every saved OAuth account.

Benefits:

- Finds stale saved logins before you need them.
- Reduces surprise login failures during work.
- Keeps saved OAuth tokens fresh.
- Gives a clear account summary in the terminal.

Risks and tradeoffs:

- It makes extra auth-server requests. Running it too often is usually not useful.
- It writes local auth files when tokens refresh.
- It rotates tokens for every saved OAuth account it checks. If a refresh is interrupted by a crash, power loss, or disk problem, you may need to log in again.
- If OpenAI has expired, revoked, or rejected a refresh token, Health Check cannot fix that account by itself. It will mark the account as needing login.

If an account needs login again, use **Login** and finish the browser login. Use **Save / Update Login** afterward only if you want to set or change an alias.

## Troubleshooting

- **Could not find `codex-auth`**: install it with `npm install -g @loongphy/codex-auth`, then reopen the app. If you installed it in a custom location, make sure it is available from your shell `PATH`.
- **No auth file**: check that the **Auth file** field points to `~/.codex/auth.json`, or log in again.
- **Unreadable auth**: the selected auth file is not valid JSON or cannot be read. Log in again, then save the login.
- **No `codex-auth` registry was found**: use **Save / Update Login** or **List Accounts** so `codex-auth` can create or refresh its account registry.
- **Switch Account says more than one account matches**: run **List Accounts**, then switch with a full email, exact alias, or row number.
- **Chrome is missing**: install Google Chrome, or copy the login link from the terminal output and open it manually.
- **Codex opens from the wrong place**: open **Codex Auth Helper > Settings** and set the Codex resources path for your Codex App install.
- **Health Check says `needs login`**: the saved login cannot refresh. Log in again, then save or update that account.
- **Codex still uses the old account after switching**: click **Restart Codex**. Use **Force Close Codex** only if Codex does not close normally.

## Built On codex-auth

This app is powered by [`loongphy/codex-auth`](https://github.com/loongphy/codex-auth), the original command-line tool for switching and managing Codex accounts.

Codex Auth Helper does not replace `codex-auth`. It makes the common `codex-auth` workflows easier to use from a macOS app.
