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
out=$("$here/../tools/sign-subaddresses.sh" "$tmp/list.txt" 2> "$tmp/log") || { cat "$tmp/log"; fail "signing"; exit 1; }
fpr=$(sed -n 's/^key: *//p' <<<"$out") sum=$(sed -n 's/^sha256: *//p' <<<"$out")
keydir=$(sed -n 's/.*the secret key is gone with //p' <<<"$out")   # its temporary GNUPGHOME

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
if [[ -z $(gpg --batch --list-secret-keys 2> /dev/null) && $keydir && ! -e $keydir ]]; then
    ok "no secret key kept: not exported, its folder gone"
else
    fail "a secret key or its folder was left"
fi

# Signed with a Core Team member's own key (SIGNING_KEY), as the mainnet list is, and checked with
# verify-subaddresses.sh: only a key in SIGNERS counts, and the list must be the pin's, the
# signature good, the lines in order, line 0 the wallet's main address.
core=$tmp/core && mkdir -m 700 "$core"
GNUPGHOME=$core gpg -q --batch --passphrase '' --quick-gen-key 'Core Team member <core@test>' ed25519 sign 1d 2> /dev/null
cfpr=$(GNUPGHOME=$core gpg --batch --with-colons --list-keys 2> /dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
mk() { for i in 0 1 2; do printf '%d %s\n' "$i" "$(printf '9%094d' "$i" | tr 0 A)"; done > "$1"; }
mk "$tmp/main.txt"
out=$(GNUPGHOME=$core SIGNING_KEY=$cfpr "$here/../tools/sign-subaddresses.sh" "$tmp/main.txt" 2>&1) || { echo "$out"; fail "signing with SIGNING_KEY"; }
if [[ $(sed -n 's/^key *//p' "$tmp/main.txt.pin") == "$cfpr" && -n $(GNUPGHOME=$core gpg --batch --list-secret-keys "$cfpr" 2> /dev/null) ]]; then
    ok "SIGNING_KEY: signed with that key, its fingerprint in LIST.pin, the key left as it was"
else
    fail "SIGNING_KEY's pin or key"
fi
wallet=$(awk 'NR == 1 { print $2 }' "$tmp/main.txt")
echo "$cfpr  # the Core Team member" > "$tmp/signers"; echo "${cfpr//?/0}  # someone else" > "$tmp/others"
v() { (unset GNUPGHOME; "$here/../tools/verify-subaddresses.sh" "$@") > "$tmp/v.out" 2>&1; }
if v "$tmp/main.txt" "$tmp/signers" "$wallet" && grep -q "signed by $cfpr (Core Team member <core@test>)" "$tmp/v.out"; then
    ok "verify: the list, signed by a key in SIGNERS, its pin, line 0 the wallet's: OK, and who signed"
else
    cat "$tmp/v.out"; fail "verify a good list"
fi
nope() { if ! v "${@:2}" && grep -q "NOT OK: .*$1" "$tmp/v.out"; then ok "verify refuses: $1"; else cat "$tmp/v.out"; fail "verify accepted: $1"; fi; }
nope "is not one of" "$tmp/main.txt" "$tmp/others" "$wallet"
nope "line 0 is not" "$tmp/main.txt" "$tmp/signers" "$(addr=$(awk 'NR == 2 { print $2 }' "$tmp/main.txt"); echo "$addr")"
cp "$tmp/main.txt" "$tmp/keep.txt"; sed -i '2s/ 9/ A/' "$tmp/main.txt"
nope "is not the list" "$tmp/main.txt" "$tmp/signers" "$wallet"
cp "$tmp/keep.txt" "$tmp/main.txt"; cp "$tmp/main.txt.key.asc" "$tmp/keep.key.asc"; cp "$tmp/list.txt.key.asc" "$tmp/main.txt.key.asc"
nope "not a good signature" "$tmp/main.txt" "$tmp/signers" "$wallet"
cp "$tmp/keep.key.asc" "$tmp/main.txt.key.asc"
{ sed -n 1p "$tmp/main.txt"; sed -n 3p "$tmp/main.txt"; sed -n 2p "$tmp/main.txt"; } > "$tmp/order.txt"
(cd "$tmp" && GNUPGHOME=$core SIGNING_KEY=$cfpr "$here/../tools/sign-subaddresses.sh" order.txt > /dev/null 2>&1)
nope "not 'index address' lines" "$tmp/order.txt" "$tmp/signers"
exit "$status"
