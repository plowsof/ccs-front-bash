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
(qrencode, PNG), from the addresses it has checked; ccs-bash makes none.

## 1. The original

ccs-front-hugo's releases carry the site as a zip, built reproducibly (the same tag gives the same
zip on any machine; build it yourself from the tag with its `container/build.sh` to check). Take
the release you mean to ship, check its sha256 against the one in the release notes, and unpack
it here (`apt install unzip` if needed):

```
v=v0.1.20                                 # ccs-bash's handover, "The releases"
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

## 5. The signed subaddress list (optional, recommended)

With it, only the wallet's addresses reach the site: one ccs-bash's JSON gets wrong is left off,
and the web server's gate and visitors check against the same list.

A **Core Team member** makes it on an offline machine and signs it **with their own key**, as the
Monero repository publishes it ([utils/gpg_keys/](https://github.com/monero-project/monero/tree/master/utils/gpg_keys)):
for the mainnet, binaryFate (`81AC 591F E9C4 B65C 5806  AFC3 F0AF 4D46 2A0B DF92`) or luigi1111
(`8777 AB8F 778E E894 87A2  F8E7 F4AC A018 3641 E010`). The script asks for the wallet's main
address and view key (both public); 15,000 subaddresses take about a minute:

```
tools/make-subaddresses.sh /path/to/monero-wallet-rpc 15000 subaddresses.txt   # --testnet for testnet
```

**Check it before signing**: line 0 is the main address, and the subaddresses the wallet has
already made are its first lines:

```
head -n 1 subaddresses.txt                         # 0 <the main address, WALLET_ADDRESS>
curl -s --digest -u user:pass http://127.0.0.1:18082/json_rpc \
    -d '{"jsonrpc":"2.0","id":0,"method":"get_address","params":{"account_index":0}}' \
    | jq -r '.result.addresses | sort_by(.address_index)[] | "\(.address_index) \(.address)"' > made.txt
head -n "$(wc -l < made.txt)" subaddresses.txt | cmp - made.txt && echo "the wallet's own"
```

Then sign it (a detached signature, from the signer's own keyring):

```
SIGNING_KEY=<the signer's fingerprint> tools/sign-subaddresses.sh subaddresses.txt
```

It writes `subaddresses.txt.asc` (the signature), `.key.asc` (the public key) and `.pin` (the
list's sha256 and the key's fingerprint). Without `SIGNING_KEY` it signs with a key made for this
and destroyed after (the testnet's): that binds the file, not a person.

**Publish and reproduce it:** the signer posts its sha256 and fingerprint where the address and
view key were published (mainnet: monero-project/meta #935); two contributors make it themselves
from the same public data and post the same sha256.

**Check it before installing it**, with your own file of the keys that may sign it (root-owned,
644; fingerprints as `gpg --show-keys binaryfate.asc` shows Monero's copies):

```
cat > /etc/ccs-front/list-signers <<'SIGNERS'
81AC591FE9C4B65C5806AFC3F0AF4D462A0BDF92  # binaryFate (monero-project/monero utils/gpg_keys)
8777AB8F778EE89487A2F8E7F4ACA0183641E010  # luigi1111 (monero-project/monero utils/gpg_keys)
SIGNERS
tools/verify-subaddresses.sh subaddresses.txt /etc/ccs-front/list-signers <WALLET_ADDRESS>
```

OK means: the list is its `.pin`'s, signed by a key in `list-signers`, its lines 0, 1, 2…, line 0
`WALLET_ADDRESS`. Compare its sha256 with the published ones. It can't know the key was revoked
since (it only has the list's copy): check Monero's, fetched fresh:

```
curl -fsSO https://raw.githubusercontent.com/monero-project/monero/master/utils/gpg_keys/luigi1111.asc   # or binaryfate.asc
gpg --show-keys --with-colons luigi1111.asc | awk -F: '$1 == "pub" { print ($2 == "r" ? "REVOKED" : "not revoked") }'
```

A revoked key: don't install the list, and ask the Core Team for one signed again.

Copy the four files to `/etc/ccs-front/` (root, 644) and pass the list as a fifth argument in
`ccs-front-run`: **A)** `/etc/ccs-front/subaddresses.txt` after the four; **B)** mount the folder,
and all five after the image:

```
    -v /etc/ccs-front:/subaddresses:ro \
    --pull never sha256:<image ID> /original /data /proposals /www/site /subaddresses/subaddresses.txt
```

Beside them `subaddresses.txt.viewkey` (root, 644): the view key, and optionally `source <https
link>` (where it was published) and `source-text <words>` (the link's words). For the mainnet:

```
62ad19781466882d8df0ae85743abcc5c8ef81e52e051e7cc56fe3c610d18001
source https://github.com/monero-project/meta/issues/935#issuecomment-1867257410
source-text shared by luigi1111 here
```

The Verify page shows them, with the commands to ask a copy of the wallet about an address.

Each run checks the list against its `.pin` (a missing file or another list stops the run) and
every address on the site against the list: a funding-required proposal, or a `/projects` entry,
whose address isn't on it is left off (`warning: left off the site: …`), the rest is made, and the
run exits 3. `/verify/`, linked from each donation box, shows the wallet's address and view key for visitors to check an address in a
view-only copy of the wallet; without the fifth argument, no check, and `/verify/` says so. The same four files, and `.viewkey`, go to the web server's gate (ccs-bash's two-machines, "The gate"), checked there too.
Near index 15,000, make a longer list the same way: its first lines are the old one
(`head -n 15000 new | cmp - old`).

## Going back

During the move from Jekyll: [ccs-bash's handover](https://github.com/plowsof/ccs-bash/blob/master/docs/handover.md#10-the-cutover),
step 10. Nothing here changes ccs-bash, its data or the proposals checkout.
