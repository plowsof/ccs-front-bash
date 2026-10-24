#!/usr/bin/env bash
# ccs-front-bash.sh ORIGINAL DATA PROPOSALS SITE [SUBADDRESSES]: fill the original (ccs-front-hugo's
# built site) with ccs-bash's JSON in DATA and the proposals' Markdown in PROPOSALS, into a new
# SITE. With SUBADDRESSES, a signed list of the wallet's subaddresses (see check_addresses), every
# donation address must be in it. Every piece of HTML comes from the original's pages and parts;
# this only fills them. The original is never changed; SITE is replaced only once the new one is
# complete. Needs no network.
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
        --rawfile labellink "$p/label-link.html" \
        --rawfile cidea "$work/regions/count_idea.html" --rawfile cfr "$work/regions/count_fr.html" \
        --rawfile cwip "$work/regions/count_wip.html" --rawfile ccp "$work/regions/count_cp.html" \
        --rawfile filters "$work/regions/filters.html" --arg verifylink "$verify_link" -f "$LIB/pages.jq" > "$work/pages"
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

# check_addresses ORIGINAL DATA LIST: with a signed list of the wallet's subaddresses (LIST,
# "index address" lines, tools/make-subaddresses.sh; beside it LIST.asc, LIST.key.asc and
# LIST.pin, its sha256 and the key's fingerprint, tools/sign-subaddresses.sh), LIST must be the
# one LIST.pin names and every donation address on the site must be in it; the Verify page gets
# the steps and the fingerprint, each donation box a link there, and the list, signature and key
# go out with the site. If the Verify part asks for them, it also gets the wallet's main address
# (the list's index 0), its view key (LIST.viewkey: public; a line "source <https link>" says
# where it was published, and "source-text <words>" what that link says) and the network, so a visitor can ask a copy of the wallet about an
# address. No LIST: no check, and the Verify
# page says there is no list yet.
check_addresses() {
    local original=$1 data=$2 list=$3 sum fpr f main vk net src text
    verify_link=''   # global, for pages.jq: the donation boxes' link to /verify/
    if [[ -z $list ]]; then
        cp "$original/parts/no-list.html" "$work/regions/verify.html"
        return 0
    fi
    for f in "$list" "$list.asc" "$list.key.asc" "$list.pin"; do [[ -f $f ]] || die "no $f (see docs/setup.md, step 5)"; done
    sum=$(sed -n 's/^sha256 *//p' "$list.pin") fpr=$(sed -n 's/^key *//p' "$list.pin")
    [[ $sum =~ ^[0-9a-f]{64}$ && $fpr =~ ^[0-9A-F]{40}$ ]] || die "$list.pin: want a 'sha256 <hex>' and a 'key <fingerprint>' line"
    [[ $(sha256sum < "$list" | cut -d' ' -f1) == "$sum" ]] || die "$list is not the list $list.pin pins"
    jq -r '.[1].proposals[] | ."donate-address" // empty' "$data/proposals.json" > "$work/addresses"
    awk 'NR == FNR { ok[$2] = 1; next } !($0 in ok) { print "not in the subaddress list: " $0; bad = 1 } END { exit bad }' \
        "$list" "$work/addresses" >&2 || die "a donation address is not one of the wallet's (see above)"
    listed=1   # global: main publishes the list
    # the fingerprint as gpg shows it: 10 groups of 4, two spaces in the middle (hex: nothing to escape)
    fpr=$(sed -E 's/(.{4})/\1 /g; s/ $//; s/^((.{4} ){5})/\1 /' <<<"$fpr")
    f=$(cat "$original/parts/verify.html")
    if [[ $f == *'{{address}}'* || $f == *'{{viewkey}}'* || $f == *'{{network}}'* || $f == *'{{wallet_source}}'* ]]; then
        main=$(awk '$1 == "0" { print $2; exit }' "$list")
        [[ $main =~ ^[0-9A-Za-z]{95}$ ]] || die "$list has no index 0 (the wallet's main address), which the Verify page shows"
        [[ -f $list.viewkey ]] || die "no $list.viewkey: the wallet's view key, which the Verify page shows (see docs/setup.md, step 5)"
        vk=$(head -n 1 "$list.viewkey" | tr -d ' ')
        [[ $vk =~ ^[0-9a-f]{64}$ ]] || die "$list.viewkey: want the view key's 64 hex characters on its first line"
        src=$(sed -n 's/^source  *//p' "$list.viewkey")
        text=$(sed -n 's/^source-text  *//p' "$list.viewkey")
        [[ $text =~ ^[A-Za-z0-9\ .,:\'_-]*$ ]] || die "$list.viewkey: source-text: letters, digits, spaces and .,:'_- only"
        text=${text//\'/"&#39;"}   # a quoted replacement: in bash 5.2+ an unquoted & means the match
        if [[ -z $src ]]; then
            src='published by this site'
        elif [[ $src =~ ^https://[A-Za-z0-9._~:/?#@!$\&\'()*+,\;=%-]+$ && $src != *\"* ]]; then
            src="<a href=\"${src//&/"&amp;"}\">${text:-where they were published}</a>"
        else
            die "$list.viewkey: the source must be one https link"
        fi
        case $main in 9* | A*) net=' --testnet' ;; 5* | 7*) net=' --stagenet' ;; *) net='' ;; esac
        # base58 and hex: nothing to escape
        f=${f//\{\{address\}\}/"$main"} f=${f//\{\{viewkey\}\}/"$vk"} f=${f//\{\{network\}\}/"$net"}
        f=${f//\{\{wallet_source\}\}/"$src"}
    fi
    printf '%s\n' "${f//\{\{fingerprint\}\}/"$fpr"}" > "$work/regions/verify.html"
    verify_link=$(cat "$original/parts/verify-link.html")
}

main() {
    local original data proposals site subaddresses stage page tag tags f
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
    # how many proposals each stage has: "count" in the stage menu (every page), "number" on the
    # home page's stage cards
    while read -r stage n; do
        printf '%s\n' "$n" > "$work/regions/count_$stage.html"
        printf '%s\n' "$n" > "$work/regions/number_$stage.html"
    done < <(jq -r --slurpfile c "$data/completed-proposals.json" \
        '"idea \(.[0].proposals | length)", "fr \(.[1].proposals | length)", "wip \(.[2].proposals | length)", "cp \($c[0][0].proposals | length)"' \
        "$data/proposals.json")

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
        cp "$work/regions"/count_*.html "$work/tags/$tag/"
        mkdir -p "$new/explore/tag/$tag"
        fill_page "$original/explore/tag/example/index.html" "$work/tags/$tag" > "$new/explore/tag/$tag/index.html"
    done
    proposal_pages "$original" "$data" "$proposals" "$new"
    # the /projects API goes with the site, so one push carries everything public
    if [[ -f $data/projects.json ]]; then cp "$data/projects.json" "$new/projects.json"; fi
    if [[ ${listed:-} ]]; then
        for f in "" .asc .key.asc; do cp "$subaddresses$f" "$new/subaddresses.txt$f"; done
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
