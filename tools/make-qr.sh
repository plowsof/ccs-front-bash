#!/usr/bin/env bash
# make-qr.sh LIST: the QR code of every address of a subaddress list (make-subaddresses.sh's
# "index address" lines): LIST.qr/<address>.png, as `qrencode -s 10 "monero:<address>"` writes it,
# and LIST.qr.sha256, each file's sha256 in the list's order (sha256sum's format, run in LIST.qr/).
# sign-subaddresses.sh pins LIST.qr.sha256 in LIST.pin, verify-subaddresses.sh remakes every code,
# ccs-front-bash puts the ones it shows on the site, and the web server's gate takes a QR code
# only as one of these files, byte for byte: it never makes or reads one. 15,000 take about 30 s
# (11.5 MB). qrencode 4.1.1 writes the same bytes on Ubuntu as in the pinned image (StageX's).
set -euo pipefail
export LC_ALL=C
list=${1:?LIST}
[[ -f $list ]] || { echo "no $list" >&2; exit 1; }
command -v qrencode > /dev/null || { echo "needs qrencode" >&2; exit 1; }
awk '$0 !~ /^[0-9]+ [1-9A-HJ-NP-Za-km-z]+$/ || length($2) != 95 { print "line " NR ": not an index and an address" > "/dev/stderr"; bad = 1; exit } END { exit bad }' "$list"

dir=$list.qr
rm -rf "$dir.tmp" "$list.qr.sha256.tmp"
mkdir "$dir.tmp"
trap 'rm -rf "$dir.tmp" "$list.qr.sha256.tmp"' EXIT
n=0
while read -r _ a; do
    qrencode -s 10 -o "$dir.tmp/$a.png" "monero:$a"
    n=$((n + 1))
    ((n % 5000)) || echo "$n" >&2
done < "$list"
abs=$(readlink -f "$list")
(cd "$dir.tmp" && cut -d" " -f2 "$abs" | sed 's/$/.png/' | xargs sha256sum) > "$list.qr.sha256.tmp"
rm -rf "$dir"
mv "$dir.tmp" "$dir"
mv "$list.qr.sha256.tmp" "$list.qr.sha256"
echo "wrote $n QR codes to $dir/ and their sums to $list.qr.sha256 (sha256 $(sha256sum < "$list.qr.sha256" | cut -d' ' -f1))" >&2
