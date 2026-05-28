#!/usr/bin/env bash

DEFAULT_DEVELOPMENT_IDENTITY="Apple Development: Linda Fitriani (HD45P449D9)"

signing_error() {
  echo "error: $*" >&2
}

signing_warning() {
  echo "warning: $*" >&2
}

codesigning_identities() {
  security find-identity -p codesigning -v
}

identity_exists() {
  local identity="$1"
  codesigning_identities | grep -F "\"$identity\"" >/dev/null
}

development_identity() {
  printf '%s\n' "${CODE_SIGN_IDENTITY:-$DEFAULT_DEVELOPMENT_IDENTITY}"
}

development_team() {
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] || return 1
  printf '%s\n' "$DEVELOPMENT_TEAM"
}

require_codesigning_identity() {
  local identity="$1"
  if ! identity_exists "$identity"; then
    signing_error "Code signing identity not found: $identity"
    signing_error "Run 'security find-identity -p codesigning -v' to see available identities."
    return 1
  fi
}

require_development_signing_identity() {
  require_codesigning_identity "$(development_identity)"
}

developer_id_identity() {
  if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    if [[ "$CODE_SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
      signing_error "Release builds require a Developer ID Application identity."
      signing_error "Current CODE_SIGN_IDENTITY is: $CODE_SIGN_IDENTITY"
      return 1
    fi
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi

  local identity
  identity="$(codesigning_identities | awk -F\" '/"Developer ID Application:/ { print $2; exit }')"
  if [[ -z "$identity" ]]; then
    signing_error "No Developer ID Application signing identity found."
    signing_error "Refusing to create an unsigned or ad-hoc release DMG."
    signing_error "Install a Developer ID Application certificate, or set CODE_SIGN_IDENTITY to an exact Developer ID identity."
    return 1
  fi

  printf '%s\n' "$identity"
}

distribution_team() {
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] || return 1
  printf '%s\n' "$DEVELOPMENT_TEAM"
}

development_signing_args() {
  printf '%s\n' \
    "CODE_SIGN_STYLE=Manual" \
    "CODE_SIGN_IDENTITY=$(development_identity)"

  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    printf '%s\n' "DEVELOPMENT_TEAM=$(development_team)"
  fi
}

distribution_signing_args() {
  local identity
  identity="$(developer_id_identity)" || return 1
  require_codesigning_identity "$identity" || return 1

  printf '%s\n' \
    "CODE_SIGN_STYLE=Manual" \
    "CODE_SIGN_IDENTITY=$identity" \
    "OTHER_CODE_SIGN_FLAGS=--timestamp"

  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    printf '%s\n' "DEVELOPMENT_TEAM=$(distribution_team)"
  fi
}

release_signing_args() {
  local distribution_errors output status
  distribution_errors="$(mktemp)"

  if output="$(distribution_signing_args 2>"$distribution_errors")"; then
    rm -f "$distribution_errors"
    printf '%s\n' "$output"
    return 0
  else
    status=$?
  fi

  if [[ "${ALLOW_DEVELOPMENT_SIGNED_RELEASE:-}" != "1" ]]; then
    cat "$distribution_errors" >&2
    rm -f "$distribution_errors"
    return "$status"
  fi

  rm -f "$distribution_errors"
  signing_warning "No Developer ID Application identity was found."
  signing_warning "ALLOW_DEVELOPMENT_SIGNED_RELEASE=1 is set, so the DMG will be development-signed and not notarized."

  require_development_signing_identity || return 1
  development_signing_args
}

verify_app_signature() {
  local app_bundle="$1"
  if [[ ! -d "$app_bundle" ]]; then
    signing_error "App bundle not found: $app_bundle"
    return 1
  fi

  local codesign_details
  if ! codesign_details="$(codesign -dvvv --entitlements :- "$app_bundle" 2>&1)"; then
    signing_error "codesign could not read signature for $app_bundle"
    echo "$codesign_details" >&2
    return 1
  fi

  if grep -q 'Signature=adhoc' <<<"$codesign_details"; then
    signing_error "App is ad-hoc signed. TCC will not remember Files and Folders permission reliably."
    return 1
  fi

  if grep -q 'TeamIdentifier=not set' <<<"$codesign_details"; then
    signing_error "App signature has no TeamIdentifier."
    return 1
  fi

  if grep -q 'Info.plist=not bound' <<<"$codesign_details"; then
    signing_error "App Info.plist is not sealed by the code signature."
    return 1
  fi

  if grep -q 'Sealed Resources=none' <<<"$codesign_details"; then
    signing_error "App bundle resources are not sealed by the code signature."
    return 1
  fi

  if grep -q 'Authority=Developer ID Application:' <<<"$codesign_details"; then
    if ! grep -q '^Timestamp=' <<<"$codesign_details"; then
      signing_error "Developer ID app signature has no secure timestamp."
      return 1
    fi

    if ! grep -q 'flags=.*runtime' <<<"$codesign_details"; then
      signing_error "Developer ID app signature is missing hardened runtime."
      return 1
    fi
  fi

  if ! codesign --verify --strict --verbose=4 "$app_bundle"; then
    signing_error "Strict code-signature verification failed for $app_bundle"
    return 1
  fi

  local spctl_output
  spctl_output="$(spctl -a -vv "$app_bundle" 2>&1 || true)"
  if grep -q 'source=no usable signature' <<<"$spctl_output"; then
    signing_error "Gatekeeper reports no usable signature for $app_bundle"
    echo "$spctl_output" >&2
    return 1
  fi
}
