#!/usr/bin/env bash
# Tests: fill tests/fixtures/original (ccs-front-hugo's built pages) with tests/fixtures/data
# (ccs-bash's test JSON), compare with tests/expected, then everything that must stop a run.
# UPDATE=1 tests/run.sh rewrites tests/expected (check the diff!).
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
run=$here/../ccs-front-bash.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; status=1; }

"$run" "$here/fixtures/original" "$here/fixtures/data" "$tmp/site" 2> "$tmp/log" || { cat "$tmp/log"; fail "the run"; exit 1; }

pages=(explore/index.html ideas/index.html funding-required/index.html work-in-progress/index.html completed-proposals/index.html)
if [[ ${UPDATE:-} ]]; then
    for p in "${pages[@]}"; do install -D -m 644 "$tmp/site/$p" "$here/expected/$p"; done
fi
for p in "${pages[@]}"; do
    if diff -u "$here/expected/$p" "$tmp/site/$p" > "$tmp/diff"; then ok "$p"; else cat "$tmp/diff"; fail "$p"; fi
done

# every proposal in the JSON gets a card on its stage's page, and all of them on Explore
count() { grep -c 'class="card ' "$tmp/site/$1" || true; }
want() { jq "$2" "$here/fixtures/data/$1"; }
fr=$(want proposals.json '.[1].proposals | length') wip=$(want proposals.json '.[2].proposals | length')
idea=$(want proposals.json '.[0].proposals | length') cp=$(want completed-proposals.json '.[0].proposals | length')
if [[ $(count funding-required/index.html) == "$fr" && $(count work-in-progress/index.html) == "$wip" \
    && $(count ideas/index.html) == "$idea" && $(count completed-proposals/index.html) == "$cp" \
    && $(count explore/index.html) == $((fr + wip + idea + cp)) ]]; then
    ok "a card per proposal ($fr fr, $wip wip, $idea ideas, $cp completed)"
else
    fail "card counts"
fi
if [[ ! -e $tmp/site/parts && ! -e $tmp/site/proposals ]]; then ok "parts/ and proposals/ left out"; else fail "parts/ or proposals/ published"; fi

# ccs-bash's escaping is kept, once: no double escaping, nothing unescaped
if grep -q 'Fund &lt;b&gt;this&lt;/b&gt; &amp;amp; that\|Fund &amp;lt;' "$tmp/site/funding-required/index.html"; then
    fail "a name was escaped twice"
elif grep -q 'Fund &lt;b&gt;this&lt;/b&gt; &amp; that' "$tmp/site/funding-required/index.html"; then
    ok "names stay escaped exactly once"
else
    fail "escaped name not found"
fi

# Everything below must stop the run and leave the last site as it was.
echo previous > "$tmp/site/marker-of-the-old-site"
must_stop() {   # must_stop WHAT ORIGINAL DATA
    local what=$1
    if "$run" "$2" "$3" "$tmp/site" 2> "$tmp/log.stop"; then
        fail "$what: the run went on"
    elif [[ ! -e $tmp/site/marker-of-the-old-site || -e $tmp/site.new ]]; then
        fail "$what: the old site was touched"
    else
        ok "$what: stops ($(grep -o 'error: .*' "$tmp/log.stop" | cut -c8-70 || head -c 60 "$tmp/log.stop"))"
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

cp -r "$here/fixtures/original" "$tmp/slot"
sed -i 's#{{author}}#{{nonesuch}}#' "$tmp/slot/parts/card-fr.html"
must_stop "a slot with no value" "$tmp/slot" "$here/fixtures/data"

# one pass: a value that looks like a slot or a marker is text, never filled again
mkdir -p "$tmp/literal"
cp "$here/fixtures/data/completed-proposals.json" "$tmp/literal/"
jq '.[1].proposals[0].name = "{{author}} &lt;!-- ccs:list fr --&gt;"' "$here/fixtures/data/proposals.json" > "$tmp/literal/proposals.json"
"$run" "$here/fixtures/original" "$tmp/literal" "$tmp/site2" 2> /dev/null
if grep -q '<h3>{{author}} &lt;!-- ccs:list fr --&gt;</h3>' "$tmp/site2/funding-required/index.html"; then
    ok "a title with {{author}} or a marker in it stays text"
else
    fail "a title was filled again"
fi

exit "$status"
