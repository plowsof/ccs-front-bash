# Every proposal page, in one run: the original's parts/proposal-<stage>.html, its {{slots}}
# filled, then its regions (donation box or funding, milestones, payouts) filled with the
# original's parts. Prints each page after a line "\u0001<file name>" (see ccs-front-bash.sh).
# Inputs: --slurpfile proposals, completed (ccs-bash's JSON), md (markdown.awk's lines),
# qrs (qr.awk's lines); --rawfile fr, wip, cp (parts/proposal-*.html), donate, funded, mdone,
# mtodo, payout, nom, nop, segdone, segtodo (the other parts).
include "common";

def part: rtrimstr("\n");

# Replace what is between <!-- ccs:NAME --> and <!-- /ccs:NAME -->, each there exactly once.
# Runs after the slots are filled; what it puts in is not looked at again.
def region($name; $html):
  ("<!-- ccs:\($name) -->") as $a | ("<!-- /ccs:\($name) -->") as $b
  | split($a) as $x
  | if ($x | length) != 2 then error("<!-- ccs:\($name) --> \($x | length - 1) times") else . end
  | ($x[1] | split($b)) as $y
  | if ($y | length) != 2 then error("<!-- /ccs:\($name) --> \($y | length - 1) times") else . end
  | $x[0] + $a + "\n" + $html + "\n" + $b + $y[1];

($md | map({key: .file, value: .}) | from_entries) as $byfile
| ($qrs | map({key: .address, value: .svg}) | from_entries) as $qr
| {fr: $fr, wip: $wip, cp: $cp} as $tpl
| paged($proposals; $completed) | .[0] as $stage | .[1] as $p
| ($p | page_file) as $file
| ($byfile[$file] // error("no proposal file \($file).md")) as $m
# the front matter's milestones and payouts are the proposal's own text: escaped here
| ($m.milestones | map(map(@html) | {name: .[0], funds: .[1], date: .[2]})
   | map(. as $x | (if $x.date != "" then $mdone else $mtodo end) | part | fill($x)) | join("\n")) as $milestones
| ($m.payouts | map(map(@html) | {date: .[0], amount: .[1]})
   | map(. as $x | $payout | part | fill($x)) | join("\n")) as $payouts
| ($p | values) as $v0
| (if $stage == "fr" then ($qr[$v0.address] // error("\($file): no QR code for its address")) else "" end) as $svg
| ($v0 + {segments: ($v0 | segments($segdone; $segtodo)), body: $m.body, qr: $svg, milestones_list: "", payouts_list: ""}) as $v
| $tpl[$stage]
| fill($v)
| region(if $stage == "fr" then "donate" else "funded" end; (if $stage == "fr" then $donate else $funded end) | part | fill($v))
| region("milestones"; if $milestones == "" then $nom | part else $milestones end)
| region("payouts"; if $payouts == "" then $nop | part else $payouts end)
| "\u0001\($file)\n" + gsub("\u0001"; "")
