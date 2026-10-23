# The list of one stage, from ccs-bash's JSON and the original's parts.
# Inputs: --arg stage (idea, fr, wip, cp); --slurpfile proposals, completed (ccs-bash's files);
# --rawfile card, empty, segdone, segtodo (parts/card-<stage>.html, empty.html, segment-*.html).
include "common";

{idea: $proposals[0][0], fr: $proposals[0][1], wip: $proposals[0][2], cp: $completed[0][0]}[$stage].proposals
| if length == 0 then $empty | rtrimstr("\n")
  else map((values | . + {segments: segments($segdone; $segtodo)}) as $v | $card | rtrimstr("\n") | fill($v)) | join("\n")
  end
