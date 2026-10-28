---
name: writing-shell-scripts
description: Default conventions for writing and changing Bash scripts, bats tests and Makefiles - strict mode and its gaps, quoting and arrays, temp files and traps, portability to macOS (bash 3.2, BSD sed and date, make 3.81), testing with stubbed commands, and the checks to run (shellcheck, bash -n, bats). Use it when creating or editing a .sh, .bash or .bats file, a Makefile or a script that runs in CI or on developer machines. The project's own conventions win where they differ.
paths:
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.bats"
  - "**/Makefile"
  - "**/*.mk"
---

# Writing shell scripts

## Before you start

- Read the project's existing scripts, `.shellcheckrc` and test setup. Match their shebang, helper functions and error style.
- Decide where the script runs: Linux only, macOS too, CI, inside containers. Portability rules below apply only when macOS is a target.
- If the script grows past roughly 150 lines, needs data structures or parses JSON beyond a `jq` call, suggest Go or Python instead.

## Basics

- `#!/usr/bin/env bash` (or `#!/bin/bash` if the project does) and `set -euo pipefail` at the top. For `/bin/sh` scripts, no bashisms at all.
- Know the gaps of `errexit`: it is off inside `if`, `&&`, `||` and functions called from them, and `local x="$(cmd)"` hides the failure of `cmd`. Declare and assign separately: `local x; x="$(cmd)"`.
- Quote every expansion: `"$var"`, `"$@"`, `"${arr[@]}"`. Build argument lists in arrays, never in strings.
- `[[ … ]]` in bash. `$(…)`, not backticks. `printf '%s\n' "$x"`, not `echo`, for arbitrary data.
- Errors to stderr through one helper (`die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }`), with a message that says what to do.
- Temp files: `tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT`.
- Pass `--` before arguments that come from users (`rm -- "$file"`). Never `eval` input.
- Scripts are safe to run twice: check before creating, use `mkdir -p`, `ln -sfn`.
- Constants and configurable values at the top, overridable from the environment: `IMAGE="${IMAGE:-localhost/app:latest}"`.

## Portability to macOS

Stock macOS ships bash 3.2, BSD utilities and GNU make 3.81. If the script must run there:

- No `declare -A`, `mapfile`/`readarray`, `${var,,}`/`${var^^}`, `wait -n`, negative array indices, `&>>`. An empty array with `set -u` fails on bash 3.2: use `${arr[@]+"${arr[@]}"}`.
- `sed -i` differs (BSD needs a suffix argument): use `sed -i.bak … && rm file.bak`, or write to a temp file and `mv`.
- No `date -d`, `grep -P`, `xargs -r`, GNU `stat -c`, `readlink -f` before macOS 12.3. Test for the GNU variant or avoid it.
- Make 3.81: no `.ONESHELL`, no `$(file …)`, no `undefine`.
- Test it: `env PATH=/usr/bin:/bin:/usr/sbin:/sbin bash script.sh` on a Mac uses only the stock tools.

## Makefiles

- `.PHONY` for every target that is not a file. A `help` target that lists the others.
- `SHELL := bash` and `.SHELLFLAGS := -eu -o pipefail -c` so recipes fail like scripts do.
- Recipes call scripts for anything longer than a few lines.
- Order-dependent targets must not rely on `-j` being off by accident: express the order as prerequisites, or say in a comment that parallel make is unsupported.

## Tests

- bats-core: one `.bats` file per script, `load helpers` for shared setup, `run` then assert `$status` and `$output`.
- Stub external commands (podman, kubectl, curl, git remotes) with fake executables first on `PATH` that record their arguments, and assert on what the script asked them to do. Real side effects belong in integration tests that clean up after themselves.
- Cover the failure paths: missing arguments, a failing command, an unexpected environment.

## Checks

- `bash -n <file>` (syntax)
- `shellcheck <file>` clean. Disable a rule only inline with a reason: `# shellcheck disable=SC2086 # word splitting wanted: list of flags`.
- `bats <tests>` for the scripts you changed.
- On a Mac target, the stock-tools run above.

## Common mistakes

- `local var=$(cmd)` hiding a failure under `set -e`.
- Unquoted variables that split on spaces in paths.
- `sed -i` that works on Linux and breaks on macOS.
- Associative arrays in a script that must run on a stock Mac.
