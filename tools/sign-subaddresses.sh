#!/usr/bin/env bash
# sign-subaddresses.sh LIST: sign LIST (from make-subaddresses.sh) with a PGP key made for it
# and thrown away: LIST.asc (a detached signature), LIST.key.asc (the public key) and LIST.pin
# (LIST's sha256 and the key's fingerprint), the four files ccs-front-bash and the web server's
# gate read. The secret key never leaves a
# temporary folder that is removed at the end, so nothing else can ever be signed with it.
set -euo pipefail
list=${1:?LIST}
export GNUPGHOME
GNUPGHOME=$(mktemp -d); chmod 700 "$GNUPGHOME"
trap 'gpgconf --kill all 2> /dev/null || true; rm -rf "$GNUPGHOME"' EXIT
uid="CCS donation subaddresses ($(date -u +%F), throwaway key)"
# gpg chats about its trust database while making a key: shown only if making it fails
gpg -q --batch --passphrase '' --quick-gen-key "$uid" ed25519 sign never 2> "$GNUPGHOME/log" \
    || { cat "$GNUPGHOME/log" >&2; exit 1; }
fpr=$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')
gpg -q --batch --armor --detach-sign --output "$list.asc" "$list"
gpg -q --batch --armor --export "$fpr" > "$list.key.asc"
gpg -q --batch --verify "$list.asc" "$list" 2> /dev/null || { echo "the signature does not verify" >&2; exit 1; }
sum=$(sha256sum < "$list" | cut -d' ' -f1)
printf 'sha256 %s\nkey %s\n' "$sum" "$fpr" > "$list.pin"
echo "key:    $fpr"
echo "sha256: $sum"
echo "wrote $list.asc, $list.key.asc and $list.pin; the secret key is gone with $GNUPGHOME"
