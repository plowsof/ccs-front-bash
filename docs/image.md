# The pinned image

The same as [ccs-bash's](https://github.com/plowsof/ccs-bash/blob/master/docs/image.md), with
less in it (about 14 MB): ccs-front-bash needs no network.

- **[StageX](https://stagex.tools) packages**, pinned by digest in `container/images`: bash, jq,
  musl, ncurses (bash's), libpng and zlib (qrencode's). Two or more StageX maintainers reproduce
  and sign each release, and every build checks those signatures (`container/verify-images.sh`, `container/stagex-keys.asc`),
  from the copy in `container/sigs/`, so a build needs nothing from StageX's signature site.
- **busybox and qrencode, built here** from upstream source pinned by sha256 in
  `container/sources.lock` (StageX's sums): busybox with only the applets in
  `container/busybox-applets` (what ccs-front-bash and its tests run, no shell, no network
  tools); qrencode with PNG output, the same version and options as ccs-bash's, for the QR codes.
- **Built by StageX's BuildKit**, pinned and checked like the rest, with `--network none`; every
  file gets the commit's time. The same commit builds to the same image ID anywhere, and
  `container/check-pinned.sh` proves it on every push (two clean builds from separate clones and
  one on another commit's cache must agree).

```
container/build.sh            # needs Docker with buildx, git, gpg, jq; prints the image ID
```

It runs as a numeric user (default 10002), reads three folders and writes one:

```
docker run --rm --network none --read-only --user "$(id -u ccs-front):$(id -g ccs-front)" \
    -v /opt/ccs-front-hugo/public:/original:ro -v /var/lib/ccs/out:/data:ro \
    -v /var/lib/ccs/proposals:/proposals:ro -v /var/lib/ccs/www:/www \
    ghcr.io/plowsof/ccs-front-bash@sha256:…          # writes /www/site
```

With a [signed subaddress list](setup.md#5-the-signed-subaddress-list-optional-recommended), mount
it too and name it: `-v /etc/ccs-front:/subaddresses:ro … /original /data /proposals /www/site
/subaddresses/subaddresses.txt` (the arguments after the image replace the default four).

## Changing the pin, releases

As in ccs-bash: `container/update-images.sh` repins to StageX's current release, stores the
signatures in `container/sigs/` and checks them (review the diff); `container/update-keys.sh` refreshes the maintainers' keys. Push a
tag `vX.Y.Z` on `master` and the `release` workflow builds, tests, runs `check-pinned.sh`, pushes
`ghcr.io/plowsof/ccs-front-bash:vX.Y.Z` and puts the pull-by-digest line and the image ID in the
release notes.
