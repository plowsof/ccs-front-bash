#!/usr/bin/env bash
# ccs-front-bash.sh ORIGINAL DATA PROPOSALS SITE: fill the original (ccs-front-hugo's built site)
# with ccs-bash's JSON in DATA and the proposals' Markdown in PROPOSALS, into a new SITE. Every
# piece of HTML comes from the original's pages and parts; this only fills them. The original
# is never changed; SITE is replaced only once the new one is complete. Needs no network.
set -euo pipefail
export LC_ALL=C

LIB=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib
# shellcheck source=lib/fill.sh
source "$LIB/fill.sh"

# proposal_pages ORIGINAL DATA PROPOSALS OUT: a page per proposal in fr, wip and cp (ideas link
# to GitLab), at the local-url ccs-bash gave it. One awk run renders all the Markdown, one jq run
# makes all the pages: awk and jq once per page would take longer than the work.
proposal_pages() {
    local original=$1 data=$2 proposals=$3 out=$4 p=$1/parts file files=()
    mkdir -p "$out/proposals"
    while IFS= read -r file; do
        [[ -f $proposals/$file.md ]] || die "no proposal file $file.md"
        files+=("$proposals/$file.md")
    done < <(jq -r -L "$LIB" --slurpfile c "$data/completed-proposals.json" --slurpfile pr "$data/proposals.json" -n \
        'include "common"; paged($pr; $c) | .[1] | page_file')
    printf '%s\0' "${files[@]}" | xargs -0 -r awk -f "$LIB/markdown.awk" > "$work/md.jsonl"
    jq -nr -L "$LIB" --slurpfile proposals "$data/proposals.json" --slurpfile completed "$data/completed-proposals.json" \
        --slurpfile md "$work/md.jsonl" \
        --rawfile fr "$p/proposal-fr.html" --rawfile wip "$p/proposal-wip.html" --rawfile cp "$p/proposal-cp.html" \
        --rawfile donate "$p/donate.html" --rawfile funded "$p/funded.html" \
        --rawfile mdone "$p/milestone-done.html" --rawfile mtodo "$p/milestone-todo.html" \
        --rawfile payout "$p/payout.html" --rawfile nom "$p/no-milestones.html" --rawfile nop "$p/no-payouts.html" \
        --rawfile segdone "$p/segment-done.html" --rawfile segtodo "$p/segment-todo.html" \
        -f "$LIB/pages.jq" > "$work/pages"
    # split: a line "\001<name>" starts the next page (pages.jq removes \001 from page text)
    awk -v dir="$out/proposals" '/^\001/ { if (f) close(f); f = dir "/" substr($0, 2) ".html"; next } { print > f }' "$work/pages"
}

main() {
    local original data proposals site stage page
    # absolute paths, then work from /: started by runuser from root's home, the current
    # directory may not be readable (find needs it)
    original=$(readlink -f "${1:?ORIGINAL}") data=$(readlink -f "${2:?DATA}")
    proposals=$(readlink -f "${3:?PROPOSALS}") site=$(readlink -f "${4:?SITE}")
    cd /
    [[ -f $original/index.html && -d $original/parts ]] || die "$original is not a built ccs-front-hugo site"
    [[ -f $data/proposals.json && -f $data/completed-proposals.json ]] || die "no ccs-bash JSON in $data"
    [[ -d $proposals ]] || die "no proposals checkout at $proposals"
    work=$(mktemp -d)   # global: the EXIT trap still needs them after main
    new=$site.new
    trap 'rm -rf "$work" "$new"' EXIT

    # each list once: the same list goes on every page that shows it
    mkdir "$work/regions"
    for stage in idea fr wip cp; do
        jq -nr -L "$LIB" --arg stage "$stage" \
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
    proposal_pages "$original" "$data" "$proposals" "$new"
    # the /projects API goes with the site, so one push carries everything public
    if [[ -f $data/projects.json ]]; then cp "$data/projects.json" "$new/projects.json"; fi

    rm -rf "$site.old"
    if [[ -e $site ]]; then mv "$site" "$site.old"; fi
    mv "$new" "$site"
    rm -rf "$site.old"
    log "filled $site"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
