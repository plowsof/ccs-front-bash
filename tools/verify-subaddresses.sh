#!/usr/bin/env bash
# verify-subaddresses.sh LIST SIGNERS [WALLET_ADDRESS]: check a signed subaddress list before it
# is installed (and on any copy of it): exit 0 and a summary if all hold, else the first that
# doesn't and 1.
#   - LIST is the list LIST.pin names (its sha256);
#   - LIST.pin's key is one of SIGNERS: a file of your own, root-owned, one fingerprint a line
#     (# comments), for the mainnet those of the Core Team members who may sign it, as the
#     Monero repository publishes their keys (utils/gpg_keys/);
#   - LIST.asc is a good signature of LIST by that key (LIST.key.asc, in a keyring of its own);
#   - LIST is "index address" lines, 0, 1, 2... in order, each a 95-character address;
#   - with WALLET_ADDRESS, line 0 is it (the wallet's main address: ccs-bash's WALLET_ADDRESS).
# ccs-front-bash and the web server's gate then check the list against its .pin every run and
# push: the pin is what they trust, this is how you know the pin is the right one.
set -euo pipefail
export LC_ALL=C
list=${1:?LIST} signers=${2:?SIGNERS} wallet=${3:-}
bad() { echo "NOT OK: $*" >&2; exit 1; }
for f in "$list" "$list.pin" "$list.asc" "$list.key.asc" "$signers"; do [[ -f $f ]] || bad "no $f"; done
sum=$(sed -n 's/^sha256 *//p' "$list.pin") fpr=$(sed -n 's/^key *//p' "$list.pin")
[[ $sum =~ ^[0-9a-f]{64}$ && $fpr =~ ^[0-9A-F]{40}$ ]] || bad "$list.pin: want a 'sha256 <hex>' and a 'key <fingerprint>' line"
[[ $(sha256sum < "$list" | cut -d' ' -f1) == "$sum" ]] || bad "$list is not the list $list.pin names (its sha256)"
sed 's/#.*//; s/[[:space:]]//g' "$signers" | tr 'a-f' 'A-F' | grep -qxF "$fpr" \
    || bad "$list.pin's key $fpr is not one of $signers"

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
chmod 700 "$GNUPGHOME"
trap 'gpgconf --kill all 2> /dev/null || true; rm -rf "$GNUPGHOME"' EXIT
gpg -q --batch --import "$list.key.asc" 2> /dev/null || bad "$list.key.asc is not a public key"
# the signature's primary key (VALIDSIG's last field), whichever of its subkeys signed; not one
# its owner revoked, nor a signature past its own expiry (a key past its expiry still counts: the
# list was signed while it was good, and a Core Team member's key is extended now and then)
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
if [[ -n $wallet ]]; then
    [[ $(awk 'NR == 1 { print $2 }' "$list") == "$wallet" ]] || bad "$list: line 0 is not the wallet's main address $wallet"
fi
main=''; [[ -z $wallet ]] || main=', line 0 the main address WALLET_ADDRESS'
echo "OK: $list, $n subaddresses (0 to $((n - 1)))$main"
echo "    sha256 $sum, as its .pin names"
echo "    signed by $fpr ($who), one of $signers"
