# Setup

ccs-front-bash runs on the ccs-bash machine, right after ccs-bash, and replaces the Jekyll build.
It reads three things and writes one:

| | Path here | What |
|---|---|---|
| the original | `/opt/ccs-front-hugo/public` | ccs-front-hugo's built site, from the offline build machine |
| the data | `/var/lib/ccs/out` | ccs-bash's `OUTPUT_DIR` |
| the proposals | `/var/lib/ccs/proposals` | the checkout ccs-bash reads |
| the site | `/var/lib/ccs/www/site` | written each run, swapped in when complete |

Needs `bash`, `jq` (1.6 or newer), `awk` (mawk, gawk or busybox), `qrencode`, coreutils, `tar`
and `find`: on Debian, `apt install jq qrencode` on top of what ccs-bash needs.

## 1. The original

Build it on the offline machine (see ccs-front-hugo), never on this one:

```
hugo build --cleanDestinationDir          # in ccs-front-hugo, at the commit you mean to ship
tar -C public -c . | sha256sum            # note this
```

Copy it here and check it is what was built:

```
install -d -m 755 /opt/ccs-front-hugo/public
ssh build-machine 'tar -C ccs-front-hugo/public -c .' | tee >(sha256sum >&2) | tar -x -C /opt/ccs-front-hugo/public
```

The two sums must match. It stays owned by root: ccs-front-bash only reads it.

## 2. ccs-front-bash

```
git clone https://github.com/plowsof/ccs-front-bash /opt/ccs-front-bash
useradd --system --no-create-home --shell /usr/sbin/nologin ccs-front   # if not there already
install -d -o ccs-front -g ccs-front -m 755 /var/lib/ccs/www
runuser -u ccs-front -- /opt/ccs-front-bash/ccs-front-bash.sh \
    /opt/ccs-front-hugo/public /var/lib/ccs/out /var/lib/ccs/proposals /var/lib/ccs/www/site
```

It writes `site.new` next to `site`, and only swaps it in once every page is made. Anything
off (a marker, a value ccs-bash didn't escape, a proposal file missing) stops the run, logs why,
and leaves the last good site as it was.

## 3. In ccs-bash-update

Replace the Jekyll line of ccs-bash's `ccs-bash-update` (ccs-bash's docs/setup.md, step 6):

```
#!/bin/sh
# /usr/local/bin/ccs-bash-update (chmod 755)
timeout -k 5 40 runuser -u ccs-git -- env HOME=/ \
    git -C /var/lib/ccs/proposals pull -q --ff-only   # GitLab down: give up
ccs-bash-run >> /var/log/ccs-bash.log 2>&1
runuser -u ccs-front -- /opt/ccs-front-bash/ccs-front-bash.sh \
    /opt/ccs-front-hugo/public /var/lib/ccs/out /var/lib/ccs/proposals /var/lib/ccs/www/site \
    >> /var/log/ccs-bash.log 2>&1
```

## 4. Serving it

**Same machine:** nginx's root is the site. With Docker, mount its parent: each run puts a new
`site` folder in place, and a bind mount of `site` itself would keep showing the first one.

```
root /var/lib/ccs/www/site;           # with Docker: mount /var/lib/ccs/www, root …/www/site
add_header Content-Security-Policy "default-src 'none'; style-src 'self'; img-src 'self' data:; font-src 'self'" always;
location = /projects {
    alias /var/lib/ccs/out/projects.json;
    default_type application/json;
}
```

**Two machines:** push the site instead of the JSON, as in ccs-bash's docs/two-machines.md:
`rsync -a --delay-updates /var/lib/ccs/www/site/ ccs-data@<web server>:`. The web server's key
keeps `-no-del`, so nothing on it can be deleted from here; the cost is that a renamed
proposal's old page stays until removed by hand.

The CSP above was checked with the built site: styles, fonts, icons and QR codes all load.

## Going back

Point nginx back at the Jekyll site and restore the old `ccs-bash-update`. Nothing here
changes ccs-bash, its data or the proposals checkout.
