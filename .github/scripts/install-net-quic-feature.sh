#!/bin/sh
# Feature-branch-only CI pin. Do not put this experimental dependency in a
# CPAN release until coordinated versioning/release has been approved.
set -eu
revision=be0ceecbaa88a6d8100459642a018b8eefba8e56
directory="$(mktemp -d)"
trap 'rm -rf "$directory"' EXIT
git -C "$directory" init -q
git -C "$directory" fetch --quiet --depth 1 \
    https://github.com/haxmeister/perl-Net-QUIC.git "$revision"
git -C "$directory" checkout --quiet --detach FETCH_HEAD
cpanm --notest --reinstall "$directory"
