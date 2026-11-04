#!/bin/bash
# One command for the first run on a Mac: build, test, probe, benchmark.
#
#   bash Tools/mac-first-run.sh
#
# Stops at the first failing step and says which one, so the tail of the output
# is enough to report.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
cd "$root/Swift" || exit 1

step() {
    printf '\n\033[1m== %s\033[0m\n' "$1"
}

stopped() {
    printf '\n\033[31mSTOPPED AT: %s\033[0m\n' "$1"
    printf 'Paste the last ~20 lines above, plus the output of:\n'
    printf '    swift --version && xcodebuild -version\n'
    exit 1
}

step "toolchain"
swift --version || stopped "toolchain"
xcodebuild -version 2>/dev/null || true

step "build"
swift build || stopped "build"

step "tests"
swift test || stopped "tests"

step "probe (five-stage parity)"
swift run spektra-probe || stopped "probe"

step "benchmark (no photo needed)"
swift run spektra-cli --bench 1024 || true

printf '\n\033[32mAll good.\033[0m Next: render a real photo with\n'
printf '    swift run spektra-cli /path/to/photo.heic out.png\n'
