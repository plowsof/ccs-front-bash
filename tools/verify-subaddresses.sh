#!/usr/bin/env bash
# verify-subaddresses.sh LIST SIGNERS [WALLET_ADDRESS]
# Checks a signed subaddress list before it is installed.
# Exits 0 with a summary if all checks pass. Otherwise prints the first failure and exits 1.
#   - LIST matches the sha256 in LIST.pin.
#   - LIST.pin's key is in SIGNERS, a root-owned file of fingerprints, one per line.
#     For mainnet, the Core Team members who may sign, from utils/gpg_keys/.
#   - LIST.asc is a good signature of LIST by that key.
#     SIGNER_KEYS=<file> uses keys you got yourself. LIST.key.asc may be an old export
#     from before a revocation, so only your own keys show a revocation for sure.
#   - LIST is "index address" lines, in order from 0, each address 95 characters, none twice.
#   - With WALLET_ADDRESS, line 0 is that address.
#   - The QR codes match LIST.pin's qr line, and each is what qrencode makes of its address.
#     They are all remade here, which needs qrencode.
# ccs-front-bash and the gate then check the list against its pin on every run.
# This is how you know the pin is the right one.
set -euo pipefail
export LC_ALL=C
list=${1:?LIST} signers=${2:?SIGNERS} wallet=${3:-}
bad() { echo "NOT OK: $*" >&2; exit 1; }
for f in "$list" "$list.pin" "$list.asc" "$list.key.asc" "$list.qr.sha256" "$signers"; do [[ -f $f ]] || bad "no $f"; done
[[ -d $list.qr ]] || bad "no $list.qr/ (its QR codes: make-qr.sh $list)"
command -v qrencode > /dev/null || bad "needs qrencode (to remake the QR codes)"
sum=$(sed -n 's/^sha256 *//p' "$list.pin") fpr=$(sed -n 's/^key *//p' "$list.pin") qr=$(sed -n 's/^qr *//p' "$list.pin")
[[ $sum =~ ^[0-9a-f]{64}$ && $fpr =~ ^[0-9A-F]{40}$ ]] || bad "$list.pin: want a 'sha256 <hex>' and a 'key <fingerprint>' line"
[[ $qr =~ ^[0-9a-f]{64}$ ]] || bad "$list.pin: no 'qr <hex>' line (the sha256 of $list.qr.sha256: make-qr.sh, then sign-subaddresses.sh)"
[[ $(sha256sum < "$list" | cut -d' ' -f1) == "$sum" ]] || bad "$list is not the list $list.pin names (its sha256)"
sed 's/#.*//; s/[[:space:]]//g' "$signers" | tr 'a-f' 'A-F' | grep -qxF "$fpr" \
    || bad "$list.pin's key $fpr is not one of $signers"

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
chmod 700 "$GNUPGHOME"
again=''
trap 'gpgconf --kill all 2> /dev/null || true; rm -rf "$GNUPGHOME" ${again:+"$again"}' EXIT
keys=$list.key.asc
if [[ -n ${SIGNER_KEYS:-} ]]; then [[ -f $SIGNER_KEYS ]] || bad "no SIGNER_KEYS file $SIGNER_KEYS"; keys=$SIGNER_KEYS; fi
gpg -q --batch --import "$keys" 2> /dev/null || bad "$keys is not a public key"
# The signature's primary key, whichever subkey signed.
# Not a revoked key, and not a signature past its own expiry.
# An expired key still counts: the list was signed while it was good.
status=$(gpg --batch --status-fd 1 --verify "$list.asc" "$list" 2> /dev/null) || true
if grep -qE '^\[GNUPG:\] (REVKEYSIG|KEYREVOKED|EXPSIG) ' <<<"$status"; then
    bad "$list.asc is by a revoked key, or has expired ($(grep -oE '(REVKEYSIG|KEYREVOKED|EXPSIG)' <<<"$status" | head -n 1))"
fi
by=$(awk '$2 == "VALIDSIG" { print $NF }' <<<"$status")
[[ $by == "$fpr" ]] || bad "$list.asc is not a good signature of $list by $fpr${by:+ (it is by $by)}"
who=$(gpg --batch --with-colons --list-keys "$fpr" | awk -F: '$1 == "uid" { print $10; exit }')

n=$(wc -l < "$list")
awk '$0 !~ /^[0-9]+ [1-9A-HJ-NP-Za-km-z]+$/ || $1 != NR - 1 || length($2) != 95 { print "line " NR ": " substr($0, 1, 40); bad = 1; exit } END { exit bad }' "$list" \
    || bad "$list: not 'index address' lines, from 0, in order"
# An address listed twice is never right.
twice=$(awk 'seen[$2]++ { print NR - 1; exit }' "$list")
[[ -z $twice ]] || bad "$list: line $twice's address is on an earlier line too (an address twice)"
if [[ -n $wallet ]]; then
    [[ $(awk 'NR == 1 { print $2 }' "$list") == "$wallet" ]] || bad "$list: line 0 is not the wallet's main address $wallet"
fi
# The QR codes: the pinned sums in the list's order, the files, and each remade here.
[[ $(sha256sum < "$list.qr.sha256" | cut -d' ' -f1) == "$qr" ]] || bad "$list.qr.sha256 is not the one $list.pin names (its qr line)"
awk 'NR == FNR { a[NR] = $2 ".png"; n = NR; next }
     $0 !~ /^[0-9a-f]+  [1-9A-HJ-NP-Za-km-z]+\.png$/ || length($1) != 64 || $2 != a[FNR] { bad = 1; exit }
     END { exit bad || FNR != n }' "$list" "$list.qr.sha256" \
    || bad "$list.qr.sha256: not '<sha256>  <address>.png' lines, one for each of $list's addresses in its order"
(cd "$list.qr" && sha256sum --quiet -c -) < "$list.qr.sha256" > /dev/null 2>&1 || bad "$list.qr/: a file that is not its sum in $list.qr.sha256 (or missing)"
again=$(mktemp -d)
cp "$list" "$again/list"
"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/make-qr.sh" "$again/list" 2> /dev/null || bad "could not remake the QR codes (make-qr.sh)"
cmp -s "$again/list.qr.sha256" "$list.qr.sha256" \
    || bad "$list.qr/: not what qrencode ($(qrencode -V 2>&1 | head -n 1)) makes of the addresses: $(diff "$again/list.qr.sha256" "$list.qr.sha256" | grep -c '^>') differ"
rm -rf "$again"
main=''; [[ -z $wallet ]] || main=', line 0 the main address WALLET_ADDRESS'
echo "OK: $list, $n subaddresses (0 to $((n - 1)))$main"
echo "    sha256 $sum, as its .pin names"
echo "    its $n QR codes $list.qr/, remade here; their sums $list.qr.sha256 as its .pin names"
echo "    signed by $fpr ($who), one of $signers${SIGNER_KEYS:+, its key from $SIGNER_KEYS}"
