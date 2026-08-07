# Codex Auth Helper

**Codex Auth Helper** is a small macOS app for managing Codex accounts without memorizing `codex-auth` commands.

It gives ChatGPT desktop app users a simple interface for login, save/update, switch, remove, restart, open, and force-close flows, while still showing the real terminal output so you always know what is happening.

![Codex Auth Helper beside CodexPlusBar](docs/images/codex-auth-helper-with-codexplusbar.png)

## See Live Account Limits With CodexPlusBar

Codex Auth Helper handles login, saved accounts, health checks, and account switching. To see the remaining usage for many accounts, use [CodexPlusBar](https://github.com/withLinda/CodexPlusBar). It shows the remaining 5-hour and 7-day usage percentages, reset times, sign-in state, and account expiry when the provider supplies it.

The two apps are separate, but they work well side by side:

1. Use CodexPlusBar to see which account has enough usage left.
2. Use **Switch & Open** in Codex Auth Helper to activate that account and reopen ChatGPT.

## Why Use It

- Switch Codex accounts and reopen the app with one button press.
- See the active account, plan, alias, account name, and last-use information in one saved-account dashboard.
- Use `codex-auth` without typing the same commands again and again.
- Save or update an auth file. You can add a clear alias, such as `main`, `work`, or `personal`, but the alias is optional when updating an existing account.
- See command output inside the app, including prompts you may need to answer.
- Open detected login links in Chrome Incognito from the built-in terminal panel.
- Restart, open, or force-close Codex App when you need a separate recovery action.

Think of it as a control panel for `codex-auth`: the app gives you buttons and a terminal view, while `codex-auth` still does the account management.

## Features

- **Login**: runs `codex-auth login --device-auth`, which saves the account through codex-auth's isolated login flow.
- **Save / Update Login**: saves an auth JSON file. Leave the alias blank to update an existing saved account without changing its alias.
- **Saved Accounts dashboard**: loads the local account registry automatically, highlights the active account, and shows useful account details.
- **Automatic updates**: notices changes to the saved-account registry and selected auth file, and also provides a manual **Refresh** button.
- **Search saved accounts**: filter the saved-account list by email, alias, account name, plan, or auth mode.
- **Open Blank Incognito**: opens a blank Chrome Incognito window from the sidebar, using your normal Chrome profile so Chrome can still offer saved passwords and passkeys.
- **Health Check**: checks every saved ChatGPT OAuth account one at a time, refreshes valid tokens, and ends with sorted account summaries.
- **Update codex-auth**: installs or updates the app-owned `codex-auth` tool without changing your global terminal copy, then reports the installed version.
- **Remove with confirmation**: removes a saved account from its row after you confirm. It does not delete the OpenAI account.
- **Switch & Open**: force-closes the ChatGPT desktop app, switches the saved account, and opens ChatGPT again in one sequence.
- **Restart ChatGPT**: quits the ChatGPT desktop app, waits for its Codex helper processes to exit, and then reopens it.
- **Open / Force Close ChatGPT**: shows the right action for the current ChatGPT desktop app state.
- **Interactive terminal**: send input to running commands from the app.
- **Link detection**: open the latest detected login link in Chrome Incognito with one click.
- **One-time code detection**: copy detected login codes with one click.
- **Configurable Codex path**: set the Codex resources path in Settings if Codex App is installed somewhere else.
- **Theme settings**: choose Everforest Dark or Light, with Hard, Medium, or Soft contrast.

## Requirements

- macOS 26 or newer.
- Codex App installed.
- Node.js and npm.
- The app can install its own [`codex-auth`](https://github.com/loongphy/codex-auth) copy. A global install is only a fallback.
- For source builds: Xcode 26 and XcodeGen.

Optional global fallback install:

```bash
npm install -g @loongphy/codex-auth@latest
```

## Install

### Install From DMG

For most users, this is the easiest way to install or update the app. You do not need Xcode.

Open the [latest GitHub release](https://github.com/withLinda/zsh-codex-auth-helper/releases/latest), then go to **Assets** and download the newest DMG file. For this release, download:

- `CodexAuthHelper-v2026.07.14.1.dmg`

Do not use the **Source code** downloads for normal installation. Those files are only the project source.

If you also want to check the download, download the matching checksum file too:

- `CodexAuthHelper-v2026.07.14.1.dmg.sha256`

The `.dmg` file is the installer. The `.sha256` file lets you check that the download was not damaged. Put both files in the same folder, then run this command from that folder:

```bash
shasum -a 256 -c CodexAuthHelper-v*.dmg.sha256
```

Then install it:

1. Open the downloaded `.dmg` file.
2. Drag `ZshCodexAuthHelper.app` to the `Applications` shortcut in the DMG window.
3. If Finder asks whether to replace an older copy, choose **Replace**.
4. Open `Codex Auth Helper` from `Applications`.

The DMG is Developer ID-signed, notarized, and stapled. macOS should verify it normally when you open it.

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

1. Open **Codex Auth Helper**.
2. Click **Update codex-auth**. This installs the app-owned tool into `~/Library/Application Support/CodexAuthHelper/codex-auth-tool`.
3. Click **Login**.
4. If the terminal shows a login link, click **Open Incognito**. If it shows a one-time code, click **Copy Code** and paste it into the browser page.
5. Finish the login in the browser. When login succeeds, `codex-auth` saves the account automatically.
6. If you want to set or change an alias, use **Save / Update Login**. The default auth file is `~/.codex/auth.json`.
7. Check that the account appears in **Saved Accounts**. The list updates automatically; click **Refresh** if needed.
8. In a saved-account row, click **Switch & Open**. The app force-closes ChatGPT, switches the account, and opens ChatGPT again.

## Complete Usage Guide

### Saved Login Area

- **Auth account status** shows the account found in the selected auth file. If it says **No auth file**, **Unreadable auth**, or **No signed-in account**, the selected auth file needs attention.
- **Alias (optional)** is a short name for a saved account, such as `main`, `work`, or `personal`. For a new account, a clear alias makes switching easier. For an existing account, you can leave the alias blank to update the saved login without changing its alias.
- **Auth file** is the file to save or update. The normal Codex file is `~/.codex/auth.json`.
- **Save / Update Login** runs `codex-auth import <auth-file>`. Use it after logging in, after reauthenticating, or after changing the auth file path.

### Saved Accounts Dashboard

- The dashboard reads the `codex-auth` registry automatically. It also notices registry changes made outside the app.
- The active account is marked **Active** and **Current**. Each row can also show the plan, alias, account name, and last-use information when those values exist.
- **Refresh** reloads the account list immediately.
- Search filters by email, alias, account name, plan, or auth mode. Clear the search to show every account again.
- **Switch & Open** uses a safe unique selector for the row. It checks the saved login, force-closes ChatGPT, switches the account, and opens ChatGPT again. If the switch fails after ChatGPT closes, the app still reopens ChatGPT.
- **Remove** shows a confirmation first. Removing a saved login does not delete the OpenAI account.

### Command Buttons

- **Login** runs `codex-auth login --device-auth`. It signs in through the browser using an isolated codex-auth login flow, then saves the finished login through `codex-auth`. Use **Save / Update Login** only when you want to set an alias manually or update a chosen auth file.
- **Open Blank Incognito** opens a blank Chrome Incognito window. It uses the same Chrome profile as your normal Chrome app, so saved passwords and passkeys can still be offered by Chrome.
- **Restart ChatGPT** quits the ChatGPT desktop app, waits for its Codex helper processes to exit, and opens it again. Use it when you need to reload the current account without switching.
- **Open ChatGPT** appears when the ChatGPT desktop app is closed. It opens ChatGPT without changing accounts.
- **Force Close ChatGPT** appears when the ChatGPT desktop app is open. Use it only when ChatGPT is stuck, did not close during restart, or Codex still seems to be using the wrong account. It can kill the app processes directly.
- **Update codex-auth** runs `npm install --global --prefix ~/Library/Application Support/CodexAuthHelper/codex-auth-tool @loongphy/codex-auth@latest` or `@next`, depending on the Settings channel. It updates only the app-owned tool. It does not run `sudo` and does not change your global terminal `codex-auth`.
- **Health Check** checks saved ChatGPT OAuth accounts. See the next section for details and timing.

### Switch Safety Check

Every account switch checks the selected saved login before changing accounts. For OAuth accounts, it refreshes only when Codex would need renewal now: when the access token is expired or within five minutes of expiry, or when expiry cannot be read and `last_refresh` is older than eight days. If the saved access token is still fresh, the switch does not ask OpenAI and does not spend the refresh token.

If `~/.codex/auth.json` is a newer matching login, the app copies it into the saved account file first. The terminal prints safe `Switch check:` lines, but never prints full tokens. If OpenAI accepts a needed refresh, the app saves the new rotated token, then runs `codex-auth switch`. If a needed refresh finds an expired, already used, or revoked token, the wrong saved file, or a save failure, the switch is blocked. API-key accounts skip OAuth refresh because they do not use refresh tokens.

### Terminal Panel

- The terminal shows the real command and output. Read it when something fails, because it usually explains the next step.
- When a command is running, the input box sends text to that command. Use it for prompts that need an answer.
- When no command is running, the input box accepts only `codex-auth switch <selector>` or `codex-auth remove <selector>`. Other commands are blocked. The saved-account row buttons are easier for normal use.
- **Open Incognito** appears when the terminal detects a login link. It opens the latest detected HTTP or HTTPS link in Google Chrome Incognito.
- **Copy Code** appears when the terminal detects a one-time login code.
- **Stop** stops the running command.
- **Clear** clears the terminal output in the app. It does not delete saved accounts.

### Settings

If the ChatGPT desktop app is not installed at `/Applications/ChatGPT.app`, open **Codex Auth Helper > Settings** and update **Codex resources path**. Old `/Applications/Codex.app` installs still work.

The default path is:

```text
/Applications/ChatGPT.app/Contents/Resources
```

Settings also has a `codex-auth` update channel:

- **Stable** installs `@loongphy/codex-auth@latest`. This is the safer normal choice.
- **Next Alpha** installs `@loongphy/codex-auth@next`. This can get new features sooner, but it can break more often.

The app always looks for its app-owned `codex-auth` first. If it is missing, the app falls back to global locations such as `/opt/homebrew/bin/codex-auth`.

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
- You do not need **Health Check** after every small switch. Each account switch checks only the selected account and refreshes it only when Codex would need renewal now. **Health Check** validates every saved OAuth account, so it is still useful before important work or about once per week.

Benefits:

- Finds stale saved logins before you need them.
- Reduces surprise login failures during work.
- Keeps saved OAuth tokens fresh.
- Gives a clear account summary in the terminal.

Risks and tradeoffs:

- It makes extra auth-server requests. Running it too often is usually not useful.
- It writes local auth files when tokens refresh.
- It rotates tokens for every saved OAuth account it checks. A normal account switch rotates the selected OAuth account token only when that account needs renewal now. If a refresh is interrupted by a crash, power loss, or disk problem, you may need to log in again.
- If OpenAI has expired, revoked, or rejected a refresh token, Health Check cannot fix that account by itself. It will mark the account as needing login.

If an account needs login again, use **Login** and finish the browser login. Use **Save / Update Login** afterward only if you want to set or change an alias.

## Troubleshooting

- **Could not find npm**: install Node.js and npm, then reopen the app.
- **Could not find `codex-auth`**: click **Update codex-auth** first. If you prefer a global fallback, install it with `npm install -g @loongphy/codex-auth`, then reopen the app.
- **No auth file**: check that the **Auth file** field points to `~/.codex/auth.json`, or log in again.
- **Unreadable auth**: the selected auth file is not valid JSON or cannot be read. Log in again, then save the login.
- **No `codex-auth` registry was found**: finish **Login** or use **Save / Update Login**, then click **Refresh** in Saved Accounts.
- **A manual switch says more than one account matches**: use a full email, exact alias, or row number. The row-level **Switch & Open** action chooses a safe unique selector automatically.
- **A switch says the refresh token was already used**: this can happen only when the switch had to refresh because the saved access token needed renewal. Click **Login**, finish browser login, then switch again. If this happens every time, read the `Switch check:` lines. They should show whether the saved account file was stale, whether `~/.codex/auth.json` was newer, whether saving the new token failed, or whether another Codex or `codex-auth` process probably used the token first.
- **A switch says the saved auth file does not match the selected account**: the saved file may belong to a different account. The app blocks the switch because switching from the wrong saved file is unsafe. Click **Login** for the selected account, then use **Save / Update Login** and **Refresh** if you need to rebuild the saved registry or alias.
- **Chrome is missing**: install Google Chrome, or copy the login link from the terminal output and open it manually.
- **ChatGPT opens from the wrong place**: open **Codex Auth Helper > Settings** and set the Codex resources path for your ChatGPT or older Codex app install.
- **Health Check says `needs login`**: the saved login cannot refresh. Log in again, then save or update that account.
- **Codex still uses the old account after switching**: use the saved account row's **Switch & Open** button. It force-closes ChatGPT before switching, then opens it again. Use **Force Close ChatGPT** only as a separate recovery action.

## Built On codex-auth

This app is powered by [`loongphy/codex-auth`](https://github.com/loongphy/codex-auth), the original command-line tool for switching and managing Codex accounts.

Codex Auth Helper does not replace `codex-auth`. It makes the common `codex-auth` workflows easier to use from a macOS app.
