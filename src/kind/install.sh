#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Options (uppercased by the CLI): VERSION, KUBECTLVERSION.
FEATURE=kind
VERSION="$(option VERSION latest)"
KUBECTL_VERSION="$(option KUBECTLVERSION latest)"

# Accept only options in the feature's format, before anything is installed.
format='^(latest|v?[0-9]+(\.[0-9]+){0,2})$'
require_version "$format"
require_version "$format" "$KUBECTL_VERSION" kubectlVersion
# Name the oldest release with the files this feature installs.
MIN_VERSION=0.12.0
# Resolve the latest releases from the projects' git tags.
PACKAGES+=(git)

# Resolve the request to a release, its binary and its checksum.
resolve_version() {
  tag="$(release_tag github kubernetes-sigs/kind "$VERSION")"
  url="https://github.com/kubernetes-sigs/kind/releases/download/$tag/kind-linux-$(arch_name x86_64=amd64 aarch64=arm64)"
  checksum="$url.sha256sum"
}

# Install kind on the PATH, then kubectl to drive the clusters it makes.
install_program() {
  install_bin "$tmp/$asset" as kind
  install_kubectl
}

# Install the requested kubectl release, checked against the digest published beside it.
install_kubectl() {
  local release base
  release="$(release_tag github kubernetes/kubernetes "$KUBECTL_VERSION")"
  log "with kubectl $release ($KUBECTL_VERSION)"
  base="https://dl.k8s.io/release/$release/bin/linux/$(arch_name x86_64=amd64 aarch64=arm64)"
  asset=kubectl
  curl -fsSL "$base/kubectl" -o "$tmp/kubectl"
  check_digest "$(curl -fsSL "$base/kubectl.sha256" | awk '{ print $1; exit }')"
  install_bin "$tmp/kubectl"
}

# Confirm both tools run from the PATH.
confirm() {
  kind version
  kubectl version --client
}

feature_main
