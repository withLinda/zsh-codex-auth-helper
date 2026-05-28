#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=script/signing_common.sh
source "$ROOT_DIR/script/signing_common.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

assert_fails() {
  if "$@" >/tmp/signing-common-test.out 2>/tmp/signing-common-test.err; then
    fail "expected command to fail: $*"
  fi
}

fake_identity_tools_dir() {
  local fake_bin
  fake_bin="$(mktemp -d)"
  cat >"$fake_bin/security" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
  1) 1111111111111111111111111111111111111111 "Apple Development: Linda Fitriani (HD45P449D9)"
  2) 2222222222222222222222222222222222222222 "Developer ID Application: Linda Fitriani (HD45P449D9)"
     2 valid identities found
OUT
SH
  chmod +x "$fake_bin/security"
  echo "$fake_bin"
}

test_development_signing_args_default_to_linda_identity() {
  local output
  output="$(
    unset DEVELOPMENT_TEAM CODE_SIGN_IDENTITY
    development_signing_args
  )"

  assert_contains "$output" "CODE_SIGN_STYLE=Manual"
  assert_contains "$output" "CODE_SIGN_IDENTITY=Apple Development: Linda Fitriani (HD45P449D9)"
}

test_development_signing_args_allow_overrides() {
  local output
  output="$(DEVELOPMENT_TEAM=TEAM123 CODE_SIGN_IDENTITY='Apple Development: Example (TEAM123)' development_signing_args)"

  assert_contains "$output" "DEVELOPMENT_TEAM=TEAM123"
  assert_contains "$output" "CODE_SIGN_IDENTITY=Apple Development: Example (TEAM123)"
}

test_distribution_signing_args_use_developer_id_identity() {
  local fake_bin output
  fake_bin="$(fake_identity_tools_dir)"
  output="$(
    PATH="$fake_bin:$PATH"
    hash -r
    unset DEVELOPMENT_TEAM CODE_SIGN_IDENTITY
    distribution_signing_args
  )"

  assert_contains "$output" "CODE_SIGN_STYLE=Manual"
  assert_contains "$output" "CODE_SIGN_IDENTITY=Developer ID Application: Linda Fitriani (HD45P449D9)"
  assert_contains "$output" "OTHER_CODE_SIGN_FLAGS=--timestamp"
}

test_distribution_signing_args_fail_without_developer_id() {
  local fake_bin
  fake_bin="$(mktemp -d)"
  cat >"$fake_bin/security" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
  1) 1111111111111111111111111111111111111111 "Apple Development: Linda Fitriani (HD45P449D9)"
     1 valid identities found
OUT
SH
  chmod +x "$fake_bin/security"

  if (
    PATH="$fake_bin:$PATH"
    hash -r
    unset DEVELOPMENT_TEAM CODE_SIGN_IDENTITY
    distribution_signing_args
  ) >/tmp/signing-common-test.out 2>/tmp/signing-common-test.err; then
    fail "expected distribution_signing_args to fail without Developer ID identity"
  fi
}

test_release_signing_args_allows_development_signed_release_when_requested() {
  local fake_bin output
  fake_bin="$(mktemp -d)"
  cat >"$fake_bin/security" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
  1) 1111111111111111111111111111111111111111 "Apple Development: Linda Fitriani (HD45P449D9)"
     1 valid identities found
OUT
SH
  chmod +x "$fake_bin/security"

  output="$(
    PATH="$fake_bin:$PATH"
    hash -r
    unset DEVELOPMENT_TEAM CODE_SIGN_IDENTITY
    ALLOW_DEVELOPMENT_SIGNED_RELEASE=1 release_signing_args
  )"

  assert_contains "$output" "CODE_SIGN_STYLE=Manual"
  assert_contains "$output" "CODE_SIGN_IDENTITY=Apple Development: Linda Fitriani (HD45P449D9)"
}

test_verify_app_signature_rejects_adhoc_signature() {
  local fake_bin app_dir
  fake_bin="$(mktemp -d)"
  app_dir="$(mktemp -d)/ZshCodexAuthHelper.app"
  mkdir -p "$app_dir"

  cat >"$fake_bin/codesign" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"--verify"* ]]; then
  exit 0
fi
cat <<'OUT'
Signature=adhoc
TeamIdentifier=not set
Info.plist=not bound
Sealed Resources=none
OUT
SH
  cat >"$fake_bin/spctl" <<'SH'
#!/usr/bin/env bash
echo "source=no usable signature"
exit 3
SH
  chmod +x "$fake_bin/codesign" "$fake_bin/spctl"

  if (
    PATH="$fake_bin:$PATH"
    hash -r
    verify_app_signature "$app_dir"
  ) >/tmp/signing-common-test.out 2>/tmp/signing-common-test.err; then
    fail "expected verify_app_signature to fail for ad-hoc signature"
  fi
}

test_verify_app_signature_rejects_developer_id_without_timestamp() {
  local fake_bin app_dir
  fake_bin="$(mktemp -d)"
  app_dir="$(mktemp -d)/ZshCodexAuthHelper.app"
  mkdir -p "$app_dir"

  cat >"$fake_bin/codesign" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"--verify"* ]]; then
  exit 0
fi
cat <<'OUT'
CodeDirectory v=20400 size=2850 flags=0x10000(runtime) hashes=82+3 location=embedded
Authority=Developer ID Application: Example (TEAM123)
TeamIdentifier=TEAM123
Info.plist entries=21
Sealed Resources version=2 rules=13 files=0
OUT
SH
  cat >"$fake_bin/spctl" <<'SH'
#!/usr/bin/env bash
echo "source=Unnotarized Developer ID"
exit 3
SH
  chmod +x "$fake_bin/codesign" "$fake_bin/spctl"

  if (
    PATH="$fake_bin:$PATH"
    hash -r
    verify_app_signature "$app_dir"
  ) >/tmp/signing-common-test.out 2>/tmp/signing-common-test.err; then
    fail "expected verify_app_signature to fail for Developer ID signature without timestamp"
  fi
}

test_verify_app_signature_rejects_developer_id_without_hardened_runtime() {
  local fake_bin app_dir
  fake_bin="$(mktemp -d)"
  app_dir="$(mktemp -d)/ZshCodexAuthHelper.app"
  mkdir -p "$app_dir"

  cat >"$fake_bin/codesign" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"--verify"* ]]; then
  exit 0
fi
cat <<'OUT'
CodeDirectory v=20400 size=2850 flags=0x0(none) hashes=82+3 location=embedded
Authority=Developer ID Application: Example (TEAM123)
TeamIdentifier=TEAM123
Timestamp=May 28, 2026 at 9:00:00 PM
Info.plist entries=21
Sealed Resources version=2 rules=13 files=0
OUT
SH
  cat >"$fake_bin/spctl" <<'SH'
#!/usr/bin/env bash
echo "source=Unnotarized Developer ID"
exit 3
SH
  chmod +x "$fake_bin/codesign" "$fake_bin/spctl"

  if (
    PATH="$fake_bin:$PATH"
    hash -r
    verify_app_signature "$app_dir"
  ) >/tmp/signing-common-test.out 2>/tmp/signing-common-test.err; then
    fail "expected verify_app_signature to fail for Developer ID signature without hardened runtime"
  fi
}

test_project_enables_hardened_runtime_for_release_readiness() {
  if ! grep -q 'ENABLE_HARDENED_RUNTIME: YES' "$ROOT_DIR/project.yml"; then
    fail "expected project.yml to enable hardened runtime"
  fi
}

test_release_script_fails_cleanly_without_developer_id() {
  local fake_bin output status
  fake_bin="$(mktemp -d)"

  cat >"$fake_bin/security" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
  1) 1111111111111111111111111111111111111111 "Apple Development: Linda Fitriani (HD45P449D9)"
     1 valid identities found
OUT
SH
  cat >"$fake_bin/xcodegen" <<'SH'
#!/usr/bin/env bash
echo "xcodegen should not be called" >&2
exit 99
SH
  cat >"$fake_bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
echo "xcodebuild should not be called" >&2
exit 99
SH
  chmod +x "$fake_bin/security" "$fake_bin/xcodegen" "$fake_bin/xcodebuild"

  set +e
  output="$(
    {
      PATH="$fake_bin:$PATH"
      hash -r
      "$ROOT_DIR/script/build_release_dmg.sh" 2099.01.01.1
    } 2>&1
  )"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "expected release script to fail without Developer ID identity"
  assert_contains "$output" "No Developer ID Application signing identity found."
  assert_contains "$output" "Refusing to create an unsigned or ad-hoc release DMG."
  assert_not_contains "$output" "unbound variable"
  assert_not_contains "$output" "xcodegen should not be called"
  assert_not_contains "$output" "xcodebuild should not be called"
}

test_release_script_codesigns_created_dmg() {
  local fake_bin version sign_log dmg_path
  fake_bin="$(mktemp -d)"
  version="2099.01.02.1"
  sign_log="$(mktemp)"
  dmg_path="$ROOT_DIR/dist/CodexAuthHelper-v$version.dmg"

  cat >"$fake_bin/security" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
  1) 2222222222222222222222222222222222222222 "Developer ID Application: Linda Fitriani (HD45P449D9)"
     1 valid identities found
OUT
SH
  cat >"$fake_bin/xcodegen" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat >"$fake_bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
mkdir -p "build/DerivedData/Build/Products/Release/ZshCodexAuthHelper.app"
exit 0
SH
  cat >"$fake_bin/codesign" <<SH
#!/usr/bin/env bash
if [[ "\$*" == *"--verify"* ]]; then
  exit 0
fi
if [[ "\$*" == *".dmg"* ]]; then
  printf '%s\\n' "\$*" >> "$sign_log"
  exit 0
fi
cat <<'OUT'
CodeDirectory v=20500 size=2858 flags=0x10000(runtime) hashes=82+3 location=embedded
Authority=Developer ID Application: Example (TEAM123)
TeamIdentifier=TEAM123
Timestamp=May 28, 2026 at 9:00:00 PM
Info.plist entries=21
Sealed Resources version=2 rules=13 files=0
OUT
SH
  cat >"$fake_bin/spctl" <<'SH'
#!/usr/bin/env bash
echo "accepted"
exit 0
SH
  cat >"$fake_bin/hdiutil" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "create" ]]; then
  printf 'fake dmg' > "${@: -1}"
fi
exit 0
SH
  chmod +x "$fake_bin/security" "$fake_bin/xcodegen" "$fake_bin/xcodebuild" "$fake_bin/codesign" "$fake_bin/spctl" "$fake_bin/hdiutil"

  rm -f "$dmg_path" "$dmg_path.sha256"
  (
    PATH="$fake_bin:$PATH"
    hash -r
    "$ROOT_DIR/script/build_release_dmg.sh" "$version"
  ) >/tmp/signing-common-test.out 2>/tmp/signing-common-test.err

  local output
  output="$(cat "$sign_log")"
  assert_contains "$output" "--sign Developer ID Application: Linda Fitriani (HD45P449D9)"
  assert_contains "$output" "--timestamp"
  assert_contains "$output" "$dmg_path"
}

test_development_signing_args_default_to_linda_identity
test_development_signing_args_allow_overrides
test_distribution_signing_args_use_developer_id_identity
test_distribution_signing_args_fail_without_developer_id
test_release_signing_args_allows_development_signed_release_when_requested
test_verify_app_signature_rejects_adhoc_signature
test_verify_app_signature_rejects_developer_id_without_timestamp
test_verify_app_signature_rejects_developer_id_without_hardened_runtime
test_project_enables_hardened_runtime_for_release_readiness
test_release_script_fails_cleanly_without_developer_id
test_release_script_codesigns_created_dmg

echo "signing_common tests passed"
