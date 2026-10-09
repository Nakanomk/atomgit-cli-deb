#!/bin/bash
# Rebuild the local Debian binary package without root or host installation.
set -euo pipefail
umask 022
export LC_ALL=C TZ=UTC
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GO=${GO:-go}
if [[ "$GO" == */* ]]; then GO=$(realpath -- "$GO"); fi
EXPECTED_GO=go1.26.8
ACTUAL_GO=$("$GO" version | awk '{print $3}')
[[ "$ACTUAL_GO" == "$EXPECTED_GO" ]] || {
  echo "Use Go 1.26.8: set GO=/path/to/go1.26.8/bin/go" >&2
  exit 1
}
export SOURCE_DATE_EPOCH=1791461444
VERSION=0.7.4
DEB_VERSION=0.7.4-1~local1
COMMIT=1b9de43514ff4f0588b06fdd4cff930fe74ce5f0
BUILD_DATE=2026-10-08T12:10:44Z
export GOOS=linux GOARCH=amd64 GOAMD64=v1 CGO_ENABLED=0
export GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOFLAGS=-mod=vendor
OUTPUT=${1:-"$ROOT/output"}
mkdir -p -- "$OUTPUT"
OUTPUT=$(cd -- "$OUTPUT" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/atomgit-cli-deb.XXXXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache"
export GOCACHE=${GOCACHE:-"$WORK/go-cache"} GOPATH="$WORK/gopath"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$GOCACHE" "$GOPATH"
unset AG_TOKEN ATOMGIT_TOKEN GITCODE_TOKEN GITHUB_TOKEN GH_TOKEN
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
(cd "$ROOT" && sha256sum --quiet -c source.sha256)
cd "$ROOT/src"
"$GO" test ./...
"$GO" vet ./...
"$GO" fix -diff ./... >"$WORK/fix.diff"
test ! -s "$WORK/fix.diff"
STAGE="$WORK/package"
install -d "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/share/doc/atomgit-cli" "$STAGE/usr/share/man/man1"
LDFLAGS="-s -w -buildid= -X atomgit.com/hust-open-atom-club/atomgit-cli/internal/version.Version=v$VERSION -X atomgit.com/hust-open-atom-club/atomgit-cli/internal/version.Commit=$COMMIT -X atomgit.com/hust-open-atom-club/atomgit-cli/internal/version.BuildDate=$BUILD_DATE"
"$GO" build -trimpath -buildvcs=false -ldflags "$LDFLAGS" -o "$STAGE/usr/bin/ag-cli" ./cmd/ag-cli
if readelf -l "$STAGE/usr/bin/ag-cli" | grep -q INTERP || readelf -d "$STAGE/usr/bin/ag-cli" | grep -q NEEDED; then
  echo 'Expected a fully static ELF; inspect dependencies before packaging.' >&2
  exit 1
fi
"$GO" run -trimpath -buildvcs=false ./scripts/generate-manpages --output "$STAGE/usr/share/man/man1" --version "v$VERSION" --date 2026-10-08
"$GO" run -trimpath -buildvcs=false ./scripts/generate-manpages --output "$STAGE/usr/share/man/man1" --version "v$VERSION" --date 2026-10-08 --check
find "$STAGE/usr/share/man/man1" -type f -name '*.1' -exec gzip -n -9 {} +
DOC="$STAGE/usr/share/doc/atomgit-cli"
install -m 0644 LICENSE "$DOC/copyright"
install -m 0644 "$ROOT/packaging/README.Debian" "$DOC/README.Debian"
gzip -n -9 -c CHANGELOG.md >"$DOC/changelog.gz"
gzip -n -9 -c "$ROOT/packaging/changelog" >"$DOC/changelog.Debian.gz"
install -d "$DOC/licenses"
install -m 0644 "$ROOT/packaging/Go-LICENSE" "$ROOT/packaging/Go-PATENTS" "$DOC/licenses/"
cp -r "$ROOT/packaging/go-vendor-licenses" "$DOC/licenses/"
while IFS= read -r -d '' license; do
  relative=${license#vendor/}
  install -D -m 0644 "$license" "$DOC/licenses/$relative"
done < <(find vendor -type f \( -iname 'license*' -o -iname 'notice*' -o -iname 'copying*' -o -iname 'copyright*' -o -iname 'patents*' \) -print0)
"$GO" version -m "$STAGE/usr/bin/ag-cli" | sed '1s|.*: |ag-cli: |' >"$DOC/build-info.txt"
INSTALLED_SIZE=$(du -sk "$STAGE/usr" | cut -f1)
cat >"$STAGE/DEBIAN/control" <<EOF
Package: atomgit-cli
Version: $DEB_VERSION
Section: devel
Priority: optional
Architecture: amd64
Maintainer: Nakanomk <56832666+Nakanomk@users.noreply.github.com>
Installed-Size: $INSTALLED_SIZE
Depends: ca-certificates
Recommends: git
Suggests: xdg-utils
Homepage: https://atomgit.com/hust-open-atom-club/atomgit-cli
Description: command-line interface for AtomGit
 Manage AtomGit repositories, issues, pull requests, releases and workflows.
 This local, unofficial Debian package installs the ag-cli executable and
 Unix manuals. Built from unmodified upstream v0.7.4 source using static Go.
EOF
find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f -exec chmod 0644 {} +
chmod 0755 "$STAGE/usr/bin/ag-cli"
(cd "$STAGE" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
PACKAGE="$OUTPUT/atomgit-cli_${DEB_VERSION}_amd64.deb"
dpkg-deb --root-owner-group --uniform-compression --threads-max=1 -Zxz -z9 --build "$STAGE" "$PACKAGE"
dpkg-deb --info "$PACKAGE"
"$STAGE/usr/bin/ag-cli" version --json
"$STAGE/usr/bin/ag-cli" --help >/dev/null
"$STAGE/usr/bin/ag-cli" schema pr create >/dev/null
(cd "$OUTPUT" && sha256sum "$(basename "$PACKAGE")" >SHA256SUMS)
echo "Built: $PACKAGE"
