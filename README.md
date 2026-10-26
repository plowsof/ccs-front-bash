<p align="center">
  <img src="logo.svg" width="180" alt="An orange clam seen from the side, eyes peeking out of its open shell, inside a gear">
</p>

# ccs-front-bash

[![check](https://github.com/plowsof/ccs-front-bash/actions/workflows/check.yml/badge.svg)](https://github.com/plowsof/ccs-front-bash/actions/workflows/check.yml) [![release](https://github.com/plowsof/ccs-front-bash/actions/workflows/release.yml/badge.svg)](https://github.com/plowsof/ccs-front-bash/actions/workflows/release.yml)

**A blazingly fast, memory-safe CCS frontend. Written in shell.**

- **Blazingly fast:** no build step at runtime, only string replacement.
- **Memory safe:** it has no memory. Every page starts again from the untouched original.
- **Fearless concurrency:** a fresh directory every run, then `rsync --delay-updates`.
- **Zero-cost abstractions:** there are no abstractions.
- **A strong type system:** everything is a string, the HTML too. That's how it stays escaped.
- **A friendly compiler:** `shellcheck`.
- **Cargo:** `apt install jq`. Or a pinned image of StageX parts, the same ID from the same commit ([docs](docs/image.md)).

Not a crustacean. A mollusc.

The front half of [ccs-bash](https://github.com/plowsof/ccs-bash): it turns ccs-bash's JSON and
the proposals' Markdown into the finished CCS website, on the backend, with bash, awk and jq.
No Jekyll, Node or any framework runs on a live machine; the public web server only receives
the finished files ([the design](https://github.com/plowsof/ccs-bash/blob/master/docs/design.md)).

**Status:** makes the whole site: the lists and every proposal page, with its donation box,
QR code, milestones and payouts. About 1.5 seconds for 316 proposals. Runs the testnet CCS since
2026-10-23, on two machines: made on the ccs-bash machine, pushed to a web server that only
serves it (https://ccs.monerodevs.org).

```
ccs-front-bash.sh ORIGINAL DATA PROPOSALS SITE
#   ORIGINAL   ccs-front-hugo's public/       DATA  ccs-bash's OUTPUT_DIR
#   PROPOSALS  the proposals checkout          SITE  the site to write (replaced when complete)
tests/run.sh   # UPDATE=1 rewrites tests/expected
```

To install it: [docs/setup.md](docs/setup.md); the whole CCS, all three repositories in order:
[ccs-bash's handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md).

Every piece of HTML comes from the original's pages and parts; this only fills them. The one
thing no template can do on a live machine is Markdown: `lib/markdown.awk` renders it (one awk
run for all proposals), `lib/pages.jq` fills every page (one jq run).

## What it does

1. **Copy the original:** the site [ccs-front-hugo](https://github.com/plowsof/ccs-front-hugo)
   builds once, offline, with markers where content goes. It is never modified.
2. **Proposal pages,** re-rendered only when a `.md` file changes: the proposal's Markdown
   into HTML (a strict subset in awk, everything escaped first), filled into
   `parts/proposal-<stage>.html`.
3. **Every run:** the Ideas, Funding Required, Work in Progress and Completed lists, and each
   proposal's donation box, with the address, from ccs-bash's JSON, checked against the signed
   list, and its QR code, made here from it (qrencode, a PNG): ccs-bash's own QR codes are never
   used, so what its account writes can't put another address in one.
   Tags (the front matter's `tags:`) as labels on cards and links on proposal pages, the
   filters on Explore, and a page per tag at `/explore/tag/<tag>/` (copies of the original's
   tag page, so still no JavaScript).
4. **Swap and push:** a missing, unmatched or repeated marker stops the run and no new site is
   made (the last good one is pushed again); otherwise the new `site/` replaces the last one and
   goes to the web server. A funding-required proposal whose address isn't on the signed list is
   left off, and the run exits 3.

The contract between the two (markers, parts, `{{slots}}`) is in
[ccs-front-hugo's README](https://github.com/plowsof/ccs-front-hugo#what-ccs-front-bash-fills-in).

## Rules

- Values are HTML-escaped exactly once; links must be `https:` (or local).
- Markers are replaced in one pass: text put into a page is never searched for markers again.
- The output keeps the original's rules: no `<script>`, no `style=`, nothing from other sites.
- A proposal's images are links, except its own: files in the proposals repository inside an images
  folder, `images/<proposal>/<file>`, that ccs-bash copied (its `images.json` and `images/`). Those
  show, copied into the site's `images/<proposal>/`.
- It needs no network: run it without any (it reads files, writes `site/`).
