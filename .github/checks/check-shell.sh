#!/usr/bin/env bash
#
# Shell hygiene for committed *.sh:
#   - `bash -n` (parses) on EVERY tracked .sh, always;
#   - ShellCheck (static analysis) on the MAINTAINED scripts — closed-loop harnesses
#     and these check scripts — when the binary is present. CI installs it; a local run
#     without it still gets the syntax gate and says ShellCheck was skipped rather than
#     lying that it passed.
#
# Two deliberate scope calls:
#   - ShellCheck runs at `--severity=info`: error/warning/info block, only pure `style`
#     nags (SC2001 "prefer ${x//}" and the like) do not. `info` is deliberate, not the
#     looser `warning`: the quoting checks that actually bit this project — SC2086,
#     unquoted expansion that word-splits — are `info`-level in ShellCheck, so a
#     `warning` gate would miss exactly the class it exists to catch. Excluding `style`
#     drops preferences, not defects — the FI-1/FI-2 line that a gate reddening on
#     non-bugs gets deleted, without lowering past the real ones.
#   - ShellCheck skips `records/**`: those are write-once historical artifacts
#     (probe scripts captured from hardware), not maintained code. `bash -n` still
#     covers them, so a committed record that does not even parse is still caught.
#
# The closed-loop harnesses are the reason this matters: they are shell, span every
# repo, and a syntax error or an unquoted expansion in one is invisible until a human
# runs it against hardware that costs money. Written from the failure: a syntax error
# makes `bash -n` exit non-zero naming the file.
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

all=()
while IFS= read -r f; do all+=("$f"); done < <(git ls-files '*.sh')
if [ "${#all[@]}" -eq 0 ]; then
  echo "no .sh files tracked"; exit 0
fi

rc=0

echo "bash -n (${#all[@]} files):"
for f in "${all[@]}"; do
  if ! err=$(bash -n "$f" 2>&1); then
    echo "  FAIL $f"; echo "    $err"; rc=1
  fi
done
[ $rc -eq 0 ] && echo "  all parse."

# Maintained scripts only for ShellCheck: everything tracked except records/ artifacts.
maintained=()
for f in "${all[@]}"; do
  case "$f" in
    records/*) ;;            # write-once artifact — bash -n above still ran on it
    *) maintained+=("$f") ;;
  esac
done

if command -v shellcheck >/dev/null 2>&1; then
  # --exclude=SC1091: "Not following: _preflight.sh". The harnesses `. ./_preflight.sh`
  # with a path relative to their own directory, resolved at runtime; ShellCheck resolves
  # statically from the invocation dir and cannot see it, so it emits SC1091 (info) for a
  # file that exists and runs fine. Excluding that one code is not the same as dropping to
  # `warning` — every other info check, SC2086 quoting included, still blocks.
  echo "shellcheck --severity=info --exclude=SC1091 (${#maintained[@]} maintained scripts):"
  if ! shellcheck --severity=info --exclude=SC1091 "${maintained[@]}"; then
    rc=1
  else
    echo "  clean."
  fi
else
  echo "shellcheck: SKIPPED (not installed) — the bash -n syntax gate above still ran."
fi

exit $rc
