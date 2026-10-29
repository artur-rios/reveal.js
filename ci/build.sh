#!/usr/bin/env bash
# The `build` check: test.yml's `build` job, which ran on Node 22 and on Node 24 (a matrix). Each version installs,
# builds and runs the tests, in the same order and from a clean node_modules. yggdrasil.yml runs it in the pinned
# Node 24 image from the repository's root; Node 22 is fetched below. Both versions run even if the first fails, and
# the check fails if either did.
#
# The tests drive Chrome (puppeteer, `npm test`). The runner had the shared libraries Chrome needs; the image does
# not, so they are installed by ci/apt-packages.sh when this runs as root, as checks do on the agents.
#
# setup-node installed Node; the image is Node 24, and Node 22 is fetched from nodejs.org, pinned by version and by
# checksum (its SHASUMS256.txt) and unpacked into a directory of its own. Renovate follows the version (the comment
# above it), not the checksums: when it moves the version, copy the two linux-*.tar.gz lines of
# https://nodejs.org/dist/v<version>/SHASUMS256.txt into this file by hand. The matrix is Node 22 and 24: the 22
# line stays 22 (renovate.json blocks its major moves).
set -euo pipefail

# The repository's root, wherever this is run from.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# shellcheck source=ci/apt-packages.sh
. ci/apt-packages.sh

# renovate: datasource=node-version depName=node
NODE22_VERSION=22.23.4

ensure_packages \
  libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 libatspi2.0-0 libdbus-1-3 libcups2 libxkbcommon0 \
  libasound2 libgbm1 libxcomposite1 libxdamage1 libxfixes3 libxrandr2

# Fetches Node 22 and prints the directory of its bin/.
fetch_node22() {
  local arch sha256 directory archive home
  case $(uname -m) in
    x86_64)
      arch=x64
      sha256=b8492284c76a54baf58d61668dd0e41ee0fc98adabf9503d30f05d08f55b4406 ;;
    aarch64)
      arch=arm64
      sha256=f7a1e486dbc8b286847815b477d4fb5e9fb963ed4489c3e1588853d685f589f9 ;;
    *)
      echo "ci/build.sh: no pinned Node $NODE22_VERSION build for $(uname -m)" >&2
      return 1 ;;
  esac
  directory=$(mktemp -d)
  archive="$directory/node.tar.gz"
  curl --fail --silent --show-error --location --retry 3 -o "$archive" \
    "https://nodejs.org/dist/v${NODE22_VERSION}/node-v${NODE22_VERSION}-linux-${arch}.tar.gz" \
    || { rm -rf "$directory"; return 1; }
  if ! echo "$sha256  $archive" | sha256sum --check --strict --status; then
    echo "ci/build.sh: the Node archive does not match its pinned checksum" >&2
    rm -rf "$directory"
    return 1
  fi
  home=$(mktemp -d)
  tar -xzf "$archive" -C "$home" --strip-components=1 --no-same-owner
  rm -rf "$directory"
  printf '%s/bin' "$home"
}

# Fails unless the node on the PATH is the given major.
expect_node_major() {
  local major
  major=$(node -p 'process.versions.node.split(".")[0]')
  if [ "$major" != "$1" ]; then
    echo "ci/build.sh: expected Node $1 on the PATH, found $major" >&2
    return 1
  fi
}

# The steps of one matrix leg, with the node and npm on the PATH.
build_and_test() {
  echo "ci/build.sh: Node $(node --version), npm $(npm --version)"
  # Each leg starts from a clean install, as a separate job did.
  # (&&, not set -e: the leg runs in a `||` list below, where set -e is off.)
  rm -rf node_modules     && npm install     && npm run build --if-present     && CI=true npm test
}

status=0
for leg in 24 22; do
  echo "ci/build.sh: ==== Node $leg ===="
  if [ "$leg" = 22 ]; then
    node22=$(fetch_node22) || { status=1; continue; }
    # fetch_node22 runs in $(...) in a `||` list, where set -e does not apply: whatever it left must really be Node 22
    # before the leg counts, or the leg would silently run on the image's Node 24.
    ( PATH="$node22:$PATH"; expect_node_major 22 && build_and_test ) || status=1
    rm -rf "$(dirname "$node22")"
  else
    expect_node_major 24 && build_and_test || status=1
  fi
done
exit "$status"
