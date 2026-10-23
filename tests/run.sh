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
if grep -q '<a class="qr" href="monero:8[0-9]*"><img src="data:image/png;base64,' "$tmp/site/proposals/near-funded.html"; then
    ok "a funding page has its QR code (ccs-bash's PNG)"
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
if grep -q "<a class=\"filter $repurposed\" href=\"/explore/tag/repurposed/\">Repurposed" "$tmp/site/funding-required/index.html" \
    && grep -q "<a class=\"filter $repurposed\" href=\"/explore/tag/repurposed/\">Repurposed" "$tmp/site/proposals/b-wip.html" \
    && grep -q "<a class=\"filter $repurposed active\" href=\"/explore/tag/repurposed/\">Repurposed<span class=\"count\">1" "$tmp/site/explore/tag/repurposed/index.html" \
    && grep -q "<span class=\"label $repurposed\">Repurposed</span>" "$tmp/site/completed-proposals/index.html"; then
    ok "the tags in every page's sidebar, the shown one active on its page; a tag has one colour everywhere"
else
    fail "filters"
fi
# a tag page is three folders down: every link to the assets (the cards' icons too) goes three up
if grep -q 'href="../../../assets/icons[.0-9a-f]*svg#user' "$tmp/site/explore/tag/repurposed/index.html" \
    && ! grep -q '"\.\./assets/\|"\.\./\.\./assets/' "$tmp/site/explore/tag/repurposed/index.html"; then
    ok "a tag page's cards link their icons from three folders down"
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

# a pinned subaddress list: every donation address must be in it, and it goes out with the site
mkdir -p "$tmp/sub"
jq -r '.[1].proposals[] | ."donate-address" // empty' "$here/fixtures/data/proposals.json" | awk '{ print NR, $0 }' > "$tmp/sub/list.txt"
echo signature > "$tmp/sub/list.txt.asc"
cp -r "$here/fixtures/original" "$tmp/pinned"
sha256sum < "$tmp/sub/list.txt" | cut -d' ' -f1 > "$tmp/pinned/parts/subaddresses.sha256"
if "$run" "$tmp/pinned" "$here/fixtures/data" "$props" "$tmp/site4" "$tmp/sub/list.txt" 2> /dev/null \
    && cmp -s "$tmp/sub/list.txt" "$tmp/site4/subaddresses.txt" && [[ -f $tmp/site4/subaddresses.txt.asc ]]; then
    ok "every donation address in the pinned list: the list and its signature are published"
else
    fail "a pinned list"
fi
if [[ ! -e $tmp/site/subaddresses.txt ]]; then ok "no pin, no list published"; else fail "a list published without a pin"; fi
cp "$tmp/pinned/parts/subaddresses.sha256" "$tmp/sub/pin"
sed -i '2d' "$tmp/sub/list.txt"
sha256sum < "$tmp/sub/list.txt" | cut -d' ' -f1 > "$tmp/pinned/parts/subaddresses.sha256"
must_stop "an address not in the (pinned) list" "$tmp/pinned" "$here/fixtures/data" "$tmp/sub/list.txt"
cp "$tmp/sub/pin" "$tmp/pinned/parts/subaddresses.sha256"
must_stop "a list that isn't the pinned one" "$tmp/pinned" "$here/fixtures/data" "$tmp/sub/list.txt"
must_stop "a pin but no list" "$tmp/pinned" "$here/fixtures/data"

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

# The Markdown renderer: hostile text stays text, links only https/#/site-relative, and the
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
    || $body == *'href="data'* || $body == *'<!-- ccs'* || $body != *'x999y'* ]]; then
    echo "$body"; fail "hostile Markdown got through"
elif [[ $body == *'<a href="https://getmonero.org/">ok</a>'* && $body == *'<a href="https://example.org/p.png">image: pic</a>'* && $body == *'&nbsp; &#8212; &amp;lt;'* ]]; then
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

exit "$status"
