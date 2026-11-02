# Setup

ccs-front-bash's own steps. The whole CCS (the order across the three repositories, and the
update script that runs them all) starts at [ccs-bash's handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md).

ccs-front-bash runs on the ccs-bash machine, right after ccs-bash, and replaces the Jekyll build.
It reads three things and writes one:

| | Path here | What |
|---|---|---|
| the original | `/opt/ccs-front-hugo/public` | ccs-front-hugo's built site, from its release zip |
| the data | `/var/lib/ccs/out` | ccs-bash's `OUTPUT_DIR` |
| the proposals | `/var/lib/ccs/proposals` | the checkout ccs-bash reads |
| the site | `/var/lib/ccs/www/site` | written each run, swapped in when complete (with ccs-bash's `projects.json`, for `/projects`) |

Needs `bash`, `jq` (1.6 or newer), `awk` (mawk, gawk or busybox), coreutils (`base64` too),
`grep`, `sed`, `tar`, `find` and `xargs` (and `unzip` for step 1): on Debian, `apt install jq`
on top of what ccs-bash needs. (qrencode only where the list is made and checked, step 5:
`make-qr.sh` and `verify-subaddresses.sh`.) The QR codes are files,
`qr/<address>.png`: the signed list's own (step 5), copied for the addresses it has checked.
ccs-bash makes none, and neither does this.

## 1. The original

ccs-front-hugo's releases carry the site as a zip, built reproducibly (the same tag gives the same
zip on any machine; build it yourself from the tag with its `container/build.sh` to check). Take
the release you mean to ship, check its sha256 against the one in the release notes, and unpack
it here (`apt install unzip` if needed):

```
v=v0.1.29                                 # ccs-bash's handover, "The releases"
curl -fLO https://github.com/plowsof/ccs-front-hugo/releases/download/$v/ccs-front-hugo-$v.zip
sha256sum ccs-front-hugo-$v.zip           # must be the release's sha256 (and your own build's)
rm -rf /opt/ccs-front-hugo/public && install -d -m 755 /opt/ccs-front-hugo/public
unzip -q ccs-front-hugo-$v.zip -d /opt/ccs-front-hugo/public
```

It stays owned by root: ccs-front-bash only reads it. A new design is a new release, unpacked
the same way; the next run uses it.

## 2. ccs-front-bash

```
git clone https://github.com/plowsof/ccs-front-bash /opt/ccs-front-bash
git -C /opt/ccs-front-bash checkout <commit>   # the one ccs-bash's contrib/release/verify prints for the release you run: not the tag, which can move; not master
useradd --system --no-create-home --shell /usr/sbin/nologin ccs-front   # if not there already
install -d -o ccs-front -g ccs-front -m 755 /var/lib/ccs/www
```

`/usr/local/bin/ccs-front-run`, one run (`chmod 755`, then try it), as ccs-bash has
`ccs-bash-run`. **A)** on the host:

```
#!/bin/sh
exec env CCS_SITE_URL=https://ccs.getmonero.org runuser -u ccs-front -- /opt/ccs-front-bash/ccs-front-bash.sh \
    /opt/ccs-front-hugo/public /var/lib/ccs/out /var/lib/ccs/proposals /var/lib/ccs/www/site \
    /etc/ccs-front/subaddresses.txt
```

**B)** from the pinned image (StageX parts only, no network, the same image ID from the same
commit anywhere): the `docker run` line in [the pinned image](image.md), after `exec`, with
`-e CCS_SITE_URL=https://ccs.getmonero.org`.

`CCS_SITE_URL`, the site's address (`https://host`): the feed's links (`feed.xml`; without it, no
feed), the same as the web server gate's `SITE_URL`. `CCS_ONION`, optional, the site's onion
address (`<56 characters>.onion`): the footer's onion line, the same as the gate's
`/etc/ccs-gate/onion` (ccs-bash's handover, "The onion address"). In ccs-bash's Docker setup the
compose's `front` passes both from its `.env`.

It writes `site.new` next to `site`, and only swaps it in once every page is made. Anything
off (a marker, a value ccs-bash didn't escape, a proposal file missing) stops the run, logs why,
and leaves the last good site as it was.

## 3. In the update

In ccs-bash's Docker setup (the production one) the compose's `front` stage runs it, after
ccs-bash and the backup, before the push ([ccs-bash's docker.md](https://github.com/plowsof/ccs-bash/blob/master/docs/docker.md)).
The host setup's `ccs-bash-update` runs `ccs-front-run` right after `ccs-bash-run`, then pushes
the site; the script, the only full copy: [ccs-bash's setup](https://github.com/plowsof/ccs-bash/blob/master/docs/setup.md#the-update-script-the-host-setup).

## 4. Serving it

**Same machine:** nginx's root is the site. With Docker, mount its parent: each run puts a new
`site` folder in place, and a bind mount of `site` itself would keep showing the first one.

```
root /var/lib/ccs/www/site;           # with Docker: mount /var/lib/ccs/www, root …/www/site
server_tokens off;
include snippets/ccs-headers.conf;    # the security headers: ccs-bash's docs/two-machines.md
location = /projects {
    alias /var/lib/ccs/out/projects.json;
    default_type application/json;
}
```

For the header's Light / Dark / System button (kept in the address, no cookies, no JavaScript),
add the theme lines from ccs-bash's docs/two-machines.md ("The theme"), with
`/var/lib/ccs/www/site/` in place of `/var/lib/ccs-data/`.

**Two machines** (recommended): the site is pushed to a web server that only serves it, as
ccs-bash's docs/two-machines.md describes (its nginx, the gate, the alerts). The site
carries `projects.json`, so that one push is all the web server gets. Its key can't delete, so a
renamed proposal's old page stays until removed by hand.

The headers above were checked with the built site: styles, fonts, icons and QR codes all load.

## 5. The signed subaddress list (required)

Only the wallet's addresses reach the site: one ccs-bash's JSON gets wrong is left off, and each
address's QR code is the list's own file. Without the list a run stops. Making it (with
`tools/make-subaddresses.sh` and `make-qr.sh`), signing it (`sign-subaddresses.sh`), checking it
(`verify-subaddresses.sh`) and installing it on both machines:
[the signed list](https://github.com/plowsof/ccs-bash/blob/master/docs/signed-list.md), in
ccs-bash's docs.

Here, it is the fifth argument: in `/etc/ccs-front/` (the list, its `.asc`, `.key.asc`, `.pin`,
`.viewkey`, `.qr.sha256` and the folder `.qr/`), `ccs-front-run` passes
`/etc/ccs-front/subaddresses.txt` after the four (step 2); from the image, mount the folder and
name it:

```
    -v /etc/ccs-front:/subaddresses:ro \
    --pull never sha256:<image ID> /original /data /proposals /www/site /subaddresses/subaddresses.txt
```

Each run checks the list and its QR sums against the `.pin` (another list stops the run), and
every address the site would show against the list: a funding-required proposal, or a `/projects`
entry, whose address isn't on it is left off (`warning: left off the site: …`), the rest is made,
and the run exits 3. `/verify/`, linked from each donation box, shows the wallet's address and
view key (`subaddresses.txt.viewkey`) for visitors to check an address in a view-only copy of the
wallet.

## Going back

During the move from Jekyll: [ccs-bash's handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md#10-the-cutover),
step 10. Nothing here changes ccs-bash, its data or the proposals checkout.
