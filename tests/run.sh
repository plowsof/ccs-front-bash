#!/usr/bin/env bash
# Fills the fixture site with the fixture data and compares it with tests/expected.
# Then tests the Markdown renderer, and everything that must stop a run.
# UPDATE=1 tests/run.sh rewrites tests/expected. Check the diff.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
front=$here/../ccs-front-bash.sh
# The signed list holds every address the fixtures use, with QR codes and a pin.
# The signature and key are stand-ins. Every run gets it.
list=$here/fixtures/list/list.txt
run() { if (($# == 4)); then "$front" "$@" "$list"; else "$front" "$@"; fi; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; status=1; }

props=$here/fixtures/proposals
run "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site" 2> "$tmp/log" || { cat "$tmp/log"; fail "the run"; exit 1; }

pages=(index.html ideas/index.html funding-required/index.html work-in-progress/index.html completed-proposals/index.html
    proposals/near-funded.html proposals/b-wip.html "proposals/c done, (old).html" "proposals/o'quote.html"
    explore/tag/available-to-pick-up/index.html)
if [[ ${UPDATE:-} ]]; then
    for p in "${pages[@]}"; do install -D -m 644 "$tmp/site/$p" "$here/expected/$p"; done
fi
for p in "${pages[@]}"; do
    if diff -u "$here/expected/$p" "$tmp/site/$p" > "$tmp/diff"; then ok "$p"; else cat "$tmp/diff"; fail "$p"; fi
done

# Every proposal gets a card on its stage's page. The home page shows only the counts.
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
# The stage menu's counts on every kind of page, and the home page's cards.
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
if cmp -s "$here/fixtures/data/site-data.json" "$tmp/site/site-data.json"; then ok "site-data.json goes with the site, as it is"; else fail "site-data.json"; fi
pages_want=$((fr + wip + cp))
if [[ $(find "$tmp/site/proposals" -name '*.html' | wc -l) == "$pages_want" ]]; then ok "a page per proposal in fr, wip, cp ($pages_want)"; else fail "proposal page count"; fi
# The Payouts tab is on work in progress and completed pages, not on funding pages.
if ! grep -q 'tab-payouts' "$tmp/site/proposals/near-funded.html" && grep -q 'tab-payouts' "$tmp/site/proposals/b-wip.html" \
    && grep -q 'tab-payouts' "$tmp/site/proposals/c done, (old).html"; then
    ok "Payouts only on work-in-progress and completed pages, as the original has them"
else
    fail "the Payouts tab"
fi
# The QR code is the signed list's file, never ccs-bash's. No data: image on any page.
page=$tmp/site/proposals/near-funded.html
addr=$(grep -m 1 -o 'href="monero:[0-9A-Za-z]*"' "$page" | sed 's/^href="monero://; s/"$//')
if grep -qF "<img src=\"../qr/$addr.png\"" "$page" && cmp -s "$tmp/site/qr/$addr.png" "$here/fixtures/list/list.txt.qr/$addr.png" \
    && [[ -z $(find "$tmp/site" -name '*.html' -exec grep -lF 'data:image' {} +) ]] \
    && ! grep -qF "$(jq -r 'first(.[1].proposals[] | ."donate-qr-code" // empty)' "$here/fixtures/data/proposals.json")" "$page" \
    && [[ $(find "$tmp/site/qr" -type f | wc -l) == $(jq '[.[1].proposals[]."donate-address" // empty] | unique | length' "$here/fixtures/data/proposals.json") ]]; then
    ok "a funding page's QR code: qr/<address>.png, the list's file, one per donation address, no data: image"
else
    fail "QR code on a funding page"
fi

# An idea's 👍/👎, and "–" where they couldn't be read.
votes=$(grep -A2 'class="votes"' "$tmp/site/ideas/index.html" | grep -o '^[0-9–]*<' | tr -d '<' | tr '\n' ' ')
if [[ $votes == "7 2 – – " ]]; then ok "votes on the idea cards ($votes)"; else fail "votes: '$votes'"; fi

# ccs-bash's escaping is kept once: nothing escaped twice, nothing unescaped.
if grep -q 'Fund &lt;b&gt;this&lt;/b&gt; &amp;amp; that\|Fund &amp;lt;' "$tmp/site/funding-required/index.html"; then
    fail "a name was escaped twice"
elif grep -q 'Fund &lt;b&gt;this&lt;/b&gt; &amp; that' "$tmp/site/funding-required/index.html"; then
    ok "names stay escaped exactly once"
else
    fail "escaped name not found"
fi

# A page per tag, with its proposals. Case and punctuation don't make a new tag.
# A tag with no letters or digits gets no page.
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
# A tag page is three folders down, so its asset links go three up.
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
run "$here/fixtures/original" "$tmp/notags" "$props" "$tmp/site3" 2> /dev/null
if [[ ! -e $tmp/site3/explore/tag ]] && ! grep -q 'class="filters"' "$tmp/site3/funding-required/index.html"; then
    ok "no tags: no filters, no tag pages"
else
    fail "filters or tag pages without tags"
fi

# Everything below must stop the run and leave the last site as it was.
echo previous > "$tmp/site/marker-of-the-old-site"
must_stop() {   # must_stop WHAT ORIGINAL DATA [SUBADDRESSES]
    local what=$1
    if run "$2" "$3" "$props" "$tmp/site" ${4:+"$4"} 2> "$tmp/log.stop"; then
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

# No absolute links, so a page under /dark/ or /light/ keeps the prefix.
abs=$(find "$tmp/site" -name '*.html' ! -name 404.html -exec grep -lE '(href|src)="/[^/]' {} + || true)
if [[ -z $abs ]] && grep -q 'href="../proposals/near-funded.html"' "$tmp/site/funding-required/index.html" \
    && grep -q 'href="../../../proposals/' "$tmp/site/explore/tag/repurposed/index.html"; then
    ok "every link relative to its page (a proposal's, a tag's), so /dark/ and /light/ stay while browsing"
else
    printf '%s\n' "$abs" | head -3; fail "absolute links"
fi

# Every donation address must be on the signed list.
# The Verify page shows the fingerprint, and each donation box links to it.
# The list, signature and key go out with the site.
cp -r "$here/fixtures/list" "$tmp/sub"
main=$(awk 'NR == 1 { print $2 }' "$tmp/sub/list.txt")   # the wallet's main address, index 0 (testnet: it starts with 9)
viewkey=$(head -n 1 "$tmp/sub/list.txt.viewkey")
pin() { printf 'sha256 %s\nkey 0123456789ABCDEF0123456789ABCDEF01234567\nqr %s\n' "$(sha256sum < "$tmp/sub/list.txt" | cut -d' ' -f1)" \
    "$(sha256sum < "$tmp/sub/list.txt.qr.sha256" | cut -d' ' -f1)" > "$tmp/sub/list.txt.pin"; }
pin
if run "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site4" "$tmp/sub/list.txt" 2> /dev/null \
    && [[ ! -e $tmp/site4/subaddresses.txt && ! -e $tmp/site4/subaddresses.txt.asc ]] \
    && grep -q '0123 4567 89AB CDEF 0123  4567 89AB CDEF 0123 4567' "$tmp/site4/verify/index.html" \
    && grep -q 'class="verify"><a href="../verify/"' "$tmp/site4/proposals/near-funded.html" \
    && cmp -s "$tmp/site4/qr/$addr.png" "$tmp/sub/list.txt.qr/$addr.png"; then
    ok "a signed list: checked, not copied into the site, the fingerprint on Verify if the design asks for it, a link in each donation box, the list's QR codes"
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
if run "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site5" "$tmp/sub/list.txt" 2> /dev/null \
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
if ! "$front" "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/nolist" 2> "$tmp/log.nolist" \
    && grep -q 'no signed subaddress list' "$tmp/log.nolist" && [[ ! -e $tmp/nolist ]]; then
    ok "no list: the run stops (the QR codes are the list's)"
else
    fail "without a list"
fi
cp "$tmp/sub/list.txt.pin" "$tmp/sub/pin.good"; cp "$tmp/sub/list.txt" "$tmp/sub/list.good"
sed -i '2d' "$tmp/sub/list.txt" && pin
# A foreign address in /projects is taken out, and the run exits 3.
rm -rf "$tmp/data-p" "$tmp/site6"; cp -r "$here/fixtures/data" "$tmp/data-p"
foreign=8$(printf '%094d' 0 | tr 0 Z)
jq --arg a "$foreign" '.[-1].address = $a' "$here/fixtures/data/projects.json" > "$tmp/data-p/projects.json"
set +e; run "$here/fixtures/original" "$tmp/data-p" "$props" "$tmp/site6" "$tmp/sub/list.txt" 2> "$tmp/log.p"; rc=$?; set -e
if [[ $rc == 3 && -f $tmp/site6/projects.json ]] && ! grep -q "$foreign" "$tmp/site6/projects.json" \
    && [[ $(jq length "$tmp/site6/projects.json") == $(jq length "$here/fixtures/data/projects.json") ]] \
    && grep -q '/projects: .*taken out' "$tmp/log.p"; then
    ok "a foreign address in /projects: taken out (the rest of it kept), exit 3"
else
    fail "a foreign address in /projects (exit $rc)"; cat "$tmp/log.p" >&2
fi
# A proposal whose address is not on the list is left off. The rest is made, and the run exits 3.
rm -rf "$tmp/site5"; set +e
run "$here/fixtures/original" "$here/fixtures/data" "$props" "$tmp/site5" "$tmp/sub/list.txt" 2> "$tmp/log.off"; rc=$?; set -e
if [[ $rc == 3 && ! -e $tmp/site5/proposals/near-funded.html && -f $tmp/site5/proposals/new-fund.html ]] \
    && ! grep -rq 'near-funded' "$tmp/site5/funding-required" "$tmp/site5/index.html" \
    && grep -q 'left off the site: /proposals/near-funded.html' "$tmp/log.off"; then
    ok "an address not in the list: that proposal left off (page, cards), the rest made, exit 3"
else
    fail "an address not in the list (exit $rc)"; cat "$tmp/log.off" >&2
fi
cp "$tmp/sub/pin.good" "$tmp/sub/list.txt.pin"
must_stop "a list that isn't the one its .pin names" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
# The list's QR codes must match the pin.
cp "$tmp/sub/list.good" "$tmp/sub/list.txt"
said() { if grep -q "$1" "$tmp/log.stop"; then ok "  (it says: $1)"; else fail "  not for its reason: $(cat "$tmp/log.stop")"; fi; }
cp "$tmp/sub/list.txt.qr/$addr.png" "$tmp/sub/qr.good"
cp "$tmp/sub/list.txt.qr/$main.png" "$tmp/sub/list.txt.qr/$addr.png"
must_stop "a QR code of the list's that is not its sum" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
said "is not its sum"
cp "$tmp/sub/qr.good" "$tmp/sub/list.txt.qr/$addr.png"
echo >> "$tmp/sub/list.txt.qr.sha256"
must_stop "QR codes' sums that aren't the ones its .pin names" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
said "is not the one .* pins"
sed -i '$d' "$tmp/sub/list.txt.qr.sha256"
sed -i '/^qr /d' "$tmp/sub/list.txt.pin"
must_stop "a .pin without its qr line" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"
said "no 'qr <sha256>' line"
cp "$tmp/sub/pin.good" "$tmp/sub/list.txt.pin"
rm "$tmp/sub/list.txt.key.asc"
must_stop "a list without its key" "$here/fixtures/original" "$here/fixtures/data" "$tmp/sub/list.txt"

# One pass: a value that looks like a slot or marker stays text.
mkdir -p "$tmp/literal"
cp "$here/fixtures/data/completed-proposals.json" "$tmp/literal/"
jq '.[1].proposals[0].name = "{{author}} &lt;!-- ccs:list fr --&gt;"' "$here/fixtures/data/proposals.json" > "$tmp/literal/proposals.json"
run "$here/fixtures/original" "$tmp/literal" "$props" "$tmp/site2" 2> /dev/null
if grep -q '<h3>{{author}} &lt;!-- ccs:list fr --&gt;</h3>' "$tmp/site2/funding-required/index.html"; then
    ok "a title with {{author}} or a marker in it stays text"
else
    fail "a title was filled again"
fi

# The Markdown renderer. Hostile text stays text.
# Links are only https, #anchor or site-relative, never //host, /\host or /&#47;host.
# mawk, gawk and busybox awk must give the same HTML.
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
# A proposal's own \001 and \002 are dropped, so "x999y" stays text.
if [[ $body == *'<script'* || $body == *'<img'* || $body == *'onerror=alert(1)>'* || $body == *'href="javascript'* \
    || $body == *'href="data'* || $body == *'<!-- ccs'* || $body != *'x999y'* \
    || $body == *'href="//'* || $body == *"href=\"/\\"* || $body == *'href="/&'* ]]; then
    echo "$body"; fail "hostile Markdown got through"
elif [[ $body == *'<a href="https://getmonero.org/">ok</a>'* && $body == *'<a href="/proposals/x.html">here</a>'* && $body == *'<a href="https://example.org/p.png">image: pic</a>'* && $body == *'&nbsp; &#8212; &amp;lt;'* ]]; then
    ok "hostile Markdown stays text, the same on ${#awks[@]} awk(s): ${awks[*]}"
else
    echo "$body"; fail "the Markdown renderer lost something"
fi

# Headings go one level down: # is h2, ##### is h6, and ###### stays h6.
printf -- '---\nlayout: fr\ntitle: T\n---\n# Who\n## Plan\n##### Five\n###### Six\n' > "$tmp/h.md"
for a in "${awks[@]}"; do
    hb=$($a -f "$here/../lib/markdown.awk" "$tmp/h.md" | jq -r '.body')
    if [[ $hb == *'<h2 id="who">Who</h2>'* && $hb == *'<h3 id="plan">Plan</h3>'* && $hb == *'<h6 id="five">Five</h6>'* && $hb == *'<h6 id="six">Six</h6>'* && $hb != *'<h1'* ]]; then :
    else echo "$hb"; fail "headings on $a: not one level down"; fi
done
ok "a proposal's headings one level down (# is h2), under the page's title"
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

# Only the named entities the gate's scan reads are kept; any other shows as written (&Alpha; is a
# Greek A). A line over 4000 characters is cut, and a body over 100,000: rendering them slows
# down sharply.
{ printf -- '---\nlayout: fr\n---\n&Alpha;&amp;&nbsp;&rsquo;&#913;\n\n'; printf '%9000s\n\n' '' | tr ' ' '<'   # (busybox's head has no -c)
  for _ in $(seq 30); do printf '%3990s\n\n' '' | tr ' ' a; done; } > "$tmp/big.md"
for a in "${awks[@]}"; do
    start=$SECONDS
    bb=$($a -f "$here/../lib/markdown.awk" "$tmp/big.md" | jq -r '.body')
    if [[ $bb == *'&amp;Alpha;&amp;&nbsp;&rsquo;&#913;'* && $bb == *'(line cut: over 4000 characters)'* && $bb == *'(The rest of this proposal is not shown: over 100000 characters.)'* ]] && ((SECONDS - start < 60)); then :
    else echo "${bb:0:300}"; fail "entities and limits on $a"; fi
done
ok "only the named entities the gate reads kept; long lines cut, long bodies stopped, quickly"

# A proposal's own images show from the site's images/. Any other image stays a link.
# A bad entry in images.json is ignored, and nothing outside images/ is copied.
im=$(mktemp -d)
cp -r "$here/fixtures/data" "$im/data" && cp -r "$props" "$im/props" && mkdir -p "$im/data/images/near-funded"
printf 'png bytes' > "$im/data/images/near-funded/chart.png"
touch -d @1700000000 "$im/data/images/near-funded/chart.png"   # the copy keeps this time
printf 'secret' > "$im/data/secret.png"
printf '\n![a chart](images/near-funded/chart.png "t") and ![other](https://elsewhere.example/x.png) and ![sneaky](images/../secret.png) ![odd](images/x/y.png)\n' >> "$im/props/near-funded.md"
# Alt text is plain text: a link or code span in it never ends the attribute
tick='`'
printf '\n![https://x/onerror=alert(1)//](images/near-funded/chart.png) ![[a](images/near-funded/chart.png) %sb%s](https://x/hidden/srcset=/qr/x.png#)\n' "$tick" "$tick" >> "$im/props/near-funded.md"
jq -n '{"images/near-funded/chart.png": "near-funded/chart.png", "images/../secret.png": "../secret.png",
    "images/x/y.png": "near-funded/chart.png", "images/a\"b/c.png": "a\"b/c.png"}' > "$im/data/images.json"
if run "$here/fixtures/original" "$im/data" "$im/props" "$im/site" 2> "$im/log"; then
    page=$im/site/proposals/near-funded.html
    if grep -qF '<img src="../images/near-funded/chart.png" alt="a chart" loading="lazy">' "$page" \
        && grep -qF '<a href="https://elsewhere.example/x.png">image: other</a>' "$page" \
        && ! grep -q 'src="[^"]*secret' "$page" && ! grep -q 'src="[^"]*images/x/' "$page" \
        && [[ $(cd "$im/site/images" && echo */*) == near-funded/chart.png ]] && [[ ! -e $im/site/secret.png ]] \
        && grep -qF '<img src="../images/near-funded/chart.png" alt="https://x/onerror=alert(1)//" loading="lazy">' "$page" \
        && ! grep -qE 'alt="[^"]*<' "$page" && ! grep -qE '<img[^>]*srcset=/qr' "$page" \
        && [[ $(date -r "$im/site/images/near-funded/chart.png" +%s) == 1700000000 ]]; then
        ok "images: a proposal's own copied image shows from the site (relative, with its time), others stay links, bad entries ignored"
    else
        grep -oE '<img[^>]*>|<a href="[^"]*">image[^<]*</a>|image: [a-z]+[^<]*' "$page"; (cd "$im/site/images" 2> /dev/null && echo */*); fail "images"
    fi
else
    cat "$im/log"; fail "images: the run"
fi
rm -rf "$im"

# The footer's onion line. With CCS_ONION, every page shows it. Without, the region is empty.
# A bad onion address stops the run.
# An older original with no onion part still runs, with no line.
on=$(mktemp -d)
cp -r "$here/fixtures/original" "$on/original"
find "$on/original" -name '*.html' -exec grep -l '</footer>' {} + | while IFS= read -r f; do
    sed -i 's#</footer>#<!-- ccs:onion -->\n<!-- /ccs:onion -->\n</footer>#' "$f"
done
printf '%s\n' '<p class="footer-onion">Also on Tor: <a href="http://{{onion}}/">{{onion}}</a></p>' > "$on/original/parts/onion.html"
o=abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion
pages() { find "$1" -name '*.html' ! -path '*/parts/*' -exec grep -l '</footer>' {} + | wc -l; }
if CCS_ONION=$o run "$on/original" "$here/fixtures/data" "$props" "$on/site" 2> "$on/log" \
    && n=$(pages "$on/site") && ((n > 3)) \
    && [[ $(find "$on/site" -name '*.html' -exec grep -l "Also on Tor: <a href=\"http://$o/\">$o</a>" {} + | wc -l) == "$n" ]] \
    && [[ -n $(find "$on/site/proposals" -name '*.html' -exec grep -l "$o" {} + | head -n 1) ]]; then
    ok "CCS_ONION: the footer's onion line on every page ($n, proposal and tag pages too)"
else cat "$on/log"; fail "the onion line"; fi
if run "$on/original" "$here/fixtures/data" "$props" "$on/site2" 2> /dev/null && ! grep -rq 'Also on Tor' "$on/site2" \
    && grep -q '<!-- ccs:onion -->' "$on/site2/index.html"; then
    ok "no CCS_ONION: the onion region empty"
else fail "no onion"; fi
if ! CCS_ONION=evil.example run "$on/original" "$here/fixtures/data" "$props" "$on/site3" 2> "$on/log3" \
    && grep -q 'CCS_ONION is not an onion address' "$on/log3" && [[ ! -e $on/site3 ]]; then
    ok "CCS_ONION that isn't an onion address: the run stops, no site"
else fail "a bad CCS_ONION"; fi
if CCS_ONION=$o run "$here/fixtures/original" "$here/fixtures/data" "$props" "$on/site4" 2> /dev/null && ! grep -rq 'Also on Tor' "$on/site4"; then
    ok "CCS_ONION with an original from before the onion line: runs, no line"
else fail "an old original with CCS_ONION"; fi
rm -rf "$on"

# A Funding Required proposal at its goal shows "Fully funded", with no address or QR code.
# The others keep the donation box. A design without that part shows the box for all.
ff=$(mktemp -d); cp -r "$here/fixtures/original" "$ff/original"; mkdir "$ff/data"; cp "$here/fixtures/data"/*.json "$ff/data/"
printf '%s\n' '<p class="funded-badge">Fully funded: {{raised}} of {{amount}} XMR</p>' > "$ff/original/parts/donate-funded.html"
jq 'map(.proposals |= map(if ."local-url" == "/proposals/near-funded.html" then .percentage = 100 else . end))' "$here/fixtures/data/proposals.json" > "$ff/data/proposals.json"
a=$(jq -r '.[1].proposals[] | select(."local-url" == "/proposals/near-funded.html") | ."donate-address"' "$ff/data/proposals.json")
b=$(jq -r '.[1].proposals[] | select(."local-url" == "/proposals/a-fund.html") | ."donate-address"' "$ff/data/proposals.json")
if run "$ff/original" "$ff/data" "$props" "$ff/site" 2> "$ff/log" \
    && grep -q 'class="funded-badge">Fully funded: ' "$ff/site/proposals/near-funded.html" && ! grep -q "$a" "$ff/site/proposals/near-funded.html" \
    && ! grep -q 'data:image/png' "$ff/site/proposals/near-funded.html" \
    && grep -q "$b" "$ff/site/proposals/a-fund.html" && ! grep -q 'funded-badge' "$ff/site/proposals/a-fund.html"; then
    ok "fully funded: \"Fully funded\" in place of the donation box (no address, no QR code); the others keep theirs"
else cat "$ff/log"; fail "fully funded"; fi
rm "$ff/original/parts/donate-funded.html"
if run "$ff/original" "$ff/data" "$props" "$ff/site2" 2> /dev/null && grep -q "$a" "$ff/site2/proposals/near-funded.html"; then
    ok "fully funded, a design without donate-funded: the donation box as before"
else fail "fully funded with an older design"; fi
rm -rf "$ff"

# The feed. With CCS_SITE_URL it must match tests/expected/feed.xml. Without, there is none.
# A bad site address stops the run.
# Only the 10 newest ideas with a created-at are in it, each linking to its MR.
# Left out: ideas with no created-at, the 11th newest, and one whose link isn't https.
fd=$(mktemp -d); mkdir "$fd/data"; cp "$here/fixtures/data"/*.json "$fd/data/"
# shellcheck disable=SC2016
dates='def at($u; $k; $v): if ."local-url" == $u then .[$k] = $v else . end;
  map(.proposals |= map(at("/proposals/near-funded.html"; "funding-required-at"; "2026-10-01T10:00:00Z")
    | at("/proposals/a-fund.html"; "funding-required-at"; "2026-10-02T00:00:00Z") | at("/proposals/a-fund.html"; "funded-at"; "2026-10-03T12:30:00Z")
    | at("/proposals/b-wip.html"; "funded-at"; "2026-09-01T00:00:00Z") | at("/proposals/ leading-space.html"; "funding-required-at"; "2026-10-04T08:00:05Z")
    | at("/proposals/dots-end.html"; "funding-required-at"; "2026-01-01T00:00:00Z")))'
for f in proposals completed-proposals; do jq "$dates" "$here/fixtures/data/$f.json" > "$fd/data/$f.json"; done
# shellcheck disable=SC2016
ideas='.[0].proposals += [range(11) as $i | {name: "Idea \($i) &amp; more", "gitlab-url": "https://example.org/mr/\(100 + $i)",
    author: "erin", date: "October 5, 2026", tags: [], upvotes: 0, downvotes: 0,
    "created-at": "2026-10-05T\(if $i < 10 then "0" else "" end)\($i):00:00Z"}]
  + [{name: "Not https", "gitlab-url": "javascript:alert(1)", author: "x", date: "October 5, 2026", tags: [],
    upvotes: 0, downvotes: 0, "created-at": "2026-10-05T23:00:00Z"}]'
jq "$ideas" "$fd/data/proposals.json" > "$fd/ideas.json" && mv "$fd/ideas.json" "$fd/data/proposals.json"
if CCS_SITE_URL=https://ccs.example.org/ run "$here/fixtures/original" "$fd/data" "$props" "$fd/site" 2> "$fd/log" \
    && diff -u "$here/expected/feed.xml" "$fd/site/feed.xml"; then
    ok "CCS_SITE_URL: feed.xml, Funding Required, fully funded and the 10 newest ideas, newest first (expected/feed.xml)"
else cat "$fd/log"; fail "the feed"; fi
if run "$here/fixtures/original" "$fd/data" "$props" "$fd/site2" 2> /dev/null && [[ ! -e $fd/site2/feed.xml ]]; then
    ok "no CCS_SITE_URL: no feed"
else fail "a feed without CCS_SITE_URL"; fi
if ! CCS_SITE_URL=https://ccs.example.org/x run "$here/fixtures/original" "$fd/data" "$props" "$fd/site3" 2> "$fd/log3" \
    && grep -q "CCS_SITE_URL is not a site's address" "$fd/log3" && [[ ! -e $fd/site3 ]]; then
    ok "CCS_SITE_URL with a path: the run stops, no site"
else fail "a bad CCS_SITE_URL"; fi

# The link card. With CCS_SITE_URL, og:image gets the site's address on every page.
# Without it, the design's path stays. A proposal page's card text comes from its slots.
cp -R "$here/fixtures/original" "$fd/card"
card='<meta property="og:image" content="/assets/card.abc.png">'
sed -i "s#^<title>.*#&\\n$card#" "$fd/card/index.html"
sed -i "s#^<title>.*#&\\n<meta property=\"og:description\" content=\"{{raised}} of {{amount}} XMR\">\\n$card#" "$fd/card/parts/proposal-fr.html"
want='<meta property="og:image" content="https://ccs.example.org/assets/card.abc.png">'
if CCS_SITE_URL=https://ccs.example.org/ run "$fd/card" "$fd/data" "$props" "$fd/site4" 2> "$fd/log4" \
    && grep -qxF "$want" "$fd/site4/index.html" && grep -qxF "$want" "$fd/site4/proposals/near-funded.html" \
    && grep -q '<meta property="og:description" content="[0-9.]* of [0-9.]* XMR">' "$fd/site4/proposals/near-funded.html" \
    && run "$fd/card" "$fd/data" "$props" "$fd/site5" 2> /dev/null && grep -qxF "$card" "$fd/site5/index.html"; then
    ok "the link card: og:image with CCS_SITE_URL's address, the design's path without it, a proposal's text from its slots"
else cat "$fd/log4"; fail "the link card"; fi
rm -rf "$fd"

exit "$status"
