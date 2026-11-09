# The builder: StageX's BuildKit, so the build tool is pinned and signed too.
# Only COPY, so nothing runs while the host's Docker makes it.
FROM scratch
COPY --from=filesystem / /
COPY --from=musl / /
COPY --from=ca-certificates / /
COPY --from=libseccomp / /
COPY --from=runc / /
COPY --from=buildkit / /
# buildkitd needs root in its container.
USER 0:0
ENTRYPOINT ["/usr/bin/buildkitd"]
