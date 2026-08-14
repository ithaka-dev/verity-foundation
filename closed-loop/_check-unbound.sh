#!/usr/bin/env bash
#
# Find variables a closed-loop script *uses* but never *assigns*.
#
# ## Why this exists
#
# `08-gateway-tls-termination.sh` referenced `$verifier` twice and defined it nowhere. Under
# `set -euo pipefail` that aborts the run — so steps 7 through 11, the entire end-to-end
# demonstration of CR-1 and MA-1, were unreachable. The same commit also read `$work/att.json`,
# a file nothing in that script ever created.
#
# Both survived `bash -n`, which checks syntax and not liveness. Both survived review. They were
# caught only when a reviewer read the script line by line and noticed the assignment was absent —
# which is not a process that scales, and is the second time in this directory that a harness could
# not have done what it claimed (see `2026-08-04-checks-that-did-not-run.md`).
#
# These scripts cost money to run. A defect that aborts one after a CVM is deployed is paid for
# twice: once in the deploy, once in the re-run.
#
# ## What it is not
#
# **`shellcheck` subsumes this entirely and should replace it.** SC2154 is exactly this check, and
# shellcheck also catches the quoting, subshell and exit-code traps this does not. It is not
# installed on the machine these are run from, and adding a dependency to a script an operator runs
# by hand is its own cost — so this is the narrow, zero-dependency stopgap for the one defect that
# has actually bitten. If shellcheck arrives, delete this.
#
#   ./_check-unbound.sh          # all scripts here
#   ./_check-unbound.sh 08*.sh   # or named ones
set -euo pipefail

cd "$(dirname "$0")"
python3 - "$@" <<'PY'
import re, sys, glob

# Shell builtins and environment that are always defined.
ENV = {
    "HOME", "PATH", "PWD", "USER", "SHELL", "SECONDS", "RANDOM", "PIPESTATUS", "BASH_SOURCE",
    "IFS", "LINENO", "OSTYPE", "FUNCNAME", "EUID", "PPID", "BASHPID", "TMPDIR", "LANG", "LC_ALL",
    "REPLY", "BASH_REMATCH",
}

targets = sys.argv[1:] or sorted(glob.glob("*.sh"))
bad = 0

for path in targets:
    src = open(path).read()

    # Heredocs carry python and shell payloads whose variables belong to another language. Strip
    # them: a `$foo` inside an embedded python program is not a shell variable, and treating it as
    # one produced enough noise in the first version of this check to hide the real finding.
    body = re.sub(r"<<-?\s*'?(\w+)'?\n.*?\n\s*\1\b", "\n", src, flags=re.S)

    # Comments mention variables while explaining them — including this file's own header, which
    # names `$verifier` as the bug it was written for. Counting a comment as a use makes the check
    # flag documentation, and a checker that cries wolf is one people stop reading.
    code = "\n".join(re.sub(r"(?<!\\)#.*$", "", ln) for ln in body.splitlines())

    used = set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", code))

    # `source`d files supply variables too. `_preflight.sh` requires VERITY_CVM_ID with `:?` and
    # aborts if it is unset, so by the time 02/03 reference it bare, it is guaranteed — treating it
    # as unassigned would report the opposite of the truth.
    for inc in re.findall(r"^\s*(?:source|\.)\s+\"?[^\"\n]*?([A-Za-z0-9_.-]+\.sh)", body, re.M):
        try:
            extra = open(inc).read()
        except OSError:
            continue
        used -= set(re.findall(r':\s*"?\$\{([A-Za-z_][A-Za-z0-9_]*):[?=]', extra))
        used -= set(re.findall(r"^\s*(?:local\s+|export\s+)?([A-Za-z_][A-Za-z0-9_]*)=", extra, re.M))

    body = code
    assigned = set()
    assigned |= set(re.findall(r"^\s*(?:local\s+|export\s+|declare\s+)?([A-Za-z_][A-Za-z0-9_]*)=", body, re.M))
    # `local a="$1" b="$2" c` — every name on the line, not just the first.
    for line in re.findall(r"^\s*(?:local|declare|export)\s+(.*)$", body, re.M):
        assigned |= set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)(?:=|\s|$)", line))
    assigned |= set(re.findall(r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b", body))
    for names in re.findall(r"\bread\s+(?:-r\s+)?([A-Za-z_][A-Za-z0-9_ ]*)", body):
        assigned |= set(names.split())
    assigned |= set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(\)", body))          # function names
    assigned |= set(re.findall(r':\s*"?\$\{([A-Za-z_][A-Za-z0-9_]*):=', body))     # : "${VAR:=default}"

    # `${VAR:-default}`, `${VAR:+x}`, `${VAR:?msg}` are safe under `set -u` by construction.
    guarded = set(re.findall(r"\$\{([A-Za-z_][A-Za-z0-9_]*):[-+?]", body))

    unknown = sorted(used - assigned - ENV - guarded)
    if unknown:
        bad += 1
        print(f"{path}: used but never assigned -> {', '.join('$' + u for u in unknown)}")
        for u in unknown:
            for n, line in enumerate(src.splitlines(), 1):
                if re.search(r"\$\{?" + re.escape(u) + r"\b", line):
                    print(f"    {path}:{n}: {line.strip()[:96]}")
                    break
    else:
        print(f"{path}: clean")

if bad:
    print(f"\n{bad} script(s) reference a variable that is never assigned.")
    print("Under `set -u` each aborts at the first such use — after any CVM it had already deployed.")
    sys.exit(1)
PY
