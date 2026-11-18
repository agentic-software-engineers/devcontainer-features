#!/usr/bin/env bash
# Tests for the shared install sequence: each case writes a small feature into a sandbox and runs
# it the way the dev container CLI runs a feature, with releases and checksums served from local
# files, and the releases' tags from local repos.
set -uo pipefail

LIB="$(cd "$(dirname "$0")" && pwd)/lib.sh"
passed=0
failed=0

# Remove every sandbox when the run ends.
SANDBOXES=()
trap 'rm -rf "${SANDBOXES[@]}"' EXIT

# Give a host's repo in the sandbox the named tags, each on a commit of its own.
tags() {
  local dir="$SANDBOX/git/$1/$2" tag
  shift 2
  git init -q "$dir"
  for tag in "$@"; do
    git -C "$dir" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m "$tag"
    git -C "$dir" tag "$tag"
  done
}

# Build a sandbox with a fake release, fake system tools and an empty install root.
sandbox() {
  SANDBOX="$(mktemp -d)"
  SANDBOXES+=("$SANDBOX")
  mkdir -p "$SANDBOX/bin" "$SANDBOX/feature" "$SANDBOX/root" "$SANDBOX/release/v1.2.3" \
    "$SANDBOX/pkg/tool-v1.2.3"
  # Package manager and machine name, recorded and faked.
  printf '#!/bin/sh\necho "$*" >> "%s/apt.log"\n' "$SANDBOX" > "$SANDBOX/bin/apt-get"
  printf '#!/bin/sh\necho "${FAKE_ARCH:-x86_64}"\n' > "$SANDBOX/bin/uname"
  # Switching user, recorded and run as the current user.
  printf '#!/bin/sh\necho "as $2: $4" >> "%s/su.log"\nexec bash -c "$4"\n' "$SANDBOX" > "$SANDBOX/bin/su"
  chmod +x "$SANDBOX/bin/apt-get" "$SANDBOX/bin/uname" "$SANDBOX/bin/su"
  # A release tarball holding one tool, its checksum list and its per-file checksum.
  printf '#!/bin/sh\necho "tool 1.2.3"\n' > "$SANDBOX/pkg/tool-v1.2.3/tool"
  chmod +x "$SANDBOX/pkg/tool-v1.2.3/tool"
  echo notes > "$SANDBOX/pkg/tool-v1.2.3/README.md"
  tar -czf "$SANDBOX/release/v1.2.3/tool-v1.2.3-linux-amd64.tar.gz" -C "$SANDBOX/pkg" tool-v1.2.3
  ( cd "$SANDBOX/release/v1.2.3" && sha256sum tool-v1.2.3-linux-amd64.tar.gz > checksums.txt \
    && cp checksums.txt tool-v1.2.3-linux-amd64.tar.gz.sha256 \
    && sha512sum tool-v1.2.3-linux-amd64.tar.gz > tool-v1.2.3-linux-amd64.tar.gz.sha512 )
  # The same tool as a zip archive with its own top folder, as some vendors ship it.
  python3 -I -c 'import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
i = zipfile.ZipInfo("tool-linux64/tool"); i.external_attr = 0o755 << 16
z.writestr(i, open(sys.argv[2]).read()); z.close()' \
    "$SANDBOX/release/v1.2.3/tool-linux64.zip" "$SANDBOX/pkg/tool-v1.2.3/tool"
  # The tool's tags: an older release, the newest one, and a pre-release beyond it.
  tags github.com example/tool v0.9.0 v1.2.3 v1.10.0-rc.1
  cp "$LIB" "$SANDBOX/feature/lib.sh"
}

# Write the feature's install script: the shared sequence, the standard declarations, then the body.
feature() {
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo '. "$(dirname "$0")/lib.sh"'
    echo 'FEATURE=tool'
    echo 'VERSION="$(option VERSION latest)"'
    cat
  } > "$SANDBOX/feature/install.sh"
}

# Run the feature like the CLI does, with the sandbox's tools and paths.
run() {
  env PATH="$SANDBOX/bin:$PATH" _FEATURE_TEST_ROOT="$SANDBOX/root" _FEATURE_TEST_GIT="$SANDBOX/git" \
    REL="file://$SANDBOX/release" "$@" bash "$SANDBOX/feature/install.sh" > "$SANDBOX/out" 2>&1
}

# Record one case: its name, and whether the check holds.
check() {
  local name="$1"; shift
  if "$@"; then passed=$((passed + 1)); echo "ok   $name"
  else failed=$((failed + 1)); echo "FAIL $name"; sed 's/^/     /' "$SANDBOX/out" 2>/dev/null; fi
}

has() { grep -qF -- "$1" "$SANDBOX/out"; }
installed() { [ -x "$SANDBOX/root/usr/local/bin/$1" ]; }

# The standard body: resolve from the release tags, verify by list, install the tool.
standard() {
  cat <<'EOF'
resolve_version() {
  tag="$(release_tag github example/tool "$VERSION")"
  url="$REL/$tag/tool-$tag-linux-$(arch_name x86_64=amd64 aarch64=arm64).tar.gz"
  checksums="$REL/$tag/checksums.txt"
}
install_program() { untar; install_bin "$tmp/tool"; }
EOF
}

# --- options and helpers ---------------------------------------------------------------

# option falls back to its default and reads a set value.
sandbox; feature <<<"$(standard); echo \"opt=\$(option COLOR blue) set=\$(option SHAPE round)\"; exit 0"

run SHAPE=square

check "option falls back to its default and reads a set value" has "opt=blue set=square"

# arch_name maps the machine name.
sandbox; feature <<<"$(standard); echo \"a=\$(arch_name x86_64=amd64 aarch64=arm64)\"; exit 0"

run FAKE_ARCH=aarch64

check "arch_name maps the machine name" has "a=arm64"

# arch_name stops on an unknown machine.
sandbox; feature <<<"$(standard); arch_name x86_64=amd64"

run FAKE_ARCH=riscv64

check "arch_name stops on an unknown machine" has "tool: unsupported architecture 'riscv64'"

# release_tag resolves latest, prefixes exact versions and keeps bare ones bare.
sandbox; feature <<<"$(standard); echo \"l=\$(release_tag github example/tool latest) e=\$(release_tag github example/tool 2.0.0) v=\$(release_tag github example/tool v2.0.0) b=\$(release_tag github example/tool 2.0.0 --bare) w=\$(release_tag github example/tool v2.0.0 --bare)\"; exit 0"

run

check "release_tag resolves latest, prefixes exact versions and keeps bare ones bare" has "l=v1.2.3 e=v2.0.0 v=v2.0.0 b=2.0.0 w=2.0.0"

# release_tag reads a Gitea host's tags.
sandbox; tags gitea.example example/tool v9.9.9
feature <<<"$(standard); echo \"g=\$(release_tag gitea.example example/tool latest)\"; exit 0"

run

check "release_tag reads a Gitea host's tags" has "g=v9.9.9"

# release_tag orders tags by version, not by text.
sandbox; tags github.com example/sorted v1.9.0 v1.10.0
feature <<<"$(standard); echo \"s=\$(release_tag github example/sorted latest)\"; exit 0"

run

check "release_tag orders tags by version, not by text" has "s=v1.10.0"

# A repo without release tags stops the resolve.
sandbox; tags github.com example/untagged
feature <<<"$(standard); release_tag github example/untagged latest"

run

check "a repo without release tags stops the resolve" has "tool: could not resolve the latest version"

# A missing repo stops the resolve.
sandbox; feature <<<"$(standard); release_tag github example/missing latest"

run

check "a missing repo stops the resolve" has "tool: could not resolve the latest version"

# --- release lines and tag prefixes -------------------------------------------------------

# release_tag resolves a major and a minor line to their newest release.
sandbox; tags github.com example/lines v1.2.0 v1.2.9 v1.9.0 v1.10.0 v1.3.0-rc.1 v2.0.0
feature <<<"$(standard); echo \"m=\$(release_tag github example/lines 1) n=\$(release_tag github example/lines 1.2) o=\$(release_tag github example/lines 2) b=\$(release_tag github example/lines 1.2 --bare)\"; exit 0"

run

check "release_tag resolves a major and a minor line to their newest release" has "m=v1.10.0 n=v1.2.9 o=v2.0.0 b=1.2.9"

# A line holding pre-releases alone stops the resolve.
sandbox; tags github.com example/lines v1.2.0 v1.3.0-rc.1
feature <<<"$(standard); release_tag github example/lines 1.3"

run

check "a line holding pre-releases alone stops the resolve" has "tool: no release in the 1.3 line"

# release_tag reads only the tags behind a prefix.
sandbox; tags github.com example/prefixed rust-v0.168.0 rust-v0.169.0 v9.0.0 other-v1.0.0
feature <<<"$(standard); echo \"l=\$(release_tag github example/prefixed latest --prefix rust-) b=\$(release_tag github example/prefixed latest --bare --prefix rust-) n=\$(release_tag github example/prefixed 0.168 --prefix rust- --bare)\"; exit 0"

run

check "release_tag reads only the tags behind a prefix" has "l=rust-v0.169.0 b=0.169.0 n=0.168.0"

# An exact version needs no remote, with or without a prefix.
sandbox; feature <<<"$(standard); echo \"e=\$(release_tag github example/missing 2.0.0) p=\$(release_tag github example/missing 0.169.0 --prefix rust-) b=\$(release_tag github example/missing v0.169.0 --prefix rust- --bare)\"; exit 0"

run

check "an exact version needs no remote, with or without a prefix" has "e=v2.0.0 p=rust-v0.169.0 b=0.169.0"

# The install root and release tags come from the test settings alone.
sandbox; mkdir -p "$SANDBOX/elsewhere"; feature <<<"$(standard)
feature_main"

run FEATURE_ROOT="$SANDBOX/elsewhere" RELEASE_API="file:///nowhere"

check "the install root and release tags come from the test settings alone" bash -c "[ -x '$SANDBOX/root/usr/local/bin/tool' ] && [ -z \"\$(ls -A '$SANDBOX/elsewhere')\" ]"

# --- the sequence ----------------------------------------------------------------------

# feature_main installs the verified tool.
sandbox; feature <<<"$(standard)
PACKAGES=(ca-certificates curl)
feature_main"

run

check "feature_main installs the verified tool" installed tool

# feature_main logs the resolved release.
sandbox; feature <<<"$(standard)
PACKAGES=(ca-certificates curl)
feature_main"

run

check "feature_main logs the resolved release" has "tool: installing v1.2.3 (latest)"

# feature_main installs the declared packages.
sandbox; feature <<<"$(standard)
PACKAGES=(ca-certificates curl)
feature_main"

run

check "feature_main installs the declared packages" grep -qF "install -y --no-install-recommends ca-certificates curl" "$SANDBOX/apt.log"

# feature_main confirms the tool runs.
sandbox; feature <<<"$(standard)
PACKAGES=(ca-certificates curl)
feature_main"

run

check "feature_main confirms the tool runs" has "tool 1.2.3"

# A per-file checksum verifies the download.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#checksum="\$url.sha256"#')
feature_main"

run

check "a per-file checksum verifies the download" installed tool

# A checksum mismatch stops the install.
sandbox; feature <<<"$(standard)
feature_main"
echo "0000000000000000000000000000000000000000000000000000000000000000  tool-v1.2.3-linux-amd64.tar.gz" \
  > "$SANDBOX/release/v1.2.3/checksums.txt"

run

check "a checksum mismatch stops the install" bash -c "! [ -e '$SANDBOX/root/usr/local/bin/tool' ] && grep -qF 'tool: checksum mismatch for tool-v1.2.3-linux-amd64.tar.gz' '$SANDBOX/out'"

# A checksum list in binary-mode notation verifies the download.
sandbox; feature <<<"$(standard)
feature_main"
sed -i 's/  / */' "$SANDBOX/release/v1.2.3/checksums.txt"

run

check "a checksum list in binary-mode notation verifies the download" installed tool

# A checksum list matches the asset name exactly.
sandbox; feature <<<"$(standard)
feature_main"
sed -i 's/tool-v1.2.3-linux-amd64.tar.gz/tool-v1x2x3-linux-amd64xtarxgz/' "$SANDBOX/release/v1.2.3/checksums.txt"

run

check "a checksum list matches the asset name exactly" bash -c "! [ -e '$SANDBOX/root/usr/local/bin/tool' ] && grep -qF 'tool: no checksum for tool-v1.2.3-linux-amd64.tar.gz in the list' '$SANDBOX/out'"

# A per-file checksum holding the hash alone verifies the download.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#checksum="\$url.sha256"#')
feature_main"
cut -d' ' -f1 "$SANDBOX/release/v1.2.3/checksums.txt" > "$SANDBOX/release/v1.2.3/tool-v1.2.3-linux-amd64.tar.gz.sha256"

run

check "a per-file checksum holding the hash alone verifies the download" installed tool

# An unverified download states its reason.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#unverified="the vendor publishes none"#')
feature_main"

run

check "an unverified download states its reason" has "tool: trusting the download over HTTPS: the vendor publishes none"

# An unverified download still installs.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#unverified="the vendor publishes none"#')
feature_main"

run

check "an unverified download still installs" installed tool

# A download without a verification declaration stops.
sandbox; feature <<<"$(standard | sed '/checksums=/d')
feature_main"

run

check "a download without a verification declaration stops" has "tool: declare one of checksums, checksum, unverified or delegated"

# Two verification declarations stop.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#checksums="\$REL/\$tag/checksums.txt"; unverified="both"#')
feature_main"

run

check "two verification declarations stop" has "tool: declare one of checksums, checksum, unverified or delegated"

# A missing required function stops and names it.
sandbox; feature <<<"$(standard | sed '/^install_program/d')
feature_main"

run

check "a missing required function stops and names it" has "tool: missing install_program"

# The library functions stay fixed for every feature.
sandbox; feature <<<"$(standard)
log() { echo overridden; }
feature_main"

run

check "the library functions stay fixed for every feature" bash -c "! [ -e '$SANDBOX/root/usr/local/bin/tool' ] && grep -q 'readonly function' '$SANDBOX/out'"

# --- optional parts --------------------------------------------------------------------

# profile writes the login profile.
sandbox; feature <<<"$(standard)
profile() { echo 'export TOOL_HOME=/x'; }
settings() { install -d \"\$FEATURE_ROOT/usr/local/etc/tool\"; echo set > \"\$FEATURE_ROOT/usr/local/etc/tool/config\"; }
post_install() { echo post-ran; }
confirm() { echo confirm-ran; }
feature_main"

run

check "profile writes the login profile" grep -qx "export TOOL_HOME=/x" "$SANDBOX/root/etc/profile.d/tool.sh"

# settings runs.
sandbox; feature <<<"$(standard)
profile() { echo 'export TOOL_HOME=/x'; }
settings() { install -d \"\$FEATURE_ROOT/usr/local/etc/tool\"; echo set > \"\$FEATURE_ROOT/usr/local/etc/tool/config\"; }
post_install() { echo post-ran; }
confirm() { echo confirm-ran; }
feature_main"

run

check "settings runs" grep -qx set "$SANDBOX/root/usr/local/etc/tool/config"

# post_install runs.
sandbox; feature <<<"$(standard)
profile() { echo 'export TOOL_HOME=/x'; }
settings() { install -d \"\$FEATURE_ROOT/usr/local/etc/tool\"; echo set > \"\$FEATURE_ROOT/usr/local/etc/tool/config\"; }
post_install() { echo post-ran; }
confirm() { echo confirm-ran; }
feature_main"

run

check "post_install runs" has "post-ran"

# confirm can be replaced.
sandbox; feature <<<"$(standard)
profile() { echo 'export TOOL_HOME=/x'; }
settings() { install -d \"\$FEATURE_ROOT/usr/local/etc/tool\"; echo set > \"\$FEATURE_ROOT/usr/local/etc/tool/config\"; }
post_install() { echo post-ran; }
confirm() { echo confirm-ran; }
feature_main"

run

check "confirm can be replaced" has "confirm-ran"

# A profile is written only from printed lines.
sandbox; feature <<<"$(standard)
profile() { :; }
feature_main"

run

check "a profile is written only from printed lines" bash -c "! [ -e '$SANDBOX/root/etc/profile.d/tool.sh' ]"

# A set state dir is claimed first.
sandbox; printf '#!/bin/sh\necho "claimed $1 $2"\n' > "$SANDBOX/feature/state-dir.sh"
printf '#!/bin/sh\n' > "$SANDBOX/feature/init.sh"; chmod +x "$SANDBOX/feature/state-dir.sh" "$SANDBOX/feature/init.sh"
cp "$(dirname "$LIB")/hook.sh" "$SANDBOX/feature/hook.sh"
feature <<<"$(standard)
feature_main"

run STATEDIR=/home/ubuntu/.local/state/tool

check "a set state dir is claimed first" has "claimed tool /home/ubuntu/.local/state/tool"

# The hooks land in libexec.
sandbox; printf '#!/bin/sh\necho "claimed $1 $2"\n' > "$SANDBOX/feature/state-dir.sh"
printf '#!/bin/sh\n' > "$SANDBOX/feature/init.sh"; chmod +x "$SANDBOX/feature/state-dir.sh" "$SANDBOX/feature/init.sh"
cp "$(dirname "$LIB")/hook.sh" "$SANDBOX/feature/hook.sh"
feature <<<"$(standard)
feature_main"

run STATEDIR=/home/ubuntu/.local/state/tool

check "the hooks land in libexec" bash -c "[ -x '$SANDBOX/root/usr/local/libexec/tool/init.sh' ] && [ -x '$SANDBOX/root/usr/local/libexec/tool/state-dir.sh' ]"

# The shared hook lands beside them.
sandbox; printf '#!/bin/sh\necho "claimed $1 $2"\n' > "$SANDBOX/feature/state-dir.sh"
printf '#!/bin/sh\n' > "$SANDBOX/feature/init.sh"; chmod +x "$SANDBOX/feature/state-dir.sh" "$SANDBOX/feature/init.sh"
cp "$(dirname "$LIB")/hook.sh" "$SANDBOX/feature/hook.sh"
feature <<<"$(standard)
feature_main"

run STATEDIR=/home/ubuntu/.local/state/tool

check "the shared hook lands beside them" bash -c "[ -f '$SANDBOX/root/usr/local/libexec/tool/hook.sh' ]"

# The state dir is recorded for the hook.
sandbox; printf '#!/bin/sh\necho "claimed $1 $2"\n' > "$SANDBOX/feature/state-dir.sh"
printf '#!/bin/sh\n' > "$SANDBOX/feature/init.sh"; chmod +x "$SANDBOX/feature/state-dir.sh" "$SANDBOX/feature/init.sh"
cp "$(dirname "$LIB")/hook.sh" "$SANDBOX/feature/hook.sh"
feature <<<"$(standard)
feature_main"

run STATEDIR=/home/ubuntu/.local/state/tool

check "the state dir is recorded for the hook" bash -c "[ \"\$(cat '$SANDBOX/root/usr/local/etc/tool/state-dir')\" = /home/ubuntu/.local/state/tool ]"

# A state dir names the guard the feature needs.
sandbox; feature <<<"$(standard)
feature_main"

run STATEDIR=/home/ubuntu/.local/state/tool

check "a state dir names the guard the feature needs" has "tool: a state dir needs state-dir.sh in the feature"

# A feature without a version option installs.
sandbox; feature <<<"$(standard)"
sed -i '/^VERSION=/d; s/release_tag github example\/tool "\$VERSION"/release_tag github example\/tool 1.2.3/' "$SANDBOX/feature/install.sh"
echo feature_main >> "$SANDBOX/feature/install.sh"

run

check "a feature without a version option installs" installed tool

# A feature without a version option logs its release.
sandbox; feature <<<"$(standard)"
sed -i '/^VERSION=/d; s/release_tag github example\/tool "\$VERSION"/release_tag github example\/tool 1.2.3/' "$SANDBOX/feature/install.sh"
echo feature_main >> "$SANDBOX/feature/install.sh"

run

check "a feature without a version option logs its release" has "tool: installing v1.2.3"

# Hooks are installed only for features that ship them.
sandbox; feature <<<"$(standard)
feature_main"

run

check "hooks are installed only for features that ship them" bash -c "! [ -e '$SANDBOX/root/usr/local/libexec/tool' ]"

# --- flat tarballs -----------------------------------------------------------------------

# untar keeps a flat tarball's file.
sandbox; tar -czf "$SANDBOX/release/v1.2.3/flat.tar.gz" -C "$SANDBOX/pkg/tool-v1.2.3" tool
feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/flat.tar.gz"#; s#checksums=.*#unverified="flat fixture"#')
feature_main"

run

check "untar keeps a flat tarball's file" installed tool

# unpack keeps a flat tarball's file in its tree.
sandbox; tar -czf "$SANDBOX/release/v1.2.3/flat.tar.gz" -C "$SANDBOX/pkg/tool-v1.2.3" tool
feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/flat.tar.gz"#; s#checksums=.*#unverified="flat fixture"#; s#^install_program.*#install_program() { unpack /opt/tool; link_bin /opt/tool tool; }#')
feature_main"

run

check "unpack keeps a flat tarball's file in its tree" bash -c "[ -x '$SANDBOX/root/opt/tool/tool' ]"

# --- program trees ---------------------------------------------------------------------

# unpack places the release in its own tree.
sandbox; feature <<<"$(standard | sed 's#^install_program.*#install_program() { unpack /opt/tool --exclude=README.md; link_bin /opt/tool; }#')
feature_main"

run

check "unpack places the release in its own tree" bash -c "[ -x '$SANDBOX/root/opt/tool/tool' ]"

# unpack passes extra archive options through.
sandbox; feature <<<"$(standard | sed 's#^install_program.*#install_program() { unpack /opt/tool --exclude=README.md; link_bin /opt/tool; }#')
feature_main"

run

check "unpack passes extra archive options through" bash -c "! [ -e '$SANDBOX/root/opt/tool/README.md' ]"

# link_bin puts the tree's commands on the PATH.
sandbox; feature <<<"$(standard | sed 's#^install_program.*#install_program() { unpack /opt/tool --exclude=README.md; link_bin /opt/tool; }#')
feature_main"

run

check "link_bin puts the tree's commands on the PATH" bash -c "[ -L '$SANDBOX/root/usr/local/bin/tool' ] && [ \"\$(readlink '$SANDBOX/root/usr/local/bin/tool')\" = '$SANDBOX/root/opt/tool/tool' ]"

# A linked command runs.
sandbox; feature <<<"$(standard | sed 's#^install_program.*#install_program() { unpack /opt/tool --exclude=README.md; link_bin /opt/tool; }#')
feature_main"

run

check "a linked command runs" has "tool 1.2.3"

# unpack opens a zip archive into the tree.
sandbox; feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/tool-linux64.zip"#; s#checksums=.*#unverified="zip fixture"#; s#^install_program.*#install_program() { unpack /opt/tool; link_bin /opt/tool tool; }#')
feature_main"

run

check "unpack opens a zip archive into the tree" bash -c "[ -x '$SANDBOX/root/opt/tool/tool' ]"

# link_bin links the named command.
sandbox; feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/tool-linux64.zip"#; s#checksums=.*#unverified="zip fixture"#; s#^install_program.*#install_program() { unpack /opt/tool; link_bin /opt/tool tool; }#')
feature_main"

run

check "link_bin links the named command" bash -c "[ -L '$SANDBOX/root/usr/local/bin/tool' ]"

# A sha512 checksum verifies the download.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#checksum="\$url.sha512"#')
feature_main"

run

check "a sha512 checksum verifies the download" installed tool

# A sha512 mismatch stops the install.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#checksum="\$url.sha512"#')
feature_main"
printf '%0128d  tool-v1.2.3-linux-amd64.tar.gz\n' 0 > "$SANDBOX/release/v1.2.3/tool-v1.2.3-linux-amd64.tar.gz.sha512"

run

check "a sha512 mismatch stops the install" has "tool: checksum mismatch for tool-v1.2.3-linux-amd64.tar.gz"

# write_file writes the content exactly.
sandbox; feature <<<"$(standard)
settings() { write_file /etc/opt/tool/config 'key=value'; write_file /usr/local/etc/tool/empty ''; }
feature_main"

run

check "write_file writes the content exactly" bash -c "[ \"\$(cat '$SANDBOX/root/etc/opt/tool/config')\" = 'key=value' ] && [ \"\$(stat -c %a '$SANDBOX/root/etc/opt/tool/config')\" = 644 ]"

# write_file keeps empty content empty.
sandbox; feature <<<"$(standard)
settings() { write_file /etc/opt/tool/config 'key=value'; write_file /usr/local/etc/tool/empty ''; }
feature_main"

run

check "write_file keeps empty content empty" bash -c "[ -f '$SANDBOX/root/usr/local/etc/tool/empty' ] && ! [ -s '$SANDBOX/root/usr/local/etc/tool/empty' ]"

# Build a zip in the release from name=content pairs, each entry executable.
zipped() {
  local zip="$1"; shift
  python3 -I -c 'import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
for pair in sys.argv[2:]:
    name, content = pair.split("=", 1)
    i = zipfile.ZipInfo(name); i.external_attr = 0o755 << 16
    z.writestr(i, content)
z.close()' "$SANDBOX/release/v1.2.3/$zip" "$@"
}

# unpack keeps a zip's root files as they are.
sandbox; zipped flat.zip "tool=#!/bin/sh
echo tool 1.2.3" "NOTICE=notes"
feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/flat.zip"#; s#checksums=.*#unverified="zip fixture"#; s#^install_program.*#install_program() { unpack /opt/tool; link_bin /opt/tool tool; }#')
feature_main"

run

check "unpack keeps a zip's root files as they are" bash -c "[ -x '$SANDBOX/root/opt/tool/tool' ] && [ -f '$SANDBOX/root/opt/tool/NOTICE' ]"

# unpack keeps a zip's several top folders apart.
sandbox; zipped two.zip "a/tool=#!/bin/sh
echo tool 1.2.3" "b/extra=x"
feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/two.zip"#; s#checksums=.*#unverified="zip fixture"#; s#^install_program.*#install_program() { unpack /opt/tool; link_bin /opt/tool/a tool; }#')
feature_main"

run

check "unpack keeps a zip's several top folders apart" bash -c "[ -x '$SANDBOX/root/opt/tool/a/tool' ] && [ -f '$SANDBOX/root/opt/tool/b/extra' ]"

# unpack names archive options a zip can't take.
sandbox; feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/tool-linux64.zip"#; s#checksums=.*#unverified="zip fixture"#; s#^install_program.*#install_program() { unpack /opt/tool --exclude=README.md; }#')
feature_main"

run

check "unpack names archive options a zip can't take" has "tool: archive options apply to tarballs"

# A checksum list of sha512 digests verifies the download.
sandbox; ( cd "$SANDBOX/release/v1.2.3" && sha512sum tool-v1.2.3-linux-amd64.tar.gz > checksums512.txt )
feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#checksums="\$REL/\$tag/checksums512.txt"#')
feature_main"

run

check "a checksum list of sha512 digests verifies the download" installed tool

# link_bin names an empty tree and links nothing from it.
sandbox; feature <<<"$(standard | sed 's#^install_program.*#install_program() { untar; install -d "$FEATURE_ROOT/opt/empty"; link_bin /opt/empty; }#')
feature_main"

run

check "link_bin names an empty tree and links nothing from it" bash -c "grep -qF 'tool: no commands in /opt/empty' '$SANDBOX/out' && [ -z \"\$(ls -A '$SANDBOX/root/usr/local/bin' 2>/dev/null)\" ]"

# write_file without content writes an empty file.
sandbox; feature <<<"$(standard)
settings() { write_file /usr/local/etc/tool/blank; }
feature_main"

run

check "write_file without content writes an empty file" bash -c "[ -f '$SANDBOX/root/usr/local/etc/tool/blank' ] && ! [ -s '$SANDBOX/root/usr/local/etc/tool/blank' ]"

# --- vendor installers ------------------------------------------------------------------

# The body for a tool whose vendor installer fetches and checks it, run as the dev user.
delegating() {
  cat <<'EOF'
resolve_version() { tag="$VERSION"; delegated="the vendor installer checks its own download"; }
install_program() { as_user "echo installed by the vendor installer"; }
EOF
}

# A delegated download needs no release file.
sandbox; feature <<<"$(delegating)
confirm() { :; }
feature_main"

run _REMOTE_USER=ubuntu

check "a delegated download needs no release file" has "installed by the vendor installer"

# A delegated download states its reason.
sandbox; feature <<<"$(delegating)
confirm() { :; }
feature_main"

run _REMOTE_USER=ubuntu

check "a delegated download states its reason" has "tool: delegating the download: the vendor installer checks its own download"

# as_user runs the command as the dev user.
sandbox; feature <<<"$(delegating)
confirm() { :; }
feature_main"

run _REMOTE_USER=ubuntu

check "as_user runs the command as the dev user" grep -qxF "as ubuntu: echo installed by the vendor installer" "$SANDBOX/su.log"

# A delegated download with a second declaration stops.
sandbox; feature <<<"$(delegating | sed 's#delegated="the vendor installer checks its own download"#delegated="x"; checksums="y"#')
feature_main"

run

check "a delegated download with a second declaration stops" has "tool: declare one of checksums, checksum, unverified or delegated"

# A version that names itself is logged once.
sandbox; feature <<<"$(delegating)
confirm() { :; }
feature_main"

run

check "a version that names itself is logged once" bash -c "grep -qx 'tool: installing latest' '$SANDBOX/out'"

# record keeps a setting for the feature's hooks.
sandbox; feature <<<"$(delegating)
confirm() { :; }
settings() { record requested.json '{\"a\": 1}'; record empty ''; }
feature_main"

run

check "record keeps a setting for the feature's hooks" bash -c "[ \"\$(cat '$SANDBOX/root/usr/local/etc/tool/requested.json')\" = '{\"a\": 1}' ] && [ -f '$SANDBOX/root/usr/local/etc/tool/empty' ] && ! [ -s '$SANDBOX/root/usr/local/etc/tool/empty' ]"

# --- review follow-ups -------------------------------------------------------------------

# A bare tag drops the v for latest as well.
sandbox; feature <<<"$(standard); echo \"lb=\$(release_tag github example/tool latest --bare)\"; exit 0"

run

check "a bare tag drops the v for latest as well" has "lb=1.2.3"

# unpack keeps a zip's hidden root files beside its folder.
sandbox; zipped hidden.zip ".hidden=x" "top/tool=#!/bin/sh
echo tool 1.2.3"
feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/hidden.zip"#; s#checksums=.*#unverified="zip fixture"#; s#^install_program.*#install_program() { unpack /opt/tool; }#')
confirm() { :; }
feature_main"

run

check "unpack keeps a zip's hidden root files beside its folder" bash -c "[ -f '$SANDBOX/root/opt/tool/.hidden' ] && [ -x '$SANDBOX/root/opt/tool/top/tool' ]"

# unpack replaces a tree from an earlier zip.
sandbox; zipped two.zip "a/tool=#!/bin/sh
echo tool 1.2.3" "b/extra=x"
feature <<<"$(standard | sed 's#url=.*#url="$REL/$tag/two.zip"#; s#checksums=.*#unverified="zip fixture"#; s#^install_program.*#install_program() { unpack /opt/tool; unpack /opt/tool; link_bin /opt/tool/a tool; }#')
feature_main"

run

check "unpack replaces a tree from an earlier zip" bash -c "[ -x '$SANDBOX/root/opt/tool/a/tool' ] && grep -q 'tool 1.2.3' '$SANDBOX/out'"

# A checksum list without the asset names what it lacks.
sandbox; feature <<<"$(standard)
feature_main"
sed -i 's/tool-v1.2.3-linux-amd64.tar.gz/tool-renamed.tar.gz/' "$SANDBOX/release/v1.2.3/checksums.txt"

run

check "a checksum list without the asset names what it lacks" has "tool: no checksum for tool-v1.2.3-linux-amd64.tar.gz in the list"

# The sync check reports a library copy its feature no longer sources.
sandbox; repo="$SANDBOX/repo"; mkdir -p "$repo/lib" "$repo/src/plain"
cp "$(dirname "$LIB")/sync.sh" "$LIB" "$(dirname "$LIB")/state-dir.sh" "$repo/lib/"
printf '#!/bin/sh\necho plain\n' > "$repo/src/plain/install.sh"; cp "$LIB" "$repo/src/plain/lib.sh"

bash "$repo/lib/sync.sh" --check > "$SANDBOX/out" 2>&1

check "the sync check reports a library copy its feature no longer sources" has "src/plain/lib.sh is a library copy its feature doesn't source"

# --- version format and delegated unpacks ------------------------------------------------

# A version outside the format stops before any command runs.
sandbox; feature <<<"$(delegating)
confirm() { :; }
feature_main"
sed -i 's/^resolve_version() { tag=/resolve_version() { require_version "^(latest|[0-9]+\\\\.[0-9]+\\\\.[0-9]+)\\$"; tag=/' "$SANDBOX/feature/install.sh"

run VERSION="latest'; touch $SANDBOX/pwned; echo '"

check "a version outside the format stops before any command runs" bash -c "grep -qF \"tool: unsupported version 'latest'\" '$SANDBOX/out' && ! [ -e '$SANDBOX/pwned' ] && ! [ -e '$SANDBOX/su.log' ]"

# A version in the format installs.
sandbox; feature <<<"$(delegating)
confirm() { :; }
feature_main"
sed -i 's/^resolve_version() { tag=/resolve_version() { require_version "^(latest|[0-9]+\\\\.[0-9]+\\\\.[0-9]+)\\$"; tag=/' "$SANDBOX/feature/install.sh"

run VERSION=2.1.0

check "a version in the format installs" has "tool: installing 2.1.0"

# A further version outside the format stops before any command runs.
sandbox; feature <<<"$(delegating | sed 's#^install_program.*#install_program() { as_user "echo plugin $PLUGIN"; }#')
confirm() { :; }
feature_main"
sed -i 's/^resolve_version() { tag=/resolve_version() { require_version "^(latest|[0-9]+)\\$" "$PLUGIN" plugin; tag=/' "$SANDBOX/feature/install.sh"

run VERSION=2.1.0 PLUGIN="1; touch $SANDBOX/pwned"

check "a further version outside the format stops before any command runs" bash -c "! [ -e '$SANDBOX/pwned' ] && ! [ -e '$SANDBOX/su.log' ]"

# A rejected further version names its option.
sandbox; feature <<<"$(delegating | sed 's#^install_program.*#install_program() { as_user "echo plugin $PLUGIN"; }#')
confirm() { :; }
feature_main"
sed -i 's/^resolve_version() { tag=/resolve_version() { require_version "^(latest|[0-9]+)\\$" "$PLUGIN" plugin; tag=/' "$SANDBOX/feature/install.sh"

run VERSION=2.1.0 PLUGIN="1; touch $SANDBOX/pwned"

check "a rejected further version names its option" has "tool: unsupported plugin '1; touch"

# Unpacking after a delegated download names what's missing.
sandbox; feature <<<"$(delegating | sed 's#^install_program.*#install_program() { unpack /opt/tool; }#')
feature_main"

run

check "unpacking after a delegated download names what's missing" has "tool: nothing was downloaded to unpack"

# --- the shared hook --------------------------------------------------------------------

# Write the feature's hook: the shared hook, the feature's own part, then init_main.
hook() {
  cp "$(dirname "$LIB")/hook.sh" "$SANDBOX/feature/hook.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo '. "$(dirname "$0")/hook.sh"'
    cat
    echo 'init_main tool "$@"'
  } > "$SANDBOX/feature/init.sh"
  mkdir -p "$SANDBOX/root/usr/local/etc/tool" "$SANDBOX/root/etc/profile.d" "$SANDBOX/home"
}

# Run the hook the way a container create does.
run_hook() {
  env _FEATURE_TEST_ROOT="$SANDBOX/root" HOME="$SANDBOX/home" bash "$SANDBOX/feature/init.sh" "$@" > "$SANDBOX/out" 2>&1
}

# The hook creates the recorded state dir, private to the dev user.
sandbox; hook <<<''; printf '%s' "$SANDBOX/state" > "$SANDBOX/root/usr/local/etc/tool/state-dir"

run_hook

check "the hook creates the recorded state dir, private to the dev user" bash -c "[ \"\$(stat -c %a '$SANDBOX/state')\" = 700 ]"

# The hook warns about a state dir on the container filesystem.
sandbox; hook <<<''; printf '%s' "$SANDBOX/state" > "$SANDBOX/root/usr/local/etc/tool/state-dir"

run_hook

check "the hook warns about a state dir on the container filesystem" has "tool: $SANDBOX/state is on the container filesystem; mount a volume there to keep it across rebuilds"

# The hook stays quiet about the volume at build.
sandbox; hook <<<''; printf '%s' "$SANDBOX/state" > "$SANDBOX/root/usr/local/etc/tool/state-dir"

run_hook --build

check "the hook stays quiet about the volume at build" bash -c "[ -d '$SANDBOX/state' ] && ! grep -q 'container filesystem' '$SANDBOX/out'"

# init_state sees the state dir, the profile and the arguments.
sandbox; hook <<<'init_state() { echo "state=$STATE_DIR color=$TOOL_COLOR args=$*"; }'
printf '%s' "$SANDBOX/state" > "$SANDBOX/root/usr/local/etc/tool/state-dir"
echo 'export TOOL_COLOR=blue' > "$SANDBOX/root/etc/profile.d/tool.sh"

run_hook --build

check "init_state sees the state dir, the profile and the arguments" has "state=$SANDBOX/state color=blue args=--build"

# A hook without a recorded state dir still runs its own part.
sandbox; hook <<<'init_state() { echo "state=[$STATE_DIR]"; }'

run_hook

check "a hook without a recorded state dir still runs its own part" bash -c "grep -qx 'state=\[\]' '$SANDBOX/out' && ! grep -q 'container filesystem' '$SANDBOX/out'"

# The sync check reports a hook copy its feature's hook no longer sources.
sandbox; repo="$SANDBOX/repo"; mkdir -p "$repo/lib" "$repo/src/plain"
cp "$(dirname "$LIB")/sync.sh" "$LIB" "$(dirname "$LIB")/state-dir.sh" "$(dirname "$LIB")/hook.sh" "$repo/lib/"
printf '#!/bin/sh\necho plain\n' > "$repo/src/plain/install.sh"; printf '#!/bin/sh\n' > "$repo/src/plain/init.sh"
cp "$(dirname "$LIB")/hook.sh" "$repo/src/plain/hook.sh"

bash "$repo/lib/sync.sh" --check > "$SANDBOX/out" 2>&1

check "the sync check reports a hook copy its feature's hook no longer sources" has "src/plain/hook.sh is a hook copy its feature's hook doesn't source"

# --- the state-dir guard ----------------------------------------------------------------

# Claim a nested state dir as the CLI does, with the user switch and ownership changes recorded.
claim() {
  printf '#!/bin/sh\necho "$*" >> "%s/chown.log"\n' "$SANDBOX" > "$SANDBOX/bin/chown"
  printf '#!/bin/sh\necho "$*" >> "%s/runuser.log"\nshift 3\nexec "$@"\n' "$SANDBOX" > "$SANDBOX/bin/runuser"
  chmod +x "$SANDBOX/bin/chown" "$SANDBOX/bin/runuser"
  mkdir -p "$SANDBOX/home"
  env PATH="$SANDBOX/bin:$PATH" _REMOTE_USER=ubuntu _REMOTE_USER_HOME="$SANDBOX/home" \
    bash "$(dirname "$LIB")/state-dir.sh" tool "$SANDBOX/home/$1" > "$SANDBOX/out" 2>&1
}

# The dev user creates a nested state dir and the folders above it.
sandbox; mkdir -p "$SANDBOX/home/.local"

claim .local/state/tool

check "the dev user creates a nested state dir and the folders above it" \
  grep -qx -- "-u ubuntu -- mkdir -p $SANDBOX/home/.local/state/tool" "$SANDBOX/runuser.log"

# The state dir is handed to the dev user.
sandbox; mkdir -p "$SANDBOX/home/.local"

claim .local/state/tool

check "the state dir is handed to the dev user" grep -qx "ubuntu: $SANDBOX/home/.local/state/tool" "$SANDBOX/chown.log"

# The folders above the state dir stay open to read.
sandbox; mkdir -p "$SANDBOX/home/.local"

claim .local/state/tool

check "the folders above the state dir stay open to read" bash -c "[ \"\$(stat -c %a '$SANDBOX/home/.local/state')\" = 755 ]"

# The state dir stays private.
sandbox; mkdir -p "$SANDBOX/home/.local"

claim .local/state/tool

check "the state dir stays private" bash -c "[ \"\$(stat -c %a '$SANDBOX/home/.local/state/tool')\" = 700 ]"

# --- options checked first ----------------------------------------------------------------

# A version checked where it is read stops before any package is installed.
sandbox; feature <<<"$(standard)
require_version '^(latest|[0-9]+\\.[0-9]+\\.[0-9]+)$'
feature_main"

run VERSION="1.2; id"

check "a version checked where it is read stops before any package is installed" \
  bash -c "grep -qF \"tool: unsupported version '1.2; id'\" '$SANDBOX/out' && ! [ -e '$SANDBOX/apt.log' ]"

# A state dir with shell syntax is refused.
sandbox; mkdir -p "$SANDBOX/home"

env _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="$SANDBOX/home" \
  bash "$(dirname "$LIB")/state-dir.sh" tool "$SANDBOX/home/\$(touch $SANDBOX/pwned)" > "$SANDBOX/out" 2>&1

check "a state dir with shell syntax is refused" \
  bash -c "grep -qF 'tool: stateDir may hold letters, digits and ._@+- alone' '$SANDBOX/out' && ! [ -e '$SANDBOX/home/\$(touch $SANDBOX/pwned)' ]"

# --- cleanup follow-ups -------------------------------------------------------------------

# unpack replaces an earlier tree, so no old file stays behind.
sandbox; mkdir -p "$SANDBOX/root/opt/tool"; echo old > "$SANDBOX/root/opt/tool/stale"
feature <<<"$(standard | sed 's#^install_program.*#install_program() { unpack /opt/tool; link_bin /opt/tool; }#')
feature_main"

run

check "unpack replaces an earlier tree, so no old file stays behind" \
  bash -c "[ -x '$SANDBOX/root/opt/tool/tool' ] && ! [ -e '$SANDBOX/root/opt/tool/stale' ]"

# A malformed checksum file is named as such.
sandbox; feature <<<"$(standard | sed 's#checksums="\$REL/\$tag/checksums.txt"#checksum="\$url.sha256"#')
feature_main"
echo "not a digest" > "$SANDBOX/release/v1.2.3/tool-v1.2.3-linux-amd64.tar.gz.sha256"

run

check "a malformed checksum file is named as such" has "tool: malformed checksum for tool-v1.2.3-linux-amd64.tar.gz"

# A feature's extra hooks land beside its hook.
sandbox; printf '#!/bin/sh\n' > "$SANDBOX/feature/init.sh"; printf '#!/bin/sh\n' > "$SANDBOX/feature/extra-init.sh"
feature <<<"$(standard)
HOOKS+=(extra-init.sh)
feature_main"

run

check "a feature's extra hooks land beside its hook" bash -c "[ -x '$SANDBOX/root/usr/local/libexec/tool/extra-init.sh' ]"

# The shared hook offers the state dir's preparation alone.
sandbox; printf '#!/usr/bin/env bash\n. "$(dirname "$0")/hook.sh"\ndeclare -F | grep -o "apply_config" || echo none\n' > "$SANDBOX/feature/init.sh"
cp "$(dirname "$LIB")/hook.sh" "$SANDBOX/feature/hook.sh"

bash "$SANDBOX/feature/init.sh" > "$SANDBOX/out" 2>&1

check "the shared hook offers the state dir's preparation alone" bash -c "grep -qx none '$SANDBOX/out'"

# --- o3s metadata -------------------------------------------------------------------------

# Write a feature's metadata into a sandbox repo, with the given o3s section.
metadata() {
  mkdir -p "$repo/src/$1"
  printf '{ "id": "%s", "customizations": { "o3s": %s } }\n' "$1" "$2" > "$repo/src/$1/devcontainer-feature.json"
}

# The o3s check accepts metadata in the documented shape.
sandbox; repo="$SANDBOX/repo"
metadata good '{ "hosts": [ { "name": "example.com", "ports": [443], "description": "Downloads" } ],
  "env": [ { "name": "TOOL_HOME", "value": "${stateDir}/home", "description": "Data in the state dir" } ],
  "files": [ { "name": "config.toml", "target": "${stateDir}/config.toml", "description": "Tool config" } ] }'
metadata plain '{}'

bash "$(dirname "$LIB")/o3s-check.sh" "$repo" > "$SANDBOX/out" 2>&1

check "the o3s check accepts metadata in the documented shape" bash -c "grep -qx '2 features checked' '$SANDBOX/out'"

# The o3s check refuses metadata outside the shape.
sandbox; repo="$SANDBOX/repo"
metadata bad '{ "hosts": [ { "name": "example.com", "ports": [443] } ], "env": { "TOOL_HOME": "x" } }'

check "the o3s check refuses metadata outside the shape" bash -c "! bash '$(dirname "$LIB")/o3s-check.sh' '$repo' > '$SANDBOX/out' 2>&1"

# The o3s check names each problem.
sandbox; repo="$SANDBOX/repo"
metadata bad '{ "hosts": [ { "name": "example.com", "ports": [443] } ], "env": { "TOOL_HOME": "x" } }'

bash "$(dirname "$LIB")/o3s-check.sh" "$repo" > "$SANDBOX/out" 2>&1

check "the o3s check names each problem" bash -c "grep -qF 'src/bad: hosts[0] needs a description' '$SANDBOX/out' && grep -qF 'src/bad: env must be a list' '$SANDBOX/out'"

# The o3s check asks every feature for a section.
sandbox; repo="$SANDBOX/repo"; mkdir -p "$repo/src/bare"; echo '{ "id": "bare" }' > "$repo/src/bare/devcontainer-feature.json"

check "the o3s check asks every feature for a section" bash -c "! bash '$(dirname "$LIB")/o3s-check.sh' '$repo' > '$SANDBOX/out' 2>&1 && grep -qF 'src/bare: needs an o3s section' '$SANDBOX/out'"

# --- the oldest release a feature installs ------------------------------------------------

# An exact version below the floor stops before anything is installed.
sandbox; feature <<<"$(standard)
MIN_VERSION=1.2.0
feature_main"

run VERSION=1.0.0

check "an exact version below the floor stops before anything is installed" bash -c "grep -qF 'tool: 1.0.0 is older than 1.2.0, the oldest release this feature installs' '$SANDBOX/out' && ! [ -e '$SANDBOX/root/usr/local/bin/tool' ]"

# A version at the floor installs.
sandbox; feature <<<"$(standard)
MIN_VERSION=1.2.3
feature_main"

run

check "a version at the floor installs" installed tool

# The latest release below the floor stops the install.
sandbox; feature <<<"$(standard)
MIN_VERSION=1.3.0
feature_main"

run

check "the latest release below the floor stops the install" has "tool: 1.2.3 is older than 1.3.0, the oldest release this feature installs"

# An empty floor installs any release.
sandbox; feature <<<"$(standard)
MIN_VERSION=
feature_main"

run

check "an empty floor installs any release" installed tool

# A floor named for arm64 applies there.
sandbox; feature <<<"$(standard)
MIN_VERSION=\"\$(arch_name x86_64= aarch64=1.3.0)\"
feature_main"

run FAKE_ARCH=aarch64

check "a floor named for arm64 applies there" has "tool: 1.2.3 is older than 1.3.0, the oldest release this feature installs"

# A floor named for arm64 leaves amd64 free.
sandbox; feature <<<"$(standard)
MIN_VERSION=\"\$(arch_name x86_64= aarch64=1.3.0)\"
feature_main"

run

check "a floor named for arm64 leaves amd64 free" installed tool

# A four-part floor compares by version, not by text.
sandbox; feature <<<"$(standard); tag=10.0.0.0; MIN_VERSION=9.0.0.0; check_floor && echo passed; exit 0"

run

check "a four-part floor compares by version, not by text" has "passed"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
