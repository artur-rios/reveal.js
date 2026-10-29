#!/usr/bin/env bash
# The `codespell` check: spellcheck.yml's `codespell` job ("Check for spelling errors"), which ran
# codespell-project/actions-codespell@v2 with the skip list below; .codespellrc (check-hidden, ignore-regex) is read by
# codespell itself, as it was there. yggdrasil.yml runs it in the pinned Python image from the repository's root.
#
# The action pip-installed the latest codespell. Here codespell is pinned: its source archive is fetched from PyPI,
# checked against the pinned sha256, and its pure-Python package put on PYTHONPATH (no pip, no write access to the
# image's site-packages). A codespell that is already importable is not looked for: the pinned one is the check.
#
# Renovate follows the version (the comment above it), not the checksum: when it moves the version, copy the sdist's
# sha256 from https://pypi.org/project/codespell/#files into this file by hand.
set -euo pipefail

# The repository's root, wherever this is run from.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# renovate: datasource=pypi depName=codespell
CODESPELL_VERSION=2.4.3
CODESPELL_SHA256=cbe085e331227b37bb86ef8bddd08dc768c704ee9a07ca869852c093fa2793e2

tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT

archive="$tools/codespell.tar.gz"
curl --fail --silent --show-error --location --retry 3 -o "$archive" \
  "https://files.pythonhosted.org/packages/source/c/codespell/codespell-${CODESPELL_VERSION}.tar.gz"
if ! echo "$CODESPELL_SHA256  $archive" | sha256sum --check --strict --status; then
  echo "ci/codespell.sh: the codespell archive does not match its pinned checksum" >&2
  exit 1
fi
tar -xzf "$archive" -C "$tools" --no-same-owner

export PYTHONPATH="$tools/codespell-${CODESPELL_VERSION}${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONDONTWRITEBYTECODE=1
python3 -m codespell_lib --version

# The workflow's skip input.
python3 -m codespell_lib --skip="./.git,./dist,package-lock.json,*.css,.codespellrc,./react/"
