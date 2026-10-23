# Shared by regions.jq (the lists) and pages.jq (proposal pages).

# Amounts are ccs-bash's (exact to 4 decimals, cut off), shown without trailing zeros.
def trim0: tostring | if test("\\.") then sub("0+$"; "") | sub("\\.$"; "") else . end;

# ccs-bash already HTML-escapes every text it writes (names, authors, links): one that is not
# escaped means something upstream went wrong, so stop rather than escape it twice or not at all.
def escaped: if test("[<>\"']") then error("not HTML-escaped: \(.)") else . end;

# A proposal from ccs-bash's JSON -> the values of its {{slots}}.
def values:
  {
    url: (."local-url" // ."gitlab-url" // "#"),
    gitlab_url: (."gitlab-url" // "#"),
    name: .name,
    author: .author,
    date: (.date // ""),
    contributors: (.contributions // 0),
    amount: ((.amount // "0") | trim0),
    raised: ((."amount-funded" // "0") | trim0),
    percentage: (.percentage // 0),
    milestones: (.milestones // 0),
    done: (."milestones-completed" // 0),
    address: (."donate-address" // ""),
    pending_note: (if (."amount-pending" // 0) > 0 then " · \(."amount-pending" | trim0) XMR pending" else "" end),
    funding_note: (if ."funding-required-date" then " · funding since \(."funding-required-date")" else "" end)
  }
  | map_values(tostring | escaped);

# Fill a part's {{slots}} from $v in one pass; a slot with no value stops the run.
def fill($v): gsub("\\{\\{(?<k>[a-z_]+)\\}\\}"; $v[.k] // error("no value for {{\(.k)}}"));

# The milestone bar of a card: one segment part per milestone.
def segments($done; $todo):
  . as $v | [range(0; $v.milestones | tonumber) | if . < ($v.done | tonumber) then $done else $todo end]
  | map(rtrimstr("\n")) | join("");

# A proposal's page file name: its local-url without /proposals/ and .html, and without the
# HTML escaping ccs-bash gave it. Checked: a plain name, no folders, nothing hidden.
def page_file:
  ."local-url" | ltrimstr("/proposals/") | rtrimstr(".html")
  | gsub("&#39;"; "'") | gsub("&quot;"; "\"") | gsub("&gt;"; ">") | gsub("&lt;"; "<") | gsub("&amp;"; "&")
  | if test("^[^/.][^/[:cntrl:]]*$") then . else error("bad page name: \(.)") end;

# The proposals that get a page (ideas link to GitLab), with their stage.
def paged($proposals; $completed):
  ($proposals[0][1].proposals[] | ["fr", .]), ($proposals[0][2].proposals[] | ["wip", .]), ($completed[0][0].proposals[] | ["cp", .]);
