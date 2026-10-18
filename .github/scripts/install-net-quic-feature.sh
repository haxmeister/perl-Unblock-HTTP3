#!/bin/sh
# Feature-branch-only CI pin. Do not put this experimental dependency in a
# CPAN release until coordinated versioning/release has been approved.
set -eu
revision=4d3a45aa2d3efb27523c6733c71d31cf527130a8
directory="$(mktemp -d)"
trap 'rm -rf "$directory"' EXIT
git -C "$directory" init -q
git -C "$directory" fetch --quiet --depth 1 \
    https://github.com/haxmeister/perl-Net-QUIC.git "$revision"
git -C "$directory" checkout --quiet --detach FETCH_HEAD
cpanm --notest --reinstall "$directory"
