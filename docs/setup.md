# How it runs

ccs-front-bash is the site builder of the CCS backend: the backend compose's `front` stage runs
it, from this repository's attested image, after ccs-bash and the backup, before the push.
Setting it up and running it, with the rest of the CCS, is in ccs-bash's docs:
[preparing the machines](https://github.com/plowsof/ccs-bash/blob/master/docs/setup.md) (the
design, the `ccs-front` account, `/etc/ccs-front`), [the backend in
Docker](https://github.com/plowsof/ccs-bash/blob/master/docs/docker.md) and
[the handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md). This page is
what the stage is given and what it does with it.

## What it reads and writes

| Argument | In the compose | What |
|---|---|---|
| ORIGINAL | `/opt/ccs-front-hugo/public` | ccs-front-hugo's built site, from its attested release zip; read only |
| DATA | `/var/lib/ccs/out` | ccs-bash's `OUTPUT_DIR`: the JSON, `images.json` and `images/` |
| PROPOSALS | `/var/lib/ccs/proposals` | the proposals checkout ccs-bash reads |
| SITE | `/var/lib/ccs/www/site` | written each run, swapped in when complete (with ccs-bash's `projects.json`, for `/projects`) |
| SUBADDRESSES | `/etc/ccs-front/subaddresses.txt` | the signed list, with its QR codes ([below](#the-signed-list)) |

`CCS_SITE_URL`, the site's address (`https://host`): the feed's links (`feed.xml`; without it, no
feed), the same as the web server gate's `SITE_URL`. `CCS_ONION`, optional, the site's onion
address (`<56 characters>.onion`): the footer's onion line, the same as the gate's
`/etc/ccs-gate/onion` (ccs-bash's handover, "The onion address"). The compose's `front` passes
both from its `.env`.

It needs no network, and runs as its own user, read-only, with no capabilities
([the pinned image](image.md)). It writes `site.new` next to `site`, and only swaps it in once
every page is made. Anything off (a marker, a value ccs-bash didn't escape, a proposal file
missing) stops the run, logs why, and leaves the last good site as it was. The web server only
ever gets the site through the push and its gate (ccs-bash's
[two machines](https://github.com/plowsof/ccs-bash/blob/master/docs/two-machines.md)); the site
carries `projects.json`, so that one push is all it gets.

## The signed list

Only the wallet's addresses reach the site: one ccs-bash's JSON gets wrong is left off, and each
address's QR code is the list's own file. Without the list a run stops. Making it (with this
repository's `tools/make-subaddresses.sh` and `make-qr.sh`), signing it (`sign-subaddresses.sh`),
checking it (`verify-subaddresses.sh`) and installing it on both machines:
[the signed list](https://github.com/plowsof/ccs-bash/blob/master/docs/signed-list.md), in
ccs-bash's docs.

It is the fifth argument: in `/etc/ccs-front/` the list, its `.asc`, `.key.asc`, `.pin`,
`.viewkey`, `.qr.sha256` and the folder `.qr/`, mounted read-only. Each run checks the list and
its QR sums against the `.pin` (another list stops the run), and every address the site would
show against the list: a funding-required proposal, or a `/projects` entry, whose address isn't
on it is left off (`warning: left off the site: …`), the rest is made, and the run exits 3.
`/verify/`, linked from each donation box, shows the wallet's address and view key
(`subaddresses.txt.viewkey`) for visitors to check an address in a view-only copy of the wallet.

## Going back

During the move from Jekyll: [ccs-bash's handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md#10-the-cutover),
step 10. Nothing here changes ccs-bash, its data or the proposals checkout.
