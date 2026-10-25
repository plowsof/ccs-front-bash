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
`grep`, `sed`, `tar`, `find`, `xargs` and `qrencode` (and `unzip` for step 1): on Debian,
`apt install jq qrencode` on top of what ccs-bash needs. It makes the QR codes itself
(qrencode, PNG), from the addresses it has checked; ccs-bash's are not used.

## 1. The original

ccs-front-hugo's releases carry the site as a zip, built reproducibly (the same tag gives the same
zip on any machine; build it yourself from the tag with its `container/build.sh` to check). Take
the release you mean to ship, check its sha256 against the one in the release notes, and unpack
it here (`apt install unzip` if needed):

```
v=v0.1.0
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
useradd --system --no-create-home --shell /usr/sbin/nologin ccs-front   # if not there already
install -d -o ccs-front -g ccs-front -m 755 /var/lib/ccs/www
```

`/usr/local/bin/ccs-front-run`, one run (`chmod 755`, then try it), as ccs-bash has
`ccs-bash-run`. **A)** on the host:

```
#!/bin/sh
exec runuser -u ccs-front -- /opt/ccs-front-bash/ccs-front-bash.sh \
    /opt/ccs-front-hugo/public /var/lib/ccs/out /var/lib/ccs/proposals /var/lib/ccs/www/site
```

**B)** from the pinned image (StageX parts only, no network, the same image ID from the same
commit anywhere): the `docker run` line in [the pinned image](image.md), after `exec`.

It writes `site.new` next to `site`, and only swaps it in once every page is made. Anything
off (a marker, a value ccs-bash didn't escape, a proposal file missing) stops the run, logs why,
and leaves the last good site as it was.

## 3. In ccs-bash-update

`ccs-bash-update` runs `ccs-front-run` right after `ccs-bash-run`, then pushes the site. The
script, the only full copy: [ccs-bash's handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md#9-the-update).

## 4. Serving it

**Same machine:** nginx's root is the site. With Docker, mount its parent: each run puts a new
`site` folder in place, and a bind mount of `site` itself would keep showing the first one.

```
root /var/lib/ccs/www/site;           # with Docker: mount /var/lib/ccs/www, root …/www/site
server_tokens off;
include snippets/ccs-headers.conf;    # the security headers: ccs-bash's docs/two-machines.md, way A
location = /projects {
    alias /var/lib/ccs/out/projects.json;
    default_type application/json;
}
```

For the header's Light / Dark / System button (kept in the address, no cookies, no JavaScript),
add the theme lines from ccs-bash's docs/two-machines.md ("The theme"), with
`/var/lib/ccs/www/site/` in place of `/var/lib/ccs-data/`.

**Two machines** (recommended): the site is pushed to a web server that only serves it, as
ccs-bash's docs/two-machines.md, way A, describes (its nginx, the gate, the alerts). The site
carries `projects.json`, so that one push is all the web server gets. Its key can't delete, so a
renamed proposal's old page stays until removed by hand.

The headers above were checked with the built site: styles, fonts, icons and QR codes all load.

## 5. The signed subaddress list (optional, recommended)

With it, no donation address can go on the site unless it is one of the wallet's: whatever
changes ccs-bash's JSON, the push or the web server can't slip in another address without the
run stopping (or, on the web server, without anyone being able to tell). It checks the address
text and its `monero:` link, and the QR code is made here from the checked address.

A **Core Team member** makes the list on an offline machine with the script below, then signs it
as described further down (`tools/sign-subaddresses.sh`). The script asks for the wallet's main
address and private view key, which are public. 15,000 subaddresses take about a minute, enough
for decades of proposals:

```
tools/make-subaddresses.sh /path/to/monero-wallet-rpc 15000 subaddresses.txt   # --testnet for testnet
```

Contributors can confirm it independently: run the same script with the same address and view
key, then compare `sha256sum subaddresses.txt` with the published list's.

**Check it before signing**: it must be this wallet's. Its first line is the main address, and
the subaddresses the wallet has already made are its first lines (here with the wallet's
wallet-rpc; `address all` in monero-wallet-cli shows the same):

```
head -n 1 subaddresses.txt                         # 0 <the main address, WALLET_ADDRESS>
curl -s --digest -u user:pass http://127.0.0.1:18082/json_rpc \
    -d '{"jsonrpc":"2.0","id":0,"method":"get_address","params":{"account_index":0}}' \
    | jq -r '.result.addresses | sort_by(.address_index)[] | "\(.address_index) \(.address)"' > made.txt
head -n "$(wc -l < made.txt)" subaddresses.txt | cmp - made.txt && echo "the wallet's own"
```

Then sign it, a standard detached signature (`subaddresses.txt.asc`, ASCII armour):

```
tools/sign-subaddresses.sh subaddresses.txt
```

It makes a PGP key only for this, signs the list, and destroys the secret key. Beside the list
it leaves the three files that go with it: `subaddresses.txt.asc` (the signature),
`subaddresses.txt.key.asc` (the public key) and `subaddresses.txt.pin` (the list's sha256 and
the key's fingerprint). Publish the fingerprint somewhere besides the site too (ccs-front-hugo's
README), so people can check the key doesn't come only from the site it vouches for.

Copy the four files to `/etc/ccs-front/` (root-owned, 644) and give the list to ccs-front-bash as
a fifth argument, in `ccs-front-run` (step 2): **A)** add `/etc/ccs-front/subaddresses.txt` after
the four. **B)** mount the folder and name the list after the image (the five arguments replace
the default four):

```
    -v /etc/ccs-front:/subaddresses:ro \
    ccs-front-bash /original /data /proposals /www/site /subaddresses/subaddresses.txt
```

With them, `subaddresses.txt.viewkey` (root-owned, 644): the wallet's view key on its first line,
and optionally a line `source <https link>` to where the address and view key were published,
and `source-text <words>` for what that link says (default "where they were published"). For the
mainnet CCS wallet that is luigi1111's comment in monero-project/meta #935:

```
62ad19781466882d8df0ae85743abcc5c8ef81e52e051e7cc56fe3c610d18001
source https://github.com/monero-project/meta/issues/935#issuecomment-1867257410
source-text shared by luigi1111 here
```

The Verify page
shows them, with the commands to ask a copy of the wallet whether an address is one of its own
(`get_address_index`).

Each run then checks the list against its `.pin` and every donation address against the list
(about 0.2s); a missing file, a list that isn't the one the pin names, or an address not in it
stops the run. It publishes the list, its signature and the key (`/subaddresses.txt`, `.asc`,
`.key.asc`), fills the site's `/verify/` page with the steps and the fingerprint, and puts a link
to it in every donation box. Without the fifth argument there is no check, and `/verify/` says
there is no list yet. Nothing about the list is in the original: a new list is the four files,
copied here and (with two machines) to the web server for its gate (ccs-bash's
docs/two-machines.md, "The gate"), which then holds back any page with an address not on it
and tells IRC. When the wallet nears the end of the list (index 15,000), make a longer one the same
way: its first lines are the old list, line for line (`head -n 15000 new | cmp - old`), which
anyone can check. A shorter one, the same: cut it with `head`, then sign it (the old signature
covers the whole old file, and its key is gone).

## Going back

During the move from Jekyll: [ccs-bash's handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md#10-the-cutover),
step 10. Nothing here changes ccs-bash, its data or the proposals checkout.
