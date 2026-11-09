# The ccs-front-bash image.
# StageX images come in from build.sh as named contexts. The steps have no network.
# It needs no network to run either: it only reads files and writes the site.
# The same commit gives the same hash: every file gets the commit's time,
# and the result is one layer. No user account: it runs as a numeric user.

# busybox with only the applets in busybox-applets.
# The toolchain's cc is clang.
FROM toolchain AS busybox
COPY --from=bash / /
COPY --from=ncurses / /
# No build time or date in the binary.
ENV KCONFIG_NOTIMESTAMP=1
RUN --mount=type=bind,source=container,target=/pin \
    bash /pin/verify.sh /pin/sources.lock /pin/sources \
    && tar -xjf /pin/sources/busybox-1.38.0.tar.bz2 -C / \
    && cd /busybox-1.38.0 \
    && make HOSTCC=cc CC=cc allnoconfig > /dev/null \
    && for applet in $(grep -v '^#' /pin/busybox-applets); do \
        config=CONFIG_$(echo "$applet" | tr 'a-z-' 'A-Z_'); \
        grep -q "^# $config is not set$" .config || { echo "no applet $applet" >&2; exit 1; }; \
        sed -i "s/^# $config is not set$/$config=y/" .config; \
        sed -i "s/^# \(CONFIG_FEATURE_${config#CONFIG_}_[A-Z0-9_]*\) is not set$/\1=y/" .config; \
    done \
    && sed -i "s/^# CONFIG_LONG_OPTS is not set$/CONFIG_LONG_OPTS=y/" .config \
    && yes "" | make HOSTCC=cc CC=cc oldconfig > /dev/null \
    && make HOSTCC=cc CC=cc > /dev/null \
    && install -D -m 755 busybox /rootfs/usr/bin/busybox \
    && for applet in $(grep -v '^#' /pin/busybox-applets); do \
        ln -s busybox "/rootfs/usr/bin/$applet"; \
        ! "/rootfs/usr/bin/$applet" --help 2>&1 | grep -q "applet not found" || { echo "$applet not built" >&2; exit 1; }; \
    done

# Only what ccs-front-bash runs: bash, jq and busybox.
# No qrencode: the QR codes are the signed list's files.
FROM scratch AS tree
COPY --from=filesystem / /
COPY --from=musl / /
COPY --from=busybox /rootfs/ /
COPY --from=bash / /
COPY --from=ncurses / /
COPY --from=jq / /
COPY ccs-front-bash.sh /opt/ccs-front-bash/
COPY lib/ /opt/ccs-front-bash/lib/

# Drop headers, static libraries and manuals. Fix the file modes.
# Give every file the commit's time.
FROM toolchain AS fix
ARG SOURCE_DATE_EPOCH
COPY --from=tree / /rootfs/
RUN cd /rootfs \
    && rm -rf usr/include usr/lib/pkgconfig usr/lib/*.a usr/lib/*.la usr/share/man usr/share/doc usr/share/info \
    && chmod 755 opt/ccs-front-bash opt/ccs-front-bash/lib opt/ccs-front-bash/ccs-front-bash.sh \
    && chmod 644 opt/ccs-front-bash/lib/* \
    && find . -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

FROM scratch AS image
COPY --from=fix /rootfs/ /
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Only a default. The compose runs it as the host's ccs-front user.
USER 10002:10002
ENTRYPOINT ["/opt/ccs-front-bash/ccs-front-bash.sh"]
CMD ["/original", "/data", "/proposals", "/www/site", "/subaddresses/subaddresses.txt"]
