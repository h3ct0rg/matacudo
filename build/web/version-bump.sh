#!/bin/sh
# Gives the web build cache-busting file names, so a browser can never mix a new
# index.html with files cached from a previous release.
#
#   ./version-bump.sh 1.0.6 [web-root]
#
# All four files the engine loads are renamed to index-<version>.*:
#
#   index-<version>.js     the loader
#   index-<version>.wasm   the engine
#   index-<version>.pck    the game (scenes, sprites, sound)
#   index-<version>.audio.worklet.js, .audio.position.worklet.js   audio worklets
#
# The engine builds every one of those names from a single base name, taken from
# `executable` in the config the HTML embeds, and it derives the .pck name from
# that base rather than from the fileSizes table (verified: renaming only the
# table made it request index.pck and fail). The worklets follow the base name
# too (verified: they 404'd as index-1.0.6.audio.worklet.js until renamed). So
# versioning the game package forces the whole set to be versioned, which is the
# honest trade: a new release is a new URL for everything, and nothing stale can
# ever be served.
#
# The cost is that the engine binary is fetched again on each release, which is
# why the Dockerfile also stores a pre-compressed copy (index-<version>.wasm.gz)
# for nginx to serve with gzip_static: the transfer is around a quarter of the
# 39 MB, without spending CPU per request.
set -eu

VERSION="${1:?falta la version, por ejemplo: ./version-bump.sh 1.0.6}"
ROOT="${2:-.}"

if [ ! -f "$ROOT/index.html" ]; then
    echo "version-bump: no encuentro $ROOT/index.html" >&2
    exit 1
fi
for required in index.js index.pck index.wasm; do
    if [ ! -f "$ROOT/$required" ]; then
        echo "version-bump: falta $required en $ROOT" >&2
        exit 1
    fi
done

# Guard against a double run on an already renamed build.
if [ -f "$ROOT/index-$VERSION.js" ]; then
    echo "version-bump: index-$VERSION.js ya existe, no hay nada que hacer"
    exit 0
fi

mv "$ROOT/index.js" "$ROOT/index-$VERSION.js"
mv "$ROOT/index.pck" "$ROOT/index-$VERSION.pck"
mv "$ROOT/index.wasm" "$ROOT/index-$VERSION.wasm"

# The audio worklets are optional files, so they are renamed only if present.
for worklet in index.audio.worklet.js index.audio.position.worklet.js; do
    if [ -f "$ROOT/$worklet" ]; then
        mv "$ROOT/$worklet" "$ROOT/index-$VERSION.${worklet#index.}"
    fi
done

# The names live inside the config the shell embeds: `executable` is the base
# name the engine fetches from, and fileSizes is the progress table, which must
# list the new key or the loading bar reports the wrong total.
sed -i \
    -e "s|\"executable\":\"index\"|\"executable\":\"index-$VERSION\"|g" \
    -e "s|index\\.pck|index-$VERSION.pck|g" \
    -e "s|index\\.wasm|index-$VERSION.wasm|g" \
    -e "s|src=\"index\\.js\"|src=\"index-$VERSION.js\"|g" \
    "$ROOT/index.html"

# Fail loudly instead of deploying a build that references files that are gone.
for expected in "index-$VERSION.js" "index-$VERSION.pck" "index-$VERSION.wasm" "executable\":\"index-$VERSION"; do
    if ! grep -q "$expected" "$ROOT/index.html"; then
        echo "version-bump: no pude reescribir index.html (falta $expected)" >&2
        exit 1
    fi
done

echo "version-bump: listo, la build pide index-$VERSION.js, .wasm y .pck"
