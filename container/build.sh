#!/usr/bin/env bash
# build.sh [TAG]: build the ccs-front-bash image.
# Checks the pins' signatures, downloads the images and sources, sets up StageX's BuildKit,
# and builds with no network in the steps. NO_CACHE=1 rebuilds everything.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
tag=${1:-ccs-front-bash}

# Releases name images by their config digest, as Docker's own image store shows it.
# The containerd store (the default in a fresh Docker 29) shows another ID instead.
if docker info --format '{{json .DriverStatus}}' | grep -q 'io\.containerd\.snapshotter'; then
    echo 'error: Docker keeps images in its containerd store, where an image ID is not the attested one:' \
        'add "features": {"containerd-snapshotter": false} to /etc/docker/daemon.json, restart Docker, build again' >&2
    exit 1
fi
"$here/verify-images.sh"
contexts=()
while read -r name ref; do
    docker pull -q "$ref" > /dev/null
    contexts+=(--build-context "$name=docker-image://$ref")
done < <(grep -v '^#' "$here/images")
"$here/fetch.sh" "$here/sources"

# Only copies, so the host's BuildKit can make it.
# Named by its ID, so the three repositories share one builder and one cache.
docker buildx build -q --builder default --network none --pull=false "${contexts[@]}" \
    --build-arg SOURCE_DATE_EPOCH=0 --output type=docker,name=stagex-buildkit,rewrite-timestamp=true \
    -f "$here/builder.Dockerfile" "$here" > /dev/null
builder_id=$(docker image inspect stagex-buildkit --format '{{.Id}}')
builder=stagex-buildkit-${builder_id:7:12}
docker tag stagex-buildkit "$builder"
docker buildx inspect "$builder" > /dev/null 2>&1 \
    || docker buildx create --name "$builder" --driver docker-container --driver-opt image="$builder" > /dev/null

# Every file time in the image is the commit's.
# The last steps never come from the cache. Cache keys ignore file times,
# so another commit's result would bring its own times.
epoch=$(git -C "$here" log -1 --format=%ct)
cache=(--no-cache-filter fix --no-cache-filter image)
[[ ${NO_CACHE:-} ]] && cache=(--no-cache)   # buildx refuses both together
docker buildx build --builder "$builder" "${cache[@]}" --network none "${contexts[@]}" \
    --build-arg SOURCE_DATE_EPOCH="$epoch" \
    --output type=docker,name="$tag",rewrite-timestamp=true -f "$here/Dockerfile" "$here/.."
docker image inspect "$tag" --format "$tag {{.Id}}" >&2
