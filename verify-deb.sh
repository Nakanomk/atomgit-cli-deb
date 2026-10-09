#!/bin/bash
# Verify the actual .deb payload without installing it on the host.
set -euo pipefail
export LC_ALL=C TZ=UTC
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=packaging/upstream.env
source "$ROOT/packaging/upstream.env"
[[ $# == 1 ]] || { echo "Usage: bash verify-deb.sh PACKAGE.deb" >&2; exit 2; }
PACKAGE=$(realpath -- "$1")
DEB_VERSION=$(dpkg-parsechangelog -l "$ROOT/packaging/changelog" -S Version)
MAINTAINER=$(dpkg-parsechangelog -l "$ROOT/packaging/changelog" -S Maintainer)
[[ "$(dpkg-deb -f "$PACKAGE" Package)" == atomgit-cli ]]
[[ "$(dpkg-deb -f "$PACKAGE" Version)" == "$DEB_VERSION" ]]
[[ "$(dpkg-deb -f "$PACKAGE" Architecture)" == amd64 ]]
[[ "$(dpkg-deb -f "$PACKAGE" Maintainer)" == "$MAINTAINER" ]]
[[ "$(dpkg-deb -f "$PACKAGE" Depends)" == ca-certificates ]]
WORK=$(mktemp -d "${TMPDIR:-/tmp}/atomgit-cli-verify.XXXXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
dpkg-deb --raw-extract "$PACKAGE" "$WORK/package"
(cd "$WORK/package" && md5sum --quiet -c DEBIAN/md5sums)
BINARY="$WORK/package/usr/bin/ag-cli"
test -x "$BINARY"
test ! -e "$WORK/package/usr/bin/ag"
for script in preinst postinst prerm postrm; do
  test ! -e "$WORK/package/DEBIAN/$script"
done
if readelf -l "$BINARY" | grep -F INTERP >/dev/null || readelf -d "$BINARY" | grep -F NEEDED >/dev/null; then
  echo 'Expected a fully static ELF.' >&2
  exit 1
fi
DOC="$WORK/package/usr/share/doc/atomgit-cli"
test -s "$DOC/copyright"
test -s "$DOC/licenses/Go-LICENSE"
test -s "$DOC/build-info.txt"
gzip -t "$DOC/changelog.gz" "$DOC/changelog.Debian.gz"
MAN="$WORK/package/usr/share/man/man1"
test -s "$MAN/ag-cli.1.gz"
test -s "$MAN/ag-cli-pr-create.1.gz"
# xargs propagates gzip failures; find -exec by itself does not.
find "$MAN" -type f -name '*.1.gz' -print0 | xargs -0 -r gzip -t
export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
unset AG_TOKEN ATOMGIT_TOKEN GITCODE_TOKEN GITHUB_TOKEN GH_TOKEN
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
cd "$WORK"
"$BINARY" version --json | tee "$WORK/version.json"
jq -e --arg version "v$VERSION" --arg commit "$COMMIT" --arg date "$BUILD_DATE" \
  '.version == $version and .commit == $commit and .buildDate == $date' "$WORK/version.json" >/dev/null
"$BINARY" --help >/dev/null
"$BINARY" --version >/dev/null
"$BINARY" schema pr create >"$WORK/schema.json"
jq -e '.formatVersion == 1 and .command.path == "ag-cli pr create" and .command.runnable == true' "$WORK/schema.json" >/dev/null
"$BINARY" api /user --dry-run >"$WORK/dry-run.json"
jq -e '.dryRun == true and .executed == false and .method == "GET" and .path == "/user"' "$WORK/dry-run.json" >/dev/null
status=0
"$BINARY" not-a-real-command >"$WORK/invalid.out" 2>&1 || status=$?
[[ "$status" == 1 ]]
test -z "$(find "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" -type f -print -quit)"
echo "Verified: $PACKAGE ($DEB_VERSION, static amd64, credential-free smoke checks)"
