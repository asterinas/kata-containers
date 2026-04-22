#!/usr/bin/env bash

set -euo pipefail

die() {
  echo "$*" >&2
  exit 1
}

write_value() {
  local key="$1"
  local value="$2"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
  else
    printf '%s=%s\n' "${key}" "${value}"
  fi

  if [ -n "${RESOLVED_ASSETS_ENV_FILE:-}" ]; then
    printf '%s=%q\n' "${key}" "${value}" >> "${RESOLVED_ASSETS_ENV_FILE}"
  fi
}

asterinas_upstream_repository="${ASTERINAS_UPSTREAM_REPOSITORY:-asterinas/asterinas}"
asterinas_upstream_ref="${ASTERINAS_UPSTREAM_REF:-main}"
kata_release_repository="${KATA_RELEASE_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
kata_static_tarball_url="${KATA_STATIC_TARBALL_URL:-}"
kata_static_tarball_sha256="${KATA_STATIC_TARBALL_SHA256:-}"

[ -n "${kata_release_repository}" ] || die "KATA_RELEASE_REPOSITORY or GITHUB_REPOSITORY must be set"

asterinas_version="$(
  gh api "repos/${asterinas_upstream_repository}/contents/VERSION?ref=${asterinas_upstream_ref}" --jq .content |
    base64 -d | tr -d '\n'
)"
docker_image_version="$(
  gh api "repos/${asterinas_upstream_repository}/contents/DOCKER_IMAGE_VERSION?ref=${asterinas_upstream_ref}" --jq .content |
    base64 -d | tr -d '\n'
)"

if [ -z "${kata_static_tarball_url}" ]; then
  kata_static_tarball_url="$(
    gh api "repos/${kata_release_repository}/releases/latest" --jq '
      .assets[]
      | select(.name | test("^kata-static-.*-asterinas-amd64\\.tar\\.zst$"))
      | .browser_download_url
    ' | head -n 1
  )"
fi

[ -n "${asterinas_version}" ] || die "Failed to resolve Asterinas VERSION"
[ -n "${docker_image_version}" ] || die "Failed to resolve Asterinas DOCKER_IMAGE_VERSION"
[ -n "${kata_static_tarball_url}" ] || die "Failed to resolve Kata static tarball URL from ${kata_release_repository}"

if [ -z "${kata_static_tarball_sha256}" ]; then
  kata_static_tarball_name="${kata_static_tarball_url##*/}"

  if [[ "${kata_static_tarball_url}" != *.tar.zst ]]; then
    die "Cannot derive SHA256SUMS URL from static tarball URL: ${kata_static_tarball_url}"
  fi

  kata_static_tarball_sha256_url="${kata_static_tarball_url%.tar.zst}.SHA256SUMS"
  kata_static_tarball_sha256="$(
    curl -fsSL "${kata_static_tarball_sha256_url}" |
      awk -v asset_name="${kata_static_tarball_name}" '
        $2 == asset_name || $2 ~ ("/" asset_name "$") {
          print $1
          exit
        }
      '
  )"
fi

[ -n "${kata_static_tarball_sha256}" ] || die "Failed to resolve Kata static tarball SHA256"

write_value "asterinas_version" "${asterinas_version}"
write_value "docker_image_version" "${docker_image_version}"
write_value "kata_static_tarball_url" "${kata_static_tarball_url}"
write_value "kata_static_tarball_sha256" "${kata_static_tarball_sha256}"
