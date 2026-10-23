#!/usr/bin/env bash
# ccs-front-bash.sh ORIGINAL DATA SITE: fill the original (ccs-front-hugo's built site) with
# ccs-bash's JSON in DATA, into a new SITE. The original is never changed; SITE is replaced
# only once the new one is complete. Needs no network.
# So far: the stage lists. Proposal pages (Markdown, donation boxes) are not made yet, so
# proposals/ is left out.
set -euo pipefail
export LC_ALL=C

LIB=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib
# shellcheck source=lib/fill.sh
source "$LIB/fill.sh"

main() {
    local original=${1:?ORIGINAL} data=${2:?DATA} site=${3:?SITE} stage page
    [[ -f $original/index.html && -d $original/parts ]] || die "$original is not a built ccs-front-hugo site"
    [[ -f $data/proposals.json && -f $data/completed-proposals.json ]] || die "no ccs-bash JSON in $data"
    work=$(mktemp -d)   # global: the EXIT trap still needs them after main
    new=$site.new
    trap 'rm -rf "$work" "$new"' EXIT

    # each region once: the same list goes on every page that shows it
    mkdir "$work/regions"
    for stage in idea fr wip cp; do
        jq -nr --arg stage "$stage" \
            --slurpfile proposals "$data/proposals.json" --slurpfile completed "$data/completed-proposals.json" \
            --rawfile card "$original/parts/card-$stage.html" --rawfile empty "$original/parts/empty.html" \
            --rawfile segdone "$original/parts/segment-done.html" --rawfile segtodo "$original/parts/segment-todo.html" \
            -f "$LIB/regions.jq" > "$work/regions/list_$stage.html"
    done

    rm -rf "$new"
    mkdir "$new"
    (cd "$original" && tar -c --exclude=./parts --exclude=./proposals .) | tar -x -C "$new"
    while IFS= read -r -d '' page; do
        grep -q '<!-- ccs:' "$page" || continue
        fill_page "$page" "$work/regions" > "$page.tmp"
        mv "$page.tmp" "$page"
    done < <(find "$new" -name '*.html' -print0)

    rm -rf "$site.old"
    if [[ -e $site ]]; then mv "$site" "$site.old"; fi
    mv "$new" "$site"
    rm -rf "$site.old"
    log "filled $site"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
