#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dazegghost-native.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

secret='native-loader-test-secret'
output="$tmp/protected"
stdout="$tmp/stdout"
stderr="$tmp/stderr"

help=$("$root/dazeghost" --help)
test "$(printf '%s\n' "$help" | grep -c '^usage: dazeghost')" -eq 1

"$root/dazeghost" --obfuscate --mode text --secret="$secret" --native-loader --input "$root/script.lua" --output "$output" >"$stdout" 2>"$stderr"

printf '%s\n' "$secret" | "$output" >"$stdout" 2>"$stderr"
grep -Fq 'Olá, mundo!' "$stdout"

if printf '%s\n' 'wrong-secret' | "$output" >"$stdout" 2>"$stderr"; then
    exit 1
fi

grep -Fq 'invalid password' "$stderr"
