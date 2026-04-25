#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$ROOT_DIR/install.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$INSTALL_SH" ]] || fail "install.sh should exist"

bash -n "$INSTALL_SH"

assert_contains() {
  local needle="$1"
  grep -Fq -- "$needle" "$INSTALL_SH" || fail "install.sh should contain: $needle"
}

assert_contains 'MAXAPI_ROOT="${HOME}/.maxapi"'
assert_contains 'NPM_PREFIX="${MAXAPI_ROOT}/npm-global"'
assert_contains 'LOCK_PATH="${MAXAPI_ROOT}/install.lock"'
assert_contains '--repair'
assert_contains '--uninstall'
assert_contains 'MAX API CLI Installer'
assert_contains 'registry.npmmirror.com'
assert_contains 'registry.npmjs.org'
assert_contains '@anthropic-ai/claude-code'
assert_contains '@openai/codex'
assert_contains '@google/gemini-cli'
assert_contains 'wait_for_package_manager_locks'
assert_contains 'install_user_node'
assert_contains 'write_shell_profile_block'
assert_contains 'run_actual_call_tests'

printf 'install.sh static checks passed\n'
