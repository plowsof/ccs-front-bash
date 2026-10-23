#!/usr/bin/env bash
# sign-subaddresses.sh LIST: sign LIST (from make-subaddresses.sh) with a PGP key made for it
# and thrown away: LIST.asc (detached signature), LIST.key.asc (the public key), and the key's
# fingerprint and LIST's sha256 for ccs-front-hugo's hugo.toml. The secret key never leaves a
# temporary folder that is removed at the end, so nothing else can ever be signed with it.
set -euo pipefail
list=${1:?LIST}
export GNUPGHOME
GNUPGHOME=$(mktemp -d); chmod 700 "$GNUPGHOME"
trap 'gpgconf --kill all 2> /dev/null || true; rm -rf "$GNUPGHOME"' EXIT
uid="CCS donation subaddresses ($(date -u +%F), throwaway key)"
gpg -q --batch --passphrase '' --quick-gen-key "$uid" ed25519 sign never
fpr=$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')
gpg -q --batch --armor --detach-sign --output "$list.asc" "$list"
gpg -q --batch --armor --export "$fpr" > "$list.key.asc"
gpg -q --batch --verify "$list.asc" "$list" 2> /dev/null || { echo "the signature does not verify" >&2; exit 1; }
echo "key:    $fpr"
echo "sha256: $(sha256sum "$list" | cut -d' ' -f1)"
echo "wrote $list.asc and $list.key.asc; the secret key is gone with $GNUPGHOME"
