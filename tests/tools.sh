#!/usr/bin/env bash
# The signing tool (tools/sign-subaddresses.sh): its signature verifies with the key it exports,
# a changed list doesn't, it prints the list's sha256, and no secret key is left anywhere. The
# QR codes (tools/make-qr.sh): one per address, pinned, remade by verify-subaddresses.sh.
# (tools/make-subaddresses.sh needs monero-wallet-rpc: checked by hand, see docs/setup.md.)
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; status=1; }

for i in 0 1 2; do printf '%d 8%s\n' "$i" "$(printf '%094d' "$i" | tr 0 B)"; done > "$tmp/list.txt"
qr() { "$here/../tools/make-qr.sh" "$1" 2> /dev/null; }
if ! "$here/../tools/sign-subaddresses.sh" "$tmp/list.txt" > "$tmp/log" 2>&1 && grep -q "make the QR codes first" "$tmp/log"; then
    ok "sign refuses a list without its QR codes' sums"
else
    fail "signed a list without LIST.qr.sha256"
fi
qr "$tmp/list.txt"
if [[ $(ls "$tmp/list.txt.qr") == "$(cut -d' ' -f2 "$tmp/list.txt" | sed 's/$/.png/' | sort)" && $(wc -l < "$tmp/list.txt.qr.sha256") == 3 ]] \
    && cmp -s "$tmp/list.txt.qr/$(awk 'NR == 2 { print $2 }' "$tmp/list.txt").png" <(qrencode -s 10 -o - "monero:$(awk 'NR == 2 { print $2 }' "$tmp/list.txt")"); then
    ok "make-qr: LIST.qr/<address>.png, qrencode -s 10 of monero:<address>, for each; their sums"
else
    fail "make-qr's files"
fi
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
if [[ $sum == "$(sha256sum < "$tmp/list.txt" | cut -d' ' -f1)" && $(cat "$tmp/list.txt.pin") == "sha256 $sum"$'\n'"key $fpr"$'\n'"qr $(sha256sum < "$tmp/list.txt.qr.sha256" | cut -d' ' -f1)" ]]; then
    ok "it prints the list's sha256, and writes it, the fingerprint and the QR codes' sums' sha256 to LIST.pin"
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
qr "$tmp/main.txt"
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
qr "$tmp/order.txt" || true
(cd "$tmp" && GNUPGHOME=$core SIGNING_KEY=$cfpr "$here/../tools/sign-subaddresses.sh" order.txt > /dev/null 2>&1)
nope "not 'index address' lines" "$tmp/order.txt" "$tmp/signers"
# Review 5: one address twice (line 2 = line 1, signed): never right, every check takes "in the
# list" for "one of the wallet's"
{ sed -n 1,2p "$tmp/main.txt"; printf '2 %s\n' "$(awk 'NR == 2 { print $2 }' "$tmp/main.txt")"; } > "$tmp/dup.txt"
qr "$tmp/dup.txt"
(cd "$tmp" && GNUPGHOME=$core SIGNING_KEY=$cfpr "$here/../tools/sign-subaddresses.sh" dup.txt > /dev/null 2>&1)
nope "an address twice" "$tmp/dup.txt" "$tmp/signers" "$wallet"
# the QR codes: the pin's sums, one for each address in order, each file its sum, each what
# qrencode makes of its address (a code of another address, its sums and pin made to match)
a1=$(awk 'NR == 2 { print $2 }' "$tmp/main.txt") a2=$(awk 'NR == 3 { print $2 }' "$tmp/main.txt")
cp -r "$tmp/main.txt.qr" "$tmp/keep.qr"; cp "$tmp/main.txt.qr.sha256" "$tmp/keep.qr.sha256"; cp "$tmp/main.txt.pin" "$tmp/keep.pin"
sed -i '/^qr /d' "$tmp/main.txt.pin"
nope "no 'qr <hex>' line" "$tmp/main.txt" "$tmp/signers" "$wallet"
cp "$tmp/keep.pin" "$tmp/main.txt.pin"
cp "$tmp/main.txt.qr/$a2.png" "$tmp/main.txt.qr/$a1.png"
nope "a file that is not its sum" "$tmp/main.txt" "$tmp/signers" "$wallet"
(cd "$tmp/main.txt.qr" && awk '{ print $2 ".png" }' "$tmp/main.txt" | xargs sha256sum) > "$tmp/main.txt.qr.sha256"
sed -i "s/^qr .*/qr $(sha256sum < "$tmp/main.txt.qr.sha256" | cut -d' ' -f1)/" "$tmp/main.txt.pin"
nope "not what qrencode" "$tmp/main.txt" "$tmp/signers" "$wallet"
{ sed -n 1p "$tmp/keep.qr.sha256"; sed -n 3p "$tmp/keep.qr.sha256"; sed -n 2p "$tmp/keep.qr.sha256"; } > "$tmp/main.txt.qr.sha256"
rm -rf "$tmp/main.txt.qr"; cp -r "$tmp/keep.qr" "$tmp/main.txt.qr"
sed -i "s/^qr .*/qr $(sha256sum < "$tmp/main.txt.qr.sha256" | cut -d' ' -f1)/" "$tmp/main.txt.pin"
nope "one for each of" "$tmp/main.txt" "$tmp/signers" "$wallet"
cp "$tmp/keep.pin" "$tmp/main.txt.pin"
nope "is not the one" "$tmp/main.txt" "$tmp/signers" "$wallet"
cp "$tmp/keep.qr.sha256" "$tmp/main.txt.qr.sha256"
if v "$tmp/main.txt" "$tmp/signers" "$wallet" && grep -q "QR codes .*remade here" "$tmp/v.out"; then
    ok "verify: the QR codes put back, OK again"
else
    cat "$tmp/v.out"; fail "verify after the QR codes put back"
fi
# the signer's key revoked (its owner's revocation certificate, as gpg made it): refused
sed 's/^:-----BEGIN/-----BEGIN/' "$core/openpgp-revocs.d/$cfpr.rev" | GNUPGHOME=$core gpg -q --batch --import 2> /dev/null
cp "$tmp/main.txt.key.asc" "$tmp/keep.key.asc"
GNUPGHOME=$core gpg --batch --armor --export "$cfpr" > "$tmp/main.txt.key.asc" 2> /dev/null
nope "revoked key" "$tmp/main.txt" "$tmp/signers" "$wallet"
# Review 5: the list shipped with its key's export from before the revocation (whoever brings a
# list brings LIST.key.asc too): with SIGNER_KEYS, keys of your own, the revocation is known
GNUPGHOME=$core gpg --batch --armor --export "$cfpr" > "$tmp/own-keys.asc" 2> /dev/null
cp "$tmp/keep.key.asc" "$tmp/main.txt.key.asc"
if ! SIGNER_KEYS=$tmp/own-keys.asc v "$tmp/main.txt" "$tmp/signers" "$wallet" && grep -q "NOT OK: .*revoked key" "$tmp/v.out"; then
    ok "verify refuses: a revoked key, the list shipped with its old export, checked with SIGNER_KEYS (your own copy of the keys)"
else cat "$tmp/v.out"; fail "verify with SIGNER_KEYS: a revoked key's old export accepted"; fi
if ! SIGNER_KEYS=$tmp/none.asc v "$tmp/main.txt" "$tmp/signers" "$wallet" && grep -q "no SIGNER_KEYS file" "$tmp/v.out"; then ok "verify refuses: a SIGNER_KEYS file that is not there"; else fail "verify: a missing SIGNER_KEYS file"; fi
exit "$status"
