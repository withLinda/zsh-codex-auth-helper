# Codex Auth Helper

**Codex Auth Helper** is a small macOS app for managing Codex accounts without memorizing `codex-auth` commands.

It gives Codex App users a simple interface for login, import, switch, list, remove, and restart flows, while still showing the real terminal output so you always know what is happening.

## Why Use It

- Switch Codex accounts faster from a desktop app.
- Use `codex-auth` without typing the same commands again and again.
- Import an auth file with a clear alias, such as `main`, `work`, or `personal`.
- See command output inside the app, including prompts you may need to answer.
- Open detected login links from the built-in terminal panel.
- Restart Codex App after switching so the new account takes effect, with a safer wait before reopening.

Think of it as a control panel for `codex-auth`: the app gives you buttons and a terminal view, while `codex-auth` still does the account management.

## Features

- **Login**: runs `codex login --device-auth`.
- **Import Auth**: imports an auth JSON file and saves it with an alias.
- **Switch Account**: opens the interactive account switch flow.
- **List Accounts**: shows accounts managed by `codex-auth`.
- **Remove Account**: starts the remove flow after a confirmation.
- **Restart Codex**: quits Codex App, waits for its helper processes to exit, and then reopens it after account changes.
- **Interactive terminal**: send input to running commands from the app.
- **Link detection**: open the latest detected login link with one click.
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

### Prebuilt App

If a prebuilt release is available, download the `.app` from this repository's Releases page, move it to `Applications`, and open it.

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
4. Use **Import Auth** to save an auth file with an alias. The default path is `~/.codex/auth.json`.
5. Click **List Accounts** to check saved accounts.
6. Click **Switch Account** and follow the terminal prompt.
7. Click **Restart Codex** so Codex App fully exits and reopens with the selected account.

If Codex App is not installed at `/Applications/Codex.app`, open **Codex Auth Helper > Settings** and update the Codex resources path. The default is `/Applications/Codex.app/Contents/Resources`.

Use **Remove Account** when you want to delete a saved account from `codex-auth`. The app asks for confirmation before starting the remove flow.

## Built On codex-auth

This app is powered by [`loongphy/codex-auth`](https://github.com/loongphy/codex-auth), the original command-line tool for switching and managing Codex accounts.

Codex Auth Helper does not replace `codex-auth`. It makes the common `codex-auth` workflows easier to use from a macOS app.
