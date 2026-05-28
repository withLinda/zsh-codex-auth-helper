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

test_development_signing_args_default_to_linda_identity
test_development_signing_args_allow_overrides
test_distribution_signing_args_use_developer_id_identity
test_distribution_signing_args_fail_without_developer_id
test_verify_app_signature_rejects_adhoc_signature
test_release_script_fails_cleanly_without_developer_id

echo "signing_common tests passed"
