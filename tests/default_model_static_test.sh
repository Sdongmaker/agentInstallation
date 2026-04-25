#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'CODEX_MODEL="gpt-5.5"' "$ROOT_DIR/install.sh" || fail "install.sh should default Codex to gpt-5.5"
grep -Fq '$Script:CODEX_MODEL  = "gpt-5.5"' "$ROOT_DIR/install.ps1" || fail "install.ps1 should default Codex to gpt-5.5"
grep -Fq '| Codex CLI | OpenAI | gpt-5.5 | `codex` |' "$ROOT_DIR/README.md" || fail "README should document Codex gpt-5.5"
grep -Fq 'output_snippet' "$ROOT_DIR/install.sh" || fail "install.sh should use richer smoke-test output snippets"

if grep -R 'gpt-5.4' "$ROOT_DIR/install.sh" "$ROOT_DIR/install.ps1" "$ROOT_DIR/README.md" >/dev/null; then
  fail "gpt-5.4 should not remain in installer defaults or README"
fi

printf 'default model static checks passed\n'
