# Renders one region from ccs-bash's JSON and the original's parts: the list of one stage.
# Inputs: --arg stage (idea, fr, wip, cp); --slurpfile proposals, completed (ccs-bash's files);
# --rawfile card, empty, done, todo (parts/card-<stage>.html, empty.html, segment-*.html).

# Amounts are ccs-bash's (exact to 4 decimals, cut off), shown without trailing zeros.
def trim0: tostring | if test("\\.") then sub("0+$"; "") | sub("\\.$"; "") else . end;

# ccs-bash already HTML-escapes every text it writes (names, authors, links): one that is not
# escaped means something upstream went wrong, so stop rather than escape it twice or not at all.
def escaped: if test("[<>\"']") then error("not HTML-escaped: \(.)") else . end;

# A proposal -> the values of its card's {{slots}}.
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
    pending_note: (if (."amount-pending" // 0) > 0 then " · \(."amount-pending" | trim0) XMR pending" else "" end),
    funding_note: (if ."funding-required-date" then " · funding since \(."funding-required-date")" else "" end)
  }
  | map_values(tostring | escaped);

# Fill a part's {{slots}} from $v in one pass; a slot with no value stops the run.
def fill($v): gsub("\\{\\{(?<k>[a-z_]+)\\}\\}"; $v[.k] // error("no value for {{\(.k)}}"));

def segments: (. as $v | [range(0; $v.milestones | tonumber) | if . < ($v.done | tonumber) then $done else $todo end] | map(rtrimstr("\n")) | join(""));

def stage_list:
  {idea: $proposals[0][0], fr: $proposals[0][1], wip: $proposals[0][2], cp: $completed[0][0]}[$stage].proposals;

stage_list
| if length == 0 then $empty | rtrimstr("\n")
  else map((values | . + {segments: segments}) as $v | $card | rtrimstr("\n") | fill($v)) | join("\n")
  end
