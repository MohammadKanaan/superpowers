#!/usr/bin/env bash
# Tests for hooks/check-scaffolding (the Stop hook that blocks completion
# while SCAFFOLD: markers remain in changed test files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/check-scaffolding"

FAILURES=0
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
    echo "  [PASS] $1"
}

fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

git_init() {
    local dir="$1"
    git -C "$dir" init -q
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name test
}

git_commit_all() {
    local dir="$1"
    git -C "$dir" add -A
    git -C "$dir" commit -qm init
}

HOOK_CODE=0
HOOK_ERR=""

invoke() {
    local dir="$1"
    local input="${2-}"
    : >"$TEST_ROOT/err"
    set +e
    (
        cd "$dir" && printf '%s' "$input" | bash "$HOOK"
    ) >/dev/null 2>"$TEST_ROOT/err"
    HOOK_CODE=$?
    set -e
    HOOK_ERR="$(cat "$TEST_ROOT/err")"
}

assert_code() {
    local want="$1"
    local description="$2"
    if [ "$HOOK_CODE" = "$want" ]; then
        pass "$description"
    else
        fail "$description (want exit $want, got $HOOK_CODE)"
    fi
}

assert_err_contains() {
    local needle="$1"
    local description="$2"
    if printf '%s' "$HOOK_ERR" | grep -q -- "$needle"; then
        pass "$description"
    else
        fail "$description (stderr missing '$needle')"
        printf '%s\n' "$HOOK_ERR" | sed 's/^/      /'
    fi
}

echo "check-scaffolding"

# 1. A changed test file with no marker passes.
dir="$TEST_ROOT/clean"
mkdir -p "$dir/test"
printf 'test("x", () => {});\n' >"$dir/test/a.test.js"
git_init "$dir"
invoke "$dir"
assert_code 0 "clean changed test file passes"

# 2. An untracked test file carrying the marker blocks.
dir="$TEST_ROOT/untracked"
mkdir -p "$dir/test"
printf '// SCAFFOLD: delete before completion\n' >"$dir/test/a.test.js"
git_init "$dir"
invoke "$dir"
assert_code 2 "untracked marker blocks"
assert_err_contains "test/a.test.js" "block message names the file"

# 3. A tracked test file modified to add the marker blocks.
dir="$TEST_ROOT/modified"
mkdir -p "$dir/test"
printf 'test("x", () => {});\n' >"$dir/test/a.test.js"
git_init "$dir"
git_commit_all "$dir"
printf '// SCAFFOLD: delete before completion\n' >>"$dir/test/a.test.js"
invoke "$dir"
assert_code 2 "modified tracked marker blocks"

# 4. A marker committed and unchanged is out of scope.
dir="$TEST_ROOT/committed"
mkdir -p "$dir/test"
printf '// SCAFFOLD: historical\n' >"$dir/test/a.test.js"
git_init "$dir"
git_commit_all "$dir"
invoke "$dir"
assert_code 0 "unchanged committed marker is ignored"

# 5. Markdown is excluded, so docs describing the marker do not self-flag.
dir="$TEST_ROOT/docs"
mkdir -p "$dir"
printf 'Use `SCAFFOLD: delete before completion`.\n' >"$dir/notes.md"
git_init "$dir"
invoke "$dir"
assert_code 0 "markdown is excluded"

# 6. Non-test source files carrying the marker are ignored.
dir="$TEST_ROOT/src"
mkdir -p "$dir/src"
printf '// SCAFFOLD: not a test\n' >"$dir/src/a.js"
git_init "$dir"
invoke "$dir"
assert_code 0 "non-test file is ignored"

# 7. The loop guard lets the harness stop after a block.
dir="$TEST_ROOT/loop"
mkdir -p "$dir/test"
printf '// SCAFFOLD: delete before completion\n' >"$dir/test/a.test.js"
git_init "$dir"
invoke "$dir" '{"stop_hook_active": true}'
assert_code 0 "stop_hook_active allows the stop"

# 8. Outside a git repository there is nothing to scope to.
dir="$TEST_ROOT/nogit"
mkdir -p "$dir/test"
printf '// SCAFFOLD: delete before completion\n' >"$dir/test/a.test.js"
invoke "$dir"
assert_code 0 "non-git directory passes"

# 9. The marker only counts at a comment position. A test that builds
#    scaffolding fixtures (or documents the marker) writes the literal into
#    a string, and must not flag itself.
dir="$TEST_ROOT/stringlit"
mkdir -p "$dir/test"
printf 'const fixture = "// SCAFFOLD: not a real marker";\nprintf("# SCAFFOLD: nope");\ntest("x", () => {});\n' >"$dir/test/a.test.js"
git_init "$dir"
invoke "$dir"
assert_code 0 "marker inside a string literal is ignored"

# 10. Anchoring must not lose real markers: indented and block comments.
dir="$TEST_ROOT/anchored"
mkdir -p "$dir/test"
printf 'test("x", () => {\n  //   SCAFFOLD: delete before completion\n  /* SCAFFOLD: block form */\n});\n' >"$dir/test/a.test.js"
git_init "$dir"
invoke "$dir"
assert_code 2 "indented and block-comment markers still block"

echo
if [ "$FAILURES" -eq 0 ]; then
    echo "All check-scaffolding tests passed."
else
    echo "$FAILURES check-scaffolding test(s) failed."
    exit 1
fi
