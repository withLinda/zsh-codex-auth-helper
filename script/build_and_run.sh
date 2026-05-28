#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ZshCodexAuthHelper"
SCHEME="ZshCodexAuthHelper"
PROJECT="ZshCodexAuthHelper.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
BUNDLE_ID="com.linda.zsh-codexauth-helper"

cd "$ROOT_DIR"

# shellcheck source=script/signing_common.sh
source "$ROOT_DIR/script/signing_common.sh"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

build_app() {
  require_development_signing_identity

  local signing_args_output
  signing_args_output="$(development_signing_args)"

  local signing_args=()
  local arg
  while IFS= read -r arg; do
    signing_args+=("$arg")
  done <<<"$signing_args_output"

  xcodegen generate >/dev/null
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    "${signing_args[@]}" \
    build

  verify_app_signature "$APP_BUNDLE"
}

open_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_BUNDLE"
}

build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
