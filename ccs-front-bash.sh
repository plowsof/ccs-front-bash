#!/usr/bin/env bash
# ccs-front-bash.sh ORIGINAL DATA PROPOSALS SITE [SUBADDRESSES]: fill the original (ccs-front-hugo's
# built site) with ccs-bash's JSON in DATA and the proposals' Markdown in PROPOSALS, into a new
# SITE. If the original pins a list of the wallet's subaddresses (see check_addresses), every
# donation address must be in SUBADDRESSES. Every
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
        --rawfile labellink "$p/label-link.html" -f "$LIB/pages.jq" > "$work/pages"
    # split: a line "\001<name>" starts the next page (pages.jq removes \001 from page text)
    awk -v dir="$out/proposals" '/^\001/ { if (f) close(f); f = dir "/" substr($0, 2) ".html"; next } { print > f }' "$work/pages"
}

# tag_regions ORIGINAL DATA: the tag filters (into $work/regions) and each tag page's regions
# (into $work/tags/<slug>/), from one jq run; the tag slugs on stdout.
tag_regions() {
    local p=$1/parts data=$2 path
    jq -nr -L "$LIB" --slurpfile proposals "$data/proposals.json" --slurpfile completed "$data/completed-proposals.json" \
        --rawfile cardfr "$p/card-fr.html" --rawfile cardwip "$p/card-wip.html" --rawfile cardcp "$p/card-cp.html" \
        --rawfile segdone "$p/segment-done.html" --rawfile segtodo "$p/segment-todo.html" \
        --rawfile labelpart "$p/label.html" --rawfile filters "$p/filters.html" --rawfile filter "$p/filter.html" \
        -f "$LIB/tags.jq" > "$work/tags.out"
    mkdir -p "$work/tags"
    # tags.jq's slugs are letters, digits and dashes: no / or . to leave the folder with
    while IFS= read -r path; do
        [[ $path == filters || $path =~ ^[^/.]+/(list_fr|list_wip|list_cp|filters|title)$ ]] || die "bad tag region '$path'"
        if [[ $path == */title ]]; then
            mkdir -p "$work/tags/${path%/*}"
            printf '%s\n' "${path%/*}"
        fi
    done < <(awk '/^\001/ { print substr($0, 2) }' "$work/tags.out")
    awk -v tags="$work/tags" -v regions="$work/regions" '
        /^\001/ { if (f) close(f); n = substr($0, 2); f = (n == "filters") ? regions "/filters.html" : tags "/" n ".html"; next }
        { print > f }' "$work/tags.out"
}

# check_addresses ORIGINAL DATA LIST: the original (built offline) may pin the sha256 of a signed
# list of the wallet's subaddresses ("index address" lines, tools/make-subaddresses.sh). Then
# LIST must be that list, every donation address on the site must be in it, and LIST and its
# signature LIST.asc go out with the site for anyone to check. No pin: nothing to check.
check_addresses() {
    local original=$1 data=$2 list=$3 pin
    pin=$(tr -d ' \n' < "$original/parts/subaddresses.sha256" 2> /dev/null || true)
    [[ $pin ]] || return 0
    listed=1   # global: main publishes the list
    [[ $pin =~ ^[0-9a-f]{64}$ ]] || die "parts/subaddresses.sha256 is not a sha256"
    [[ $list && -f $list && -f $list.asc ]] || die "the original pins a subaddress list: give it (and its .asc) as SUBADDRESSES"
    [[ $(sha256sum < "$list" | cut -d' ' -f1) == "$pin" ]] || die "$list is not the subaddress list the original pins"
    jq -r '.[1].proposals[] | ."donate-address" // empty' "$data/proposals.json" > "$work/addresses"
    awk 'NR == FNR { ok[$2] = 1; next } !($0 in ok) { print "not in the subaddress list: " $0; bad = 1 } END { exit bad }' \
        "$list" "$work/addresses" >&2 || die "a donation address is not one of the wallet's (see above)"
}

main() {
    local original data proposals site subaddresses stage page tag tags
    # absolute paths, then work from /: started by runuser from root's home, the current
    # directory may not be readable (find needs it)
    original=$(readlink -f "${1:?ORIGINAL}") data=$(readlink -f "${2:?DATA}")
    proposals=$(readlink -f "${3:?PROPOSALS}") site=$(readlink -f "${4:?SITE}")
    subaddresses=${5:+$(readlink -f "$5")}
    cd /
    [[ -f $original/index.html && -d $original/parts ]] || die "$original is not a built ccs-front-hugo site"
    [[ -f $original/explore/tag/example/index.html ]] || die "$original has no tag page (explore/tag/example/)"
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
            --rawfile labelpart "$original/parts/label.html" -f "$LIB/regions.jq" > "$work/regions/list_$stage.html"
    done

    check_addresses "$original" "$data" "$subaddresses"
    mapfile -t tags < <(tag_regions "$original" "$data")

    rm -rf "$new"
    mkdir "$new"
    (cd "$original" && tar -c --exclude=./parts --exclude=./proposals --exclude=./explore/tag .) | tar -x -C "$new"
    while IFS= read -r -d '' page; do
        grep -q '<!-- ccs:' "$page" || continue
        fill_page "$page" "$work/regions" > "$page.tmp"
        mv "$page.tmp" "$page"
    done < <(find "$new" -name '*.html' -print0)
    # a page per tag: the original's tag page, at the same depth (its relative links still work)
    for tag in "${tags[@]}"; do
        mkdir -p "$new/explore/tag/$tag"
        fill_page "$original/explore/tag/example/index.html" "$work/tags/$tag" > "$new/explore/tag/$tag/index.html"
    done
    proposal_pages "$original" "$data" "$proposals" "$new"
    # the /projects API goes with the site, so one push carries everything public
    if [[ -f $data/projects.json ]]; then cp "$data/projects.json" "$new/projects.json"; fi
    if [[ ${listed:-} ]]; then
        cp "$subaddresses" "$new/subaddresses.txt" && cp "$subaddresses.asc" "$new/subaddresses.txt.asc"
    fi

    rm -rf "$site.old"
    if [[ -e $site ]]; then mv "$site" "$site.old"; fi
    mv "$new" "$site"
    rm -rf "$site.old"
    log "filled $site (${#tags[@]} tag pages)"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
