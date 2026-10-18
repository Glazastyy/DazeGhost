#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/dazeghost-separate-XXXXXX")
payload="$work/protected.lua"
vm="$work/protected-vm"

"$root/dazeghost" --obfuscate --mode text --input "$root/tests/fixtures/script.lua" --output "$payload" --separate-vm "$vm"
test -x "$vm"
"$vm"

if "$vm" "$payload"; then
    exit 1
fi

printf '\n' >> "$payload"
if "$vm"; then
    exit 1
fi

printf 'passed: separate VM binding and tamper rejection\n'
