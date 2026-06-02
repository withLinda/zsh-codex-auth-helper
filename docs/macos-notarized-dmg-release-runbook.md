# macOS Notarized DMG Release Runbook

This guide is for any macOS app that you want to distribute outside the Mac App Store.

Use it when you want users to download a `.dmg`, open it, drag the app to
Applications, and run it without Gatekeeper warnings.

## When to use this guide

Use this guide when:

- You are shipping a macOS app outside the Mac App Store.
- You want to publish a `.dmg` file on GitHub Releases, your website, or another download page.
- You have an Apple Developer account.
- You have a `Developer ID Application` certificate.
- You want the release to pass Apple's notarization and Gatekeeper checks.

Do not use this guide for Mac App Store distribution. The Mac App Store uses a different signing and upload flow.

## Big picture

Think of this process like preparing a sealed package:

- The app is the item inside the package.
- The DMG is the package.
- Code signing writes your trusted sender name on the item and the package.
- Notarization asks Apple to inspect the package.
- Stapling attaches Apple's approval ticket to the package.
- Gatekeeper verification checks the final package before users open it.

These are separate steps:

- `Apple Development` certificate is for local development and testing.
- `Developer ID Application` certificate is for public distribution outside the Mac App Store.
- Hardened Runtime is needed for notarization.
- A secure timestamp is needed for notarization.
- The app inside the DMG must be signed.
- The DMG itself should also be signed before notarization.
- The notarization ticket must be stapled after Apple accepts the DMG.
- The checksum must be regenerated after stapling, because stapling changes the DMG file.

The correct order is:

1. Build the app.
2. Sign the app.
3. Create the DMG.
4. Sign the DMG.
5. Notarize the DMG.
6. Staple the DMG.
7. Regenerate the checksum.
8. Verify the final DMG.
9. Publish the final DMG and checksum.

## Placeholders used in this guide

Replace these values before running the commands:

```bash
APP_NAME="ExampleApp"
VERSION="1.2.3"
TEAM_ID="ABCDE12345"
DEVELOPER_ID_NAME="Developer ID Application: Your Name ($TEAM_ID)"
NOTARY_PROFILE="example-notary"

RELEASE_DIR="$PWD/dist"
STAGING_DIR="$PWD/build/dmg-staging"
APP_BUNDLE="$PWD/build/Release/$APP_NAME.app"
DMG_PATH="$RELEASE_DIR/$APP_NAME-v$VERSION.dmg"
```

Placeholder meanings:

- `APP_NAME`: your app name.
- `APP_BUNDLE`: path to the built `.app` bundle.
- `DMG_PATH`: path where the final `.dmg` will be created.
- `VERSION`: release version.
- `TEAM_ID`: your Apple Developer Team ID.
- `DEVELOPER_ID_NAME`: the full Developer ID signing identity name.
- `NOTARY_PROFILE`: the Keychain profile name for Apple notarization credentials.

## One-time setup

### 1. Check installed signing identities

```bash
security find-identity -p codesigning -v
```

Look for a valid identity like this:

```text
Developer ID Application: Your Name (ABCDE12345)
```

For public distribution, use `Developer ID Application`, not `Apple Development`.

### 2. Confirm the certificate has a matching private key

Open **Keychain Access**, then check your certificate under **login** or **System**.

The certificate must expand and show a private key under it. If it does not have a private key, the Mac can see the certificate but cannot sign with it.

This is like having a printed ID card without the matching key. It proves the identity exists, but it cannot unlock signing.

If the identity does not appear in this command:

```bash
security find-identity -p codesigning -v
```

then one common cause is that the matching private key is missing. Fix it by importing a `.p12` that contains both certificate and private key, or by creating a new certificate from a certificate signing request on this Mac.

### 3. Store Apple notary credentials in Keychain

Run this once per machine:

```bash
xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "YOUR_APPLE_ID_EMAIL" --team-id "$TEAM_ID"
```

When prompted, enter an app-specific password from your Apple ID account.

Do not put Apple ID passwords, app-specific passwords, API keys, or other secrets in scripts, README files, release notes, or Git history.

## Step-by-step release runbook

### 1. Build a release app bundle

Build your app in Release mode. The exact command depends on your project.

For an Xcode project:

```bash
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$PWD/build/DerivedData" \
  build
```

For an Xcode archive:

```bash
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$PWD/build/$APP_NAME.xcarchive" \
  archive
```

After building, make sure `APP_BUNDLE` points to the actual `.app` bundle.

```bash
test -d "$APP_BUNDLE"
```

### 2. Sign the app with Developer ID

Use Developer ID signing, Hardened Runtime, and a secure timestamp:

```bash
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_NAME" "$APP_BUNDLE"
```

For Xcode projects, it is usually better to set these in build settings:

- `CODE_SIGN_IDENTITY` should use `Developer ID Application`.
- `DEVELOPMENT_TEAM` should use your `TEAM_ID`.
- `ENABLE_HARDENED_RUNTIME` should be `YES`.
- `OTHER_CODE_SIGN_FLAGS` should include `--timestamp`.

For complex apps with helpers, frameworks, command-line tools, or XPC services, sign nested code explicitly before signing the outer `.app`. The `--deep` command above is useful for a simple generic example, but explicit nested signing is easier to debug for larger apps.

### 3. Verify the signed app

```bash
codesign --verify --strict --verbose=4 "$APP_BUNDLE"
codesign -dvvv "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE"
```

Check for:

- `Authority=Developer ID Application`.
- `Timestamp=` is present.
- `flags=` includes `runtime`.
- The app does not include development-only entitlements such as `com.apple.security.get-task-allow` set to `true`.

### 4. Create the DMG

Create a clean staging folder, copy the app into it, and add an Applications shortcut:

```bash
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$RELEASE_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
```

### 5. Sign the DMG

Sign the DMG before notarization:

```bash
codesign --force --sign "$DEVELOPER_ID_NAME" --timestamp "$DMG_PATH"
```

Then verify the DMG signature:

```bash
codesign --verify --verbose=4 "$DMG_PATH"
codesign -dvvv "$DMG_PATH"
```

Before notarization, this Gatekeeper command may show `source=Unnotarized Developer ID`. That is expected before Apple accepts and you staple the ticket.

```bash
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
```

### 6. Submit the DMG to Apple notarization

```bash
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
```

If Apple accepts the submission, continue to stapling.

If Apple rejects it, get the log. Replace `SUBMISSION_ID` with the ID printed by `notarytool`:

```bash
xcrun notarytool log "SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" notarization-log.json
```

Open `notarization-log.json` and fix every error before submitting again.

### 7. Staple the accepted ticket to the DMG

```bash
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
```

Stapling changes the DMG file. Because of that, any checksum made before this step is now old and must be replaced.

### 8. Regenerate the checksum after stapling

```bash
(cd "$(dirname "$DMG_PATH")" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")
```

Verify the checksum:

```bash
(cd "$(dirname "$DMG_PATH")" && shasum -a 256 -c "$(basename "$DMG_PATH").sha256")
```

### 9. Verify the final DMG

Run these checks on the final stapled DMG:

```bash
codesign --verify --verbose=4 "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
hdiutil verify "$DMG_PATH"
```

The `spctl` result should say:

```text
accepted
source=Notarized Developer ID
```

Also test the app from the mounted DMG:

```bash
MOUNT_POINT="/Volumes/$APP_NAME"

hdiutil detach "$MOUNT_POINT" 2>/dev/null || true
hdiutil attach -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH"

codesign --verify --strict --verbose=4 "$MOUNT_POINT/$APP_NAME.app"
codesign -dvvv "$MOUNT_POINT/$APP_NAME.app"
spctl -a -vv "$MOUNT_POINT/$APP_NAME.app"

hdiutil detach "$MOUNT_POINT"
```

For GUI apps, also open the app from the mounted DMG on a clean Mac or a clean user account when possible.

### 10. Publish the final DMG and checksum

Publish only the final stapled DMG and the checksum generated after stapling.

For GitHub Releases, one possible command is:

```bash
gh release create "v$VERSION" \
  "$DMG_PATH" \
  "$DMG_PATH.sha256" \
  --title "$APP_NAME v$VERSION" \
  --notes "Release $VERSION"
```

If you already created the release, upload or replace the assets with the final stapled files:

```bash
gh release upload "v$VERSION" "$DMG_PATH" "$DMG_PATH.sha256" --clobber
```

## Common problems

### `source=Unnotarized Developer ID`

This means Gatekeeper sees a Developer ID signature, but it does not see a usable notarization ticket.

Fix:

1. Submit the DMG to Apple notarization.
2. Wait for `Accepted`.
3. Run `xcrun stapler staple "$DMG_PATH"`.
4. Run `xcrun stapler validate "$DMG_PATH"`.
5. Run `spctl` again on the final DMG.

### `source=no usable signature`

This usually means the DMG or app is not signed in a way Gatekeeper can use.

Fix:

1. Verify the app signature with `codesign --verify --strict --verbose=4 "$APP_BUNDLE"`.
2. Sign the app with `Developer ID Application`.
3. Create the DMG again.
4. Sign the DMG with `codesign --force --sign "$DEVELOPER_ID_NAME" --timestamp "$DMG_PATH"`.
5. Submit the signed DMG to notarization again.

Important: if Apple accepted an unsigned DMG, still sign the DMG and submit again. The final Gatekeeper check must pass on the exact DMG you publish.

### `code object is not signed at all`

This means the target file or bundle has no code signature.

Fix:

- If the error points to the app, sign the app before creating the DMG.
- If the error points to the DMG, sign the DMG before notarization.
- If the error points to nested code, sign that nested item before signing the outer app.

### Notarization rejected because Hardened Runtime is missing

Apple requires Hardened Runtime for Developer ID notarization.

Fix:

- In Xcode, set `ENABLE_HARDENED_RUNTIME=YES`.
- For manual signing, include `--options runtime`.

Example:

```bash
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_NAME" "$APP_BUNDLE"
```

### Notarization rejected because secure timestamp is missing

Apple needs a trusted signing time.

Fix:

- For manual signing, include `--timestamp`.
- For Xcode builds, add `--timestamp` to `OTHER_CODE_SIGN_FLAGS` when using Developer ID signing.

Example:

```bash
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_NAME" "$APP_BUNDLE"
codesign --force --sign "$DEVELOPER_ID_NAME" --timestamp "$DMG_PATH"
```

### Certificate exists but does not show in `security find-identity`

The matching private key is probably missing.

Fix:

- Import the `.p12` file that contains both the certificate and private key.
- Or create a new certificate from a certificate signing request on this Mac.
- Then run `security find-identity -p codesigning -v` again.

A `.cer` file alone is often not enough on a new Mac, because it may contain only the public certificate.

### Checksum fails after stapling

Stapling changes the DMG file, so the old checksum no longer matches.

Fix:

```bash
(cd "$(dirname "$DMG_PATH")" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")
```

Always create the checksum after stapling, not before.

### Notarization is accepted but users still see warnings

This usually means the file users downloaded is not the same final file that passed verification.

Fix:

1. Run `spctl` on the exact DMG you plan to publish.
2. Confirm it says `source=Notarized Developer ID`.
3. Regenerate the checksum after stapling.
4. Upload the stapled DMG and the new checksum.
5. Download the release asset and verify that downloaded copy too.

## Final release checklist

Use this checklist before publishing:

- `security find-identity -p codesigning -v` shows your `Developer ID Application` identity.
- The Developer ID certificate has a matching private key.
- Notary credentials are stored in Keychain.
- The app was built in Release mode.
- The app is signed with `Developer ID Application`.
- The app signature has Hardened Runtime.
- The app signature has a secure timestamp.
- The DMG was created from the signed app.
- The DMG is signed with `Developer ID Application`.
- Apple notarization returned `Accepted`.
- The notarization ticket was stapled to the DMG.
- The checksum was regenerated after stapling.
- `xcrun stapler validate "$DMG_PATH"` passes.
- `spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"` says `source=Notarized Developer ID`.
- `hdiutil verify "$DMG_PATH"` passes.
- The app inside the mounted DMG passes `codesign --verify --strict`.
- The published release contains the final stapled DMG and matching checksum.

## Short lesson from this repo

One important lesson from this release work is general for any macOS app:

Apple can accept a notarization submission, but the final DMG can still fail Gatekeeper if the DMG itself has no usable signature. Sign the app, create the DMG, sign the DMG, then notarize and staple that signed DMG.
