#!/usr/bin/env bash
# sign-subaddresses.sh LIST: sign LIST (from make-subaddresses.sh): LIST.asc (a detached
# signature), LIST.key.asc (the public key) and LIST.pin (LIST's sha256 and the key's
# fingerprint), the four files ccs-front-bash and the web server's gate read.
#   SIGNING_KEY=<fingerprint>   sign with that key of your own, from your keyring (GNUPGHOME): a
#                               Core Team member's, whose key the Monero repository publishes
#                               (utils/gpg_keys/), so anyone can check who signed. Nothing is
#                               made or destroyed. The mainnet list is signed so.
#   (unset)                     a PGP key made only for this and thrown away: the secret key
#                               never leaves a temporary folder removed at the end. It binds the
#                               file, not a person (the testnet's).
set -euo pipefail
list=${1:?LIST}
if [[ -n ${SIGNING_KEY:-} ]]; then
    fpr=$(tr -d ' ' <<<"$SIGNING_KEY" | tr 'a-f' 'A-F')
    [[ $fpr =~ ^[0-9A-F]{40}$ ]] || { echo "SIGNING_KEY: a key's 40 hex digits fingerprint" >&2; exit 1; }
    gpg --batch --list-secret-keys "$fpr" > /dev/null 2>&1 || { echo "no secret key $fpr in this keyring" >&2; exit 1; }
    gpg -q --batch --yes --armor --local-user "$fpr" --detach-sign --output "$list.asc" "$list"
    gpg -q --batch --armor --export-options export-minimal --export "$fpr" > "$list.key.asc"
    gone=''
else
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
    gone=1
fi
gpg -q --batch --verify "$list.asc" "$list" 2> /dev/null || { echo "the signature does not verify" >&2; exit 1; }
sum=$(sha256sum < "$list" | cut -d' ' -f1)
printf 'sha256 %s\nkey %s\n' "$sum" "$fpr" > "$list.pin"
echo "key:    $fpr"
echo "sha256: $sum"
if [[ $gone ]]; then echo "wrote $list.asc, $list.key.asc and $list.pin; the secret key is gone with $GNUPGHOME"
else echo "wrote $list.asc, $list.key.asc and $list.pin, signed with your key $fpr"; fi
