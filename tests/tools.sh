#!/usr/bin/env bash
# The signing tool (tools/sign-subaddresses.sh): its signature verifies with the key it exports,
# a changed list doesn't, it prints the list's sha256, and no secret key is left anywhere.
# (tools/make-subaddresses.sh needs monero-wallet-rpc: checked by hand, see docs/setup.md.)
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; status=1; }

for i in 0 1 2; do printf '%d 8%094d\n' "$i" "$i"; done > "$tmp/list.txt"
before=$(ls -A "${TMPDIR:-/tmp}" | wc -l)
out=$("$here/../tools/sign-subaddresses.sh" "$tmp/list.txt" 2> "$tmp/log") || { cat "$tmp/log"; fail "signing"; exit 1; }
fpr=$(sed -n 's/^key: *//p' <<<"$out") sum=$(sed -n 's/^sha256: *//p' <<<"$out")

export GNUPGHOME=$tmp/verify
mkdir -m 700 "$GNUPGHOME"
gpg -q --batch --import "$tmp/list.txt.key.asc" 2> /dev/null
if gpg --batch --verify "$tmp/list.txt.asc" "$tmp/list.txt" 2>&1 | grep -q "using EDDSA key $fpr"; then
    ok "the list's signature verifies with the exported key ($fpr)"
else
    fail "signature"
fi
if [[ $sum == "$(sha256sum < "$tmp/list.txt" | cut -d' ' -f1)" && $(cat "$tmp/list.txt.pin") == "sha256 $sum"$'\n'"key $fpr" ]]; then
    ok "it prints the list's sha256, and writes it and the fingerprint to LIST.pin"
else
    fail "sha256 '$sum' or LIST.pin"
fi
sed -i '2s/^1 8/1 9/' "$tmp/list.txt"
if ! gpg --batch --verify "$tmp/list.txt.asc" "$tmp/list.txt" 2> /dev/null; then ok "a changed list fails"; else fail "a changed list verified"; fi
if [[ -z $(gpg --batch --list-secret-keys 2> /dev/null) && $(ls -A "${TMPDIR:-/tmp}" | wc -l) -le $before ]]; then
    ok "no secret key kept: not exported, its folder gone"
else
    fail "a secret key or its folder was left"
fi
exit "$status"
