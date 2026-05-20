# Codex Auth Helper

**Codex Auth Helper** is a small macOS app for managing Codex accounts without memorizing `codex-auth` commands.

It gives Codex App users a simple interface for login, save/update, switch, list, remove, and restart flows, while still showing the real terminal output so you always know what is happening.

![Codex Auth Helper app showing account list output](docs/codex-auth-helper-screenshot.png)

## Why Use It

- Switch Codex accounts faster from a desktop app.
- Use `codex-auth` without typing the same commands again and again.
- Save or update an auth file. You can add a clear alias, such as `main`, `work`, or `personal`, but the alias is optional when updating an existing account.
- See command output inside the app, including prompts you may need to answer.
- Open detected login links from the built-in terminal panel.
- Restart Codex App after switching so the new account takes effect, with a safer wait before reopening.

Think of it as a control panel for `codex-auth`: the app gives you buttons and a terminal view, while `codex-auth` still does the account management.

## Features

- **Login**: runs `codex login --device-auth`.
- **Save / Update Login**: saves an auth JSON file. Leave the alias blank to update an existing saved account without changing its alias.
- **Switch Account**: prepares `codex-auth switch` so you can type the alias.
- **List Accounts**: shows accounts managed by `codex-auth`.
- **Health Check**: manually refreshes saved ChatGPT accounts whose last refresh is older than 24 hours, one account at a time.
- **Remove Account**: prepares `codex-auth remove` so you can type the alias.
- **Restart Codex**: quits Codex App, waits for its helper processes to exit, and then reopens it after account changes.
- **Interactive terminal**: send input to running commands from the app.
- **Link detection**: open the latest detected login link with one click.
- **One-time code detection**: copy detected login codes with one click.
- **Configurable Codex path**: set the Codex resources path in Settings if Codex App is installed somewhere else.

## Requirements

- macOS 26 or newer.
- Codex App installed.
- Node.js and npm.
- [`codex-auth`](https://github.com/loongphy/codex-auth) installed first.
- For source builds: Xcode 26 and XcodeGen.

Install `codex-auth`:

```bash
npm install -g @loongphy/codex-auth
```

## Install

### Install From DMG

For most users, this is the easiest way to install the app. You do not need Xcode.

Open the [latest GitHub release](https://github.com/withLinda/zsh-codex-auth-helper/releases/latest), then go to **Assets** and download the file that ends in `.dmg`:

- `CodexAuthHelper-v...dmg`

Do not use the **Source code** downloads for normal installation. Those files are only the project source.

If you also want to check the download, download the matching checksum file too:

- `CodexAuthHelper-v...dmg.sha256`

The `.dmg` file is the installer. The `.sha256` file lets you check that the download was not damaged. Put both files in the same folder, then run this command from that folder:

```bash
shasum -a 256 -c CodexAuthHelper-v*.dmg.sha256
```

Then install it:

1. Open the downloaded `.dmg` file.
2. Drag `ZshCodexAuthHelper.app` to the `Applications` shortcut in the DMG window.
3. If Finder asks whether to replace an older copy, choose **Replace**.
4. Open `Codex Auth Helper` from `Applications`.

The release is unsigned. On first launch, macOS may show a warning. If that happens, right-click `Codex Auth Helper`, choose **Open**, then choose **Open** again.

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

## How To Use

1. Install `codex-auth`.
2. Open Codex Auth Helper.
3. Click **Login** if you need to sign in to Codex.
4. Use **Save / Update Login** to save the auth file. The default path is `~/.codex/auth.json`. Add an alias for a new account, or leave the alias blank to update an existing saved account.
5. Click **List Accounts** to check saved accounts.
6. Click **Health Check** when you want to refresh saved ChatGPT logins that have not been refreshed in the last 24 hours. It skips recent accounts and API-key accounts, refreshes one account at a time, and writes each new refresh token immediately.
7. Click **Switch Account**, type the alias in the terminal input, then press Return.
8. Click **Restart Codex** so Codex App fully exits and reopens with the selected account.

Health Check helps reduce local stale-token problems. It cannot prevent OpenAI from expiring or revoking a token, or from asking you to verify your login again. If an account needs login again, use **Login**, then **Save / Update Login**.

If Codex App is not installed at `/Applications/Codex.app`, open **Codex Auth Helper > Settings** and update the Codex resources path. The default is `/Applications/Codex.app/Contents/Resources`.

Use **Remove Account** when you want to delete a saved account from `codex-auth`. The app prepares `codex-auth remove`; type the alias in the terminal input, then press Return.

## Built On codex-auth

This app is powered by [`loongphy/codex-auth`](https://github.com/loongphy/codex-auth), the original command-line tool for switching and managing Codex accounts.

Codex Auth Helper does not replace `codex-auth`. It makes the common `codex-auth` workflows easier to use from a macOS app.
