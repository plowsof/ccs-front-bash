#!/usr/bin/env bash
# check-pinned.sh
# Fails unless three builds give the same hash: two clean builds from separate clones,
# and one on a cache left by another commit.
# check-pinned.sh clean UMASK | warm: run one build alone and print "id: <image id>".
# CI runs warm under umask 077 on a second machine.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
repo=$(git -C "$here" rev-parse --show-toplevel)
name=$(basename "$repo")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; docker image rm -f "$name:other" "$name:warm" "$name:repro1" "$name:repro2" > /dev/null 2>&1 || true' EXIT

"$here/fetch.sh" "$tmp/sources"                # once, so every build gets the same files

# clean N UMASK: build with no cache, from a fresh clone made under UMASK. Prints the image ID.
clean() {
    (umask "$2" && git clone -q "$repo" "$tmp/clone$1")
    cp -r "$tmp/sources" "$tmp/clone$1/container/sources"
    NO_CACHE=1 "$tmp/clone$1/container/build.sh" "$name:repro$1" > /dev/null 2>&1
    docker image inspect "$name:repro$1" --format '{{.Id}}'
}
# warm: build an older commit, then this one on its cache. Prints the image ID.
warm() {
    local c
    for c in other warm; do
        git clone -q "$repo" "$tmp/$c"
        cp -r "$tmp/sources" "$tmp/$c/container/sources"
    done
    GIT_COMMITTER_DATE="@$(($(git -C "$repo" log -1 --format=%ct) - 86400)) +0000" \
        git -C "$tmp/other" -c user.name=check -c user.email=check@invalid commit -q --allow-empty -m other
    "$tmp/other/container/build.sh" "$name:other" > /dev/null 2>&1
    "$tmp/warm/container/build.sh" "$name:warm" > /dev/null 2>&1
    docker image inspect "$name:warm" --format '{{.Id}}'
}

case ${1:-} in
    clean) echo "id: $(clean 1 "${2:?UMASK}")"; exit ;;
    warm) echo "id: $(warm)"; exit ;;
    "") ;;
    *) echo "usage: check-pinned.sh [clean UMASK | warm]" >&2; exit 1 ;;
esac

declare -A id
id[warm]=$(warm)
echo "build with a cache from another commit: ${id[warm]}"
for i in 1 2; do
    id[$i]=$(clean "$i" "$([[ $i == 1 ]] && echo 022 || echo 077)")
    echo "build $i: ${id[$i]}"
    sleep 2
done
if [[ ${id[1]} != "${id[2]}" ]]; then
    echo "error: the image hash is not pinned, the two builds differ" >&2
    exit 1
fi
if [[ ${id[warm]} != "${id[1]}" ]]; then
    echo "error: a build cache from another commit changes the image hash" >&2
    exit 1
fi
echo "pinned: commit $(git -C "$repo" rev-parse --short HEAD) builds to ${id[1]}"
