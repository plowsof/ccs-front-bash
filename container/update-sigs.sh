#!/usr/bin/env bash
# update-sigs.sh
# Saves in sigs/ the StageX signatures of every pinned image, for each linux manifest.
# Builds then read them here instead of from sigs.stagex.tools.
# update-images.sh runs it, then verify-images.sh checks them.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
lookaside=https://sigs.stagex.tools
new=$(mktemp -d)
trap 'rm -rf "$new"' EXIT
while read -r name ref; do
    repo=${ref%@*}
    for manifest in $(docker buildx imagetools inspect --raw "$ref" | jq -r '.manifests[] | select(.platform.os == "linux") | .digest'); do
        d=$new/$repo/${manifest#sha256:}
        mkdir -p "$d"
        for n in $(seq 1 20); do
            code=$(curl -sS --max-time 60 -o "$d/signature-$n" -w '%{http_code}' "$lookaside/$repo@${manifest/:/=}/signature-$n")
            [[ $code == 404 ]] && { rm -f "$d/signature-$n"; break; }
            [[ $code == 200 ]] || { echo "error: $name: signature-$n: HTTP $code from $lookaside" >&2; exit 1; }
        done
        echo "$name: $(find "$d" -type f | wc -l) signature(s) on $manifest" >&2
    done
done < <(grep -v '^#' "$here/images")
rm -rf "$here/sigs" && mv "$new" "$here/sigs" && chmod -R u=rwX,go=rX "$here/sigs"
trap - EXIT
# Record each signature that counts now, so it still counts after its key expires.
"$here/verify-images.sh" --record
