#!/usr/bin/env bash
# Tests: fill tests/fixtures/original (ccs-front-hugo's built pages) with tests/fixtures/data
# (ccs-bash's test JSON) and tests/fixtures/proposals (its proposals), compare with
# tests/expected, then the Markdown renderer, then everything that must stop a run.
# UPDATE=1 tests/run.sh rewrites tests/expected (check the diff!).
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
run=$here/../ccs-front-bash.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; status=1; }

props=$here/fixtures/proposals
"$run" "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site" 2> "$tmp/log" || { cat "$tmp/log"; fail "the run"; exit 1; }

pages=(index.html ideas/index.html funding-required/index.html work-in-progress/index.html completed-proposals/index.html
    proposals/near-funded.html proposals/b-wip.html "proposals/c done, (old).html" "proposals/o'quote.html"
    explore/tag/available-to-pick-up/index.html)
if [[ ${UPDATE:-} ]]; then
    for p in "${pages[@]}"; do install -D -m 644 "$tmp/site/$p" "$here/expected/$p"; done
fi
for p in "${pages[@]}"; do
    if diff -u "$here/expected/$p" "$tmp/site/$p" > "$tmp/diff"; then ok "$p"; else cat "$tmp/diff"; fail "$p"; fi
done

# every proposal in the JSON gets a card on its stage's page; the home page has none, only the
# stages' counts
count() { grep -c 'class="card ' "$tmp/site/$1" || true; }
want() { jq "$2" "$here/fixtures/data/$1"; }
fr=$(want proposals.json '.[1].proposals | length') wip=$(want proposals.json '.[2].proposals | length')
idea=$(want proposals.json '.[0].proposals | length') cp=$(want completed-proposals.json '.[0].proposals | length')
if [[ $(count funding-required/index.html) == "$fr" && $(count work-in-progress/index.html) == "$wip" \
    && $(count ideas/index.html) == "$idea" && $(count completed-proposals/index.html) == "$cp" \
    && $(count index.html) == 0 ]]; then
    ok "a card per proposal ($fr fr, $wip wip, $idea ideas, $cp completed), none on the home page"
else
    fail "card counts"
fi
# the stage menu's counts on every kind of page (a proposal page too), the home page's cards'
counts() { grep -A1 "<!-- ccs:${2:-count} " "$tmp/site/$1" | grep -o '^[0-9]*$' | tr '\n' ' '; }
n4="$idea $fr $wip $cp "
if [[ $(counts index.html) == "$n4" && $(counts index.html number) == "$n4" && $(counts funding-required/index.html) == "$n4" \
    && $(counts explore/tag/repurposed/index.html) == "$n4" && $(counts proposals/b-wip.html) == "$n4" ]]; then
    ok "each stage's count, in the menu of every kind of page and on the home page's cards"
else
    fail "stage counts: home '$(counts index.html)' '$(counts index.html number)', proposal '$(counts proposals/b-wip.html)'"
fi
if [[ ! -e $tmp/site/explore/index.html ]]; then ok "no Explore page"; else fail "an Explore page"; fi
if [[ ! -e $tmp/site/parts && ! -e $tmp/site/proposals/example.html ]]; then ok "parts/ and the example pages left out"; else fail "parts/ or an example page published"; fi
if cmp -s "$here/fixtures/data/projects.json" "$tmp/site/projects.json"; then ok "projects.json goes with the site"; else fail "projects.json"; fi
pages_want=$((fr + wip + cp))
if [[ $(find "$tmp/site/proposals" -name '*.html' | wc -l) == "$pages_want" ]]; then ok "a page per proposal in fr, wip, cp ($pages_want)"; else fail "proposal page count"; fi
# the Payouts tab where the original has it (work in progress, completed), not on a funding page,
# which has nothing paid out yet; either way the run fills what is there
if ! grep -q 'tab-payouts' "$tmp/site/proposals/near-funded.html" && grep -q 'tab-payouts' "$tmp/site/proposals/b-wip.html" \
    && grep -q 'tab-payouts' "$tmp/site/proposals/c done, (old).html"; then
    ok "Payouts only on work-in-progress and completed pages, as the original has them"
else
    fail "the Payouts tab"
fi
# the QR code is made here from the address (a PNG: its base64 starts iVBORw0KGgo), never ccs-bash's (the fixture's is the text "QR for
# monero:…", not a PNG): zbarimg reads it back where it is installed (not in the image)
page=$tmp/site/proposals/near-funded.html
addr=$(grep -m 1 -o 'href="monero:[0-9A-Za-z]*"' "$page" | sed 's/^href="monero://; s/"$//')
qr=$(grep -m 1 -o 'src="data:image/png;base64,[A-Za-z0-9+/=]*"' "$page" | sed 's/^src="data:image\/png;base64,//; s/"$//')
if [[ $qr == iVBORw0KGgo* ]] \
    && ! grep -qF "$(jq -r 'first(.[1].proposals[] | ."donate-qr-code" // empty)' "$here/fixtures/data/proposals.json")" "$page"; then
    if command -v zbarimg > /dev/null; then
        base64 -d <<<"$qr" > "$tmp/qr.png"
        if [[ $(zbarimg -q --raw "$tmp/qr.png") == "monero:$addr" ]]; then ok "a funding page's QR code is made here, of its address (zbarimg reads it back)"; else fail "the QR code isn't of its address"; fi
    else
        ok "a funding page's QR code is made here, a PNG, not ccs-bash's (no zbarimg to read it back)"
    fi
else
    fail "QR code on a funding page"
fi

# an idea's 👍/👎, and "–" where ccs-bash couldn't read them
votes=$(grep -A2 'class="votes"' "$tmp/site/ideas/index.html" | grep -o '^[0-9–]*<' | tr -d '<' | tr '\n' ' ')
if [[ $votes == "7 2 – – " ]]; then ok "votes on the idea cards ($votes)"; else fail "votes: '$votes'"; fi

# ccs-bash's escaping is kept, once: no double escaping, nothing unescaped
if grep -q 'Fund &lt;b&gt;this&lt;/b&gt; &amp;amp; that\|Fund &amp;lt;' "$tmp/site/funding-required/index.html"; then
    fail "a name was escaped twice"
elif grep -q 'Fund &lt;b&gt;this&lt;/b&gt; &amp; that' "$tmp/site/funding-required/index.html"; then
    ok "names stay escaped exactly once"
else
    fail "escaped name not found"
fi

# tags: a page per tag (spellings that differ only in case or punctuation are one tag, a tag
# with no letters or digits gets none), with that tag's proposals; filters on Explore
tagpages=$(cd "$tmp/site/explore/tag" && printf '%s ' *)
if [[ $tagpages == "abandoned available-to-pick-up b-x-b-y repurposed " ]]; then ok "a page per tag ($tagpages)"; else fail "tag pages: $tagpages"; fi
if [[ $(count explore/tag/available-to-pick-up/index.html) == 2 && $(count explore/tag/repurposed/index.html) == 1 ]]; then
    ok "a tag page has that tag's proposals, from every stage"
else
    fail "cards on the tag pages"
fi
repurposed=$(jq -rn -L "$here/../lib" 'include "common"; "repurposed" | tag_color')
if grep -q "<a class=\"filter $repurposed\" href=\"../explore/tag/repurposed/\">Repurposed" "$tmp/site/funding-required/index.html" \
    && grep -q "<a class=\"filter $repurposed\" href=\"../explore/tag/repurposed/\">Repurposed" "$tmp/site/proposals/b-wip.html" \
    && grep -q "<a class=\"filter $repurposed active\" href=\"../../../explore/tag/repurposed/\">Repurposed<span class=\"count\">1" "$tmp/site/explore/tag/repurposed/index.html" \
    && grep -q "<span class=\"label $repurposed\">Repurposed</span>" "$tmp/site/completed-proposals/index.html"; then
    ok "the tags in every page's sidebar, the shown one active on its page; a tag has one colour everywhere"
else
    fail "filters"
fi
# a tag page is three folders down: every link to the assets goes three up (the cards' icons
# are the stylesheet's, by class)
if grep -q 'href="../../../assets/style\.' "$tmp/site/explore/tag/repurposed/index.html" \
    && grep -q 'class="icon icon-user"' "$tmp/site/explore/tag/repurposed/index.html" \
    && ! grep -q '"\.\./assets/\|"\.\./\.\./assets/' "$tmp/site/explore/tag/repurposed/index.html"; then
    ok "a tag page's cards have their icons, and it links the assets from three folders down"
else
    fail "icons on a tag page's cards"
fi
mkdir -p "$tmp/notags"
jq '(.. | objects | select(has("tags"))).tags = []' "$here/fixtures/data/proposals.json" > "$tmp/notags/proposals.json"
jq '(.. | objects | select(has("tags"))).tags = []' "$here/fixtures/data/completed-proposals.json" > "$tmp/notags/completed-proposals.json"
"$run" "$here/fixtures/original" "$tmp/notags" "$props" "$tmp/site3" 2> /dev/null
if [[ ! -e $tmp/site3/explore/tag ]] && ! grep -q 'class="filters"' "$tmp/site3/funding-required/index.html"; then
    ok "no tags: no filters, no tag pages"
else
    fail "filters or tag pages without tags"
fi

# Everything below must stop the run and leave the last site as it was.
echo previous > "$tmp/site/marker-of-the-old-site"
must_stop() {   # must_stop WHAT ORIGINAL DATA [SUBADDRESSES]
    local what=$1
    if "$run" "$2" "$3" "$props" "$tmp/site" ${4:+"$4"} 2> "$tmp/log.stop"; then
        fail "$what: the run went on"
    elif [[ ! -e $tmp/site/marker-of-the-old-site || -e $tmp/site.new ]]; then
        fail "$what: the old site was touched"
    else
        ok "$what: stops ($(grep -o 'error: .*' "$tmp/log.stop" | cut -c8-70 || cut -c1-60 "$tmp/log.stop" | head -n 1))"
    fi
}
broken() {   # broken NAME SED: a copy of the original with ideas/index.html changed by SED
    cp -r "$here/fixtures/original" "$tmp/$1"
    sed -i "$2" "$tmp/$1/ideas/index.html"
    echo "$tmp/$1"
}
must_stop "no end marker" "$(broken noend 's#<!-- /ccs:list idea -->##')" "$here/fixtures/data"
must_stop "a marker inside a region" "$(broken nested 's#<!-- /ccs:list idea -->#<!-- ccs:list fr --><!-- /ccs:list idea -->#')" "$here/fixtures/data"
must_stop "an end marker alone" "$(broken stray 's#</main>#<!-- /ccs:list fr --></main>#')" "$here/fixtures/data"
must_stop "a region it can't fill" "$(broken unknown 's#</main>#<!-- ccs:list zz --><!-- /ccs:list zz --></main>#')" "$here/fixtures/data"
must_stop "a marker used twice" "$(broken twice 's#</main>#<!-- ccs:list idea --><!-- /ccs:list idea --></main>#')" "$here/fixtures/data"

mkdir -p "$tmp/unescaped"
cp "$here/fixtures/data/completed-proposals.json" "$tmp/unescaped/"
jq '.[1].proposals[0].name = "<script>x</script>"' "$here/fixtures/data/proposals.json" > "$tmp/unescaped/proposals.json"
must_stop "a value ccs-bash didn't escape" "$here/fixtures/original" "$tmp/unescaped"
jq '.[2].proposals[0].tags = ["<b>"]' "$here/fixtures/data/proposals.json" > "$tmp/unescaped/proposals.json"
must_stop "a tag ccs-bash didn't escape" "$here/fixtures/original" "$tmp/unescaped"

cp -r "$here/fixtures/original" "$tmp/slot"
sed -i 's#{{author}}#{{nonesuch}}#' "$tmp/slot/parts/card-fr.html"
must_stop "a slot with no value" "$tmp/slot" "$here/fixtures/data"

# no absolute link on any page: under /dark/ or /light/ (the theme), every link keeps the prefix
abs=$(grep -rlE '(href|src)="/[^/]' "$tmp/site" --include='*.html' | grep -v '/404.html$' || true)
if [[ -z $abs ]] && grep -q 'href="../proposals/near-funded.html"' "$tmp/site/funding-required/index.html" \
    && grep -q 'href="../../../proposals/' "$tmp/site/explore/tag/repurposed/index.html"; then
    ok "every link relative to its page (a proposal's, a tag's), so /dark/ and /light/ stay while browsing"
else
    printf '%s\n' "$abs" | head -3; fail "absolute links"
fi

# a signed subaddress list (the list, .asc, .key.asc, .pin beside it): every donation address
# must be in it; the Verify page shows the steps and the fingerprint, each donation box links
# there, and the list, signature and key go out with the site
mkdir -p "$tmp/sub"
main=9$(printf '%094d' 0 | tr 0 W)   # the wallet's main address, index 0 (testnet: it starts with 9)
viewkey=$(printf '%064d' 0 | tr 0 a)
# the wallet's subaddresses: every address the fixtures use (funding-required, and /projects')
{ echo "0 $main"; { jq -r '.[1].proposals[] | ."donate-address" // empty' "$here/fixtures/data/proposals.json"
    jq -r '.[] | .address // empty' "$here/fixtures/data/projects.json"; } | awk '!seen[$0]++ { print ++n, $0 }'; } > "$tmp/sub/list.txt"
echo "$viewkey" > "$tmp/sub/list.txt.viewkey"
echo signature > "$tmp/sub/list.txt.asc"
echo key > "$tmp/sub/list.txt.key.asc"
pin() { printf 'sha256 %s\nkey 0123456789ABCDEF0123456789ABCDEF01234567\n' "$(sha256sum < "$tmp/sub/list.txt" | cut -d' ' -f1)" > "$tmp/sub/list.txt.pin"; }
pin
if "$run" "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site4" "$tmp/sub/list.txt" 2> /dev/null \
    && [[ ! -e $tmp/site4/subaddresses.txt && ! -e $tmp/site4/subaddresses.txt.asc ]] \
    && grep -q '0123 4567 89AB CDEF 0123  4567 89AB CDEF 0123 4567' "$tmp/site4/verify/index.html" \
    && grep -q 'class="verify"><a href="../verify/"' "$tmp/site4/proposals/near-funded.html"; then
    ok "a signed list: checked, not copied into the site, the fingerprint on Verify if the design asks for it, a link in each donation box"
else
    fail "a signed list"
fi
v=$tmp/site4/verify/index.html
if [[ $(grep -o "$main" "$v" | wc -l) == 2 && $(grep -o "$viewkey" "$v" | wc -l) == 2 ]] && grep -q 'monero-wallet-rpc --testnet --offline' "$v" \
    && grep -q 'are public (published by this site)' "$v" && ! grep -q '{{' "$v"; then
    ok "Verify: the wallet's address and view key (index 0, list.txt.viewkey), the network from the address, every slot filled"
else
    fail "Verify: asking the wallet"
fi
printf '%s\nsource https://example.org/r/Monero/comments/x?context=3&y=1\nsource-text shared by luigi1111 here\n' "$viewkey" > "$tmp/sub/list.txt.viewkey"
if "$run" "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site5" "$tmp/sub/list.txt" 2> /dev/null \
    && grep -q 'are public (<a href="https://example.org/r/Monero/comments/x?context=3&amp;y=1">shared by luigi1111 here</a>)' "$tmp/site5/verify/index.html"; then
    ok "Verify: the source and source-text lines in list.txt.viewkey become the link to where they were published"
else
    fail "Verify: the source"
fi
printf '%s\nsource https://x.org/"><script>\n' "$viewkey" > "$tmp/sub/list.txt.viewkey"
must_stop "a view key's source that isn't one https link" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
printf '%s\nsource-text <b>x</b>\n' "$viewkey" > "$tmp/sub/list.txt.viewkey"
must_stop "a source-text with HTML in it" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
rm "$tmp/sub/list.txt.viewkey"
must_stop "no view key file, when Verify shows the view key" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
echo "$viewkey" > "$tmp/sub/list.txt.viewkey"
if [[ ! -e $tmp/site/subaddresses.txt ]] && grep -q 'no signed list' "$tmp/site/verify/index.html" \
    && ! grep -q 'class="verify"' "$tmp/site/proposals/near-funded.html"; then
    ok "no list: none published, Verify says so, no link in the donation boxes"
else
    fail "without a list"
fi
cp "$tmp/sub/list.txt.pin" "$tmp/sub/pin.good"
sed -i '2d' "$tmp/sub/list.txt" && pin
# a foreign address in /projects (ccs-bash's projects.json goes out with the site): taken out, exit 3
rm -rf "$tmp/data-p" "$tmp/site6"; cp -r "$here/fixtures/data" "$tmp/data-p"
foreign=8$(printf '%094d' 0 | tr 0 Z)
jq --arg a "$foreign" '.[-1].address = $a' "$here/fixtures/data/projects.json" > "$tmp/data-p/projects.json"
set +e; "$run" "$here/fixtures/original" "$tmp/data-p" "$props" "$tmp/site6" "$tmp/sub/list.txt" 2> "$tmp/log.p"; rc=$?; set -e
if [[ $rc == 3 && -f $tmp/site6/projects.json ]] && ! grep -q "$foreign" "$tmp/site6/projects.json" \
    && [[ $(jq length "$tmp/site6/projects.json") == $(jq length "$here/fixtures/data/projects.json") ]] \
    && grep -q '/projects: .*taken out' "$tmp/log.p"; then
    ok "a foreign address in /projects: taken out (the rest of it kept), exit 3"
else
    fail "a foreign address in /projects (exit $rc)"; cat "$tmp/log.p" >&2
fi
# an address not in the list: that proposal is left off (its page, its card), the rest made, exit 3
rm -rf "$tmp/site5"; set +e
"$run" "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site5" "$tmp/sub/list.txt" 2> "$tmp/log.off"; rc=$?; set -e
if [[ $rc == 3 && ! -e $tmp/site5/proposals/near-funded.html && -f $tmp/site5/proposals/new-fund.html ]] \
    && ! grep -rq 'near-funded' "$tmp/site5/funding-required" "$tmp/site5/index.html" \
    && grep -q 'left off the site: /proposals/near-funded.html' "$tmp/log.off"; then
    ok "an address not in the list: that proposal left off (page, cards), the rest made, exit 3"
else
    fail "an address not in the list (exit $rc)"; cat "$tmp/log.off" >&2
fi
cp "$tmp/sub/pin.good" "$tmp/sub/list.txt.pin"
must_stop "a list that isn't the one its .pin names" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
rm "$tmp/sub/list.txt.key.asc"
must_stop "a list without its key" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"

# one pass: a value that looks like a slot or a marker is text, never filled again
mkdir -p "$tmp/literal"
cp "$here/fixtures/data/completed-proposals.json" "$tmp/literal/"
jq '.[1].proposals[0].name = "{{author}} &lt;!-- ccs:list fr --&gt;"' "$here/fixtures/data/proposals.json" > "$tmp/literal/proposals.json"
"$run" "$here/fixtures/original" "$tmp/literal" "$props" "$tmp/site2" 2> /dev/null
if grep -q '<h3>{{author}} &lt;!-- ccs:list fr --&gt;</h3>' "$tmp/site2/funding-required/index.html"; then
    ok "a title with {{author}} or a marker in it stays text"
else
    fail "a title was filled again"
fi

# The Markdown renderer: hostile text stays text, links only https/#/site-relative (never one a
# browser reads as another site's: //host, /\host, /&#47;host), and the
# same HTML from every awk there is (mawk, gawk, busybox: CI has the first two).
cat > "$tmp/evil.md" <<'MD'
---
layout: fr
milestones:
  - name: "<img src=x onerror=alert(1)>"
    funds: 1
---
<script>alert(1)</script> <img src=x onerror=alert(1)> <a href="javascript:alert(1)">x</a>
[click](javascript:alert(1)) [data](data:text/html,x) [ok](https://getmonero.org/) ![pic](https://example.org/p.png)
[a](//evil.example/) [b](/\evil.example) [c](/&#47;evil.example) [d](/&#x2f;evil.example) [here](/proposals/x.html)
`<b>` **bold** <!-- ccs:list fr --> {{name}} &nbsp; &#8212; &amp;lt;
	tab	and controls
MD
printf 'x999y
' >> "$tmp/evil.md"
awks=()
for a in mawk gawk "busybox awk"; do
    command -v "${a%% *}" > /dev/null && $a 'BEGIN { exit 0 }' 2> /dev/null && awks+=("$a")
done
first=
for a in "${awks[@]}"; do
    $a -f "$here/../lib/markdown.awk" "$tmp/evil.md" > "$tmp/evil.${a// /_}" || fail "markdown.awk on $a"
    [[ $first ]] || first=$tmp/evil.${a// /_}
    cmp -s "$first" "$tmp/evil.${a// /_}" || fail "$a renders differently from ${awks[0]}"
done
body=$(jq -r '.body' "$first")
# (a proposal's own \001 and \002 are dropped: "x999y" stays text, never held HTML number 999)
if [[ $body == *'<script'* || $body == *'<img'* || $body == *'onerror=alert(1)>'* || $body == *'href="javascript'* \
    || $body == *'href="data'* || $body == *'<!-- ccs'* || $body != *'x999y'* \
    || $body == *'href="//'* || $body == *"href=\"/\\"* || $body == *'href="/&'* ]]; then
    echo "$body"; fail "hostile Markdown got through"
elif [[ $body == *'<a href="https://getmonero.org/">ok</a>'* && $body == *'<a href="/proposals/x.html">here</a>'* && $body == *'<a href="https://example.org/p.png">image: pic</a>'* && $body == *'&nbsp; &#8212; &amp;lt;'* ]]; then
    ok "hostile Markdown stays text, the same on ${#awks[@]} awk(s): ${awks[*]}"
else
    echo "$body"; fail "the Markdown renderer lost something"
fi
if [[ $(jq -r '.milestones[0][0]' "$first") == '<img src=x onerror=alert(1)>' ]]; then
    ok "front matter milestones read as text (escaped later, by jq)"
else
    fail "milestones from the front matter"
fi
if grep -q '&lt;img src=x' "$tmp/site/proposals/near-funded.html" || ! grep -q '<img src=x' "$tmp/site/proposals/near-funded.html"; then
    ok "no raw HTML from front matter on a page"
else
    fail "raw HTML from front matter on a page"
fi

# Images: a proposal's own images ccs-bash copied (images.json, images/<proposal>/) show from the
# site's images/, relative to the page; any other stays a link; a list entry that isn't
# images/<proposal>/<file> for a file that is there is ignored, and nothing outside images/ is copied.
im=$(mktemp -d)
cp -r "$here/fixtures/data" "$im/data" && cp -r "$props" "$im/props" && mkdir -p "$im/data/images/near-funded"
printf 'png bytes' > "$im/data/images/near-funded/chart.png"
touch -d @1700000000 "$im/data/images/near-funded/chart.png"   # the copy keeps this time
printf 'secret' > "$im/data/secret.png"
printf '\n![a chart](images/near-funded/chart.png "t") and ![other](https://elsewhere.example/x.png) and ![sneaky](images/../secret.png) ![odd](images/x/y.png)\n' >> "$im/props/near-funded.md"
jq -n '{"images/near-funded/chart.png": "near-funded/chart.png", "images/../secret.png": "../secret.png",
    "images/x/y.png": "near-funded/chart.png", "images/a\"b/c.png": "a\"b/c.png"}' > "$im/data/images.json"
if "$run" "$here/fixtures/original" "$im/data" "$im/props" "$im/site" 2> "$im/log"; then
    page=$im/site/proposals/near-funded.html
    if grep -qF '<img src="../images/near-funded/chart.png" alt="a chart" loading="lazy">' "$page" \
        && grep -qF '<a href="https://elsewhere.example/x.png">image: other</a>' "$page" \
        && ! grep -q 'src="[^"]*secret' "$page" && ! grep -q 'src="[^"]*images/x/' "$page" \
        && [[ $(cd "$im/site/images" && echo */*) == near-funded/chart.png ]] && [[ ! -e $im/site/secret.png ]] \
        && [[ $(date -r "$im/site/images/near-funded/chart.png" +%s) == 1700000000 ]]; then
        ok "images: a proposal's own copied image shows from the site (relative, with its time), others stay links, bad entries ignored"
    else
        grep -oE '<img[^>]*>|<a href="[^"]*">image[^<]*</a>|image: [a-z]+[^<]*' "$page"; (cd "$im/site/images" 2> /dev/null && echo */*); fail "images"
    fi
else
    cat "$im/log"; fail "images: the run"
fi
rm -rf "$im"

# The footer's onion line: an original whose footer has the onion region (every page, the proposal
# pages and the tag pages too) and the onion part: with CCS_ONION, the part filled with it on every
# page; without, the region empty; an address that isn't one stops the run. An original from before
# (no region, no part) runs with CCS_ONION all the same, with no line.
on=$(mktemp -d)
cp -r "$here/fixtures/original" "$on/original"
find "$on/original" -name '*.html' -exec grep -l '</footer>' {} + | while IFS= read -r f; do
    sed -i 's#</footer>#<!-- ccs:onion -->\n<!-- /ccs:onion -->\n</footer>#' "$f"
done
printf '%s\n' '<p class="footer-onion">Also on Tor: <a href="http://{{onion}}/">{{onion}}</a></p>' > "$on/original/parts/onion.html"
o=abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion
pages() { find "$1" -name '*.html' ! -path '*/parts/*' -exec grep -l '</footer>' {} + | wc -l; }
if CCS_ONION=$o "$run" "$on/original" "$here/fixtures/data" "$props" "$on/site" 2> "$on/log" \
    && n=$(pages "$on/site") && ((n > 3)) \
    && [[ $(find "$on/site" -name '*.html' -exec grep -l "Also on Tor: <a href=\"http://$o/\">$o</a>" {} + | wc -l) == "$n" ]] \
    && [[ -n $(find "$on/site/proposals" -name '*.html' -exec grep -l "$o" {} + | head -n 1) ]]; then
    ok "CCS_ONION: the footer's onion line on every page ($n, proposal and tag pages too)"
else cat "$on/log"; fail "the onion line"; fi
if "$run" "$on/original" "$here/fixtures/data" "$props" "$on/site2" 2> /dev/null && ! grep -rq 'Also on Tor' "$on/site2" \
    && grep -q '<!-- ccs:onion -->' "$on/site2/index.html"; then
    ok "no CCS_ONION: the onion region empty"
else fail "no onion"; fi
if ! CCS_ONION=evil.example "$run" "$on/original" "$here/fixtures/data" "$props" "$on/site3" 2> "$on/log3" \
    && grep -q 'CCS_ONION is not an onion address' "$on/log3" && [[ ! -e $on/site3 ]]; then
    ok "CCS_ONION that isn't an onion address: the run stops, no site"
else fail "a bad CCS_ONION"; fi
if CCS_ONION=$o "$run" "$here/fixtures/original" "$here/fixtures/data" "$props" "$on/site4" 2> /dev/null && ! grep -rq 'Also on Tor' "$on/site4"; then
    ok "CCS_ONION with an original from before the onion line: runs, no line"
else fail "an old original with CCS_ONION"; fi
rm -rf "$on"

# The feed (feed.xml): with CCS_SITE_URL, the proposals put to Funding Required and fully funded,
# newest first, as tests/expected/feed.xml (a title's markup as ‹ ›, a name's space as %20); none
# without it; an address that isn't a site's stops the run
fd=$(mktemp -d); mkdir "$fd/data"; cp "$here/fixtures/data"/*.json "$fd/data/"
# shellcheck disable=SC2016
dates='def at($u; $k; $v): if ."local-url" == $u then .[$k] = $v else . end;
  map(.proposals |= map(at("/proposals/near-funded.html"; "funding-required-at"; "2026-10-01T10:00:00Z")
    | at("/proposals/a-fund.html"; "funding-required-at"; "2026-10-02T00:00:00Z") | at("/proposals/a-fund.html"; "funded-at"; "2026-10-03T12:30:00Z")
    | at("/proposals/b-wip.html"; "funded-at"; "2026-09-01T00:00:00Z") | at("/proposals/ leading-space.html"; "funding-required-at"; "2026-10-04T08:00:05Z")
    | at("/proposals/dots-end.html"; "funding-required-at"; "2026-01-01T00:00:00Z")))'
for f in proposals completed-proposals; do jq "$dates" "$here/fixtures/data/$f.json" > "$fd/data/$f.json"; done
if CCS_SITE_URL=https://ccs.example.org/ "$run" "$here/fixtures/original" "$fd/data" "$props" "$fd/site" 2> "$fd/log" \
    && diff -u "$here/expected/feed.xml" "$fd/site/feed.xml"; then
    ok "CCS_SITE_URL: feed.xml, Funding Required and fully funded, newest first (expected/feed.xml)"
else cat "$fd/log"; fail "the feed"; fi
if "$run" "$here/fixtures/original" "$fd/data" "$props" "$fd/site2" 2> /dev/null && [[ ! -e $fd/site2/feed.xml ]]; then
    ok "no CCS_SITE_URL: no feed"
else fail "a feed without CCS_SITE_URL"; fi
if ! CCS_SITE_URL=https://ccs.example.org/x "$run" "$here/fixtures/original" "$fd/data" "$props" "$fd/site3" 2> "$fd/log3" \
    && grep -q "CCS_SITE_URL is not a site's address" "$fd/log3" && [[ ! -e $fd/site3 ]]; then
    ok "CCS_SITE_URL with a path: the run stops, no site"
else fail "a bad CCS_SITE_URL"; fi
rm -rf "$fd"

exit "$status"
