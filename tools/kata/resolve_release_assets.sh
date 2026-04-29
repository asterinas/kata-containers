#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

download_latest_release_json() {
  repository="$1"
  output_path="$2"
  max_attempts="$3"
  retry_sleep="$4"

  for attempt in $(seq 1 "${max_attempts}"); do
    if gh api "repos/${repository}/releases/latest" > "${output_path}"; then
      return 0
    fi

    if [ "${attempt}" -eq "${max_attempts}" ]; then
      return 1
    fi

    echo "Failed to read latest release from ${repository}; retrying (${attempt}/${max_attempts})..." >&2
    sleep "${retry_sleep}"
  done
}

kata_release_repository="${KATA_RELEASE_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
kata_static_tarball_url="${KATA_STATIC_TARBALL_URL:-}"
kata_static_tarball_sha256="${KATA_STATIC_TARBALL_SHA256:-}"
kata_expected_commit="${KATA_STATIC_TARBALL_EXPECTED_KATA_COMMIT:-}"
kata_release_wait_attempts="${KATA_STATIC_TARBALL_RELEASE_WAIT_ATTEMPTS:-60}"
kata_release_wait_interval="${KATA_STATIC_TARBALL_RELEASE_WAIT_INTERVAL:-30}"
metadata_env_file="${RESOLVED_ASSETS_ENV_FILE:-$(mktemp)}"

[ -n "${kata_release_repository}" ] || die "KATA_RELEASE_REPOSITORY or GITHUB_REPOSITORY must be set"

RESOLVED_ASTERINAS_METADATA_ENV_FILE="${metadata_env_file}" bash "${script_dir}/asterinas_metadata.sh" resolve
# shellcheck disable=SC1090
. "${metadata_env_file}"

if [ -z "${kata_static_tarball_url}" ]; then
  release_json_download_path="${KATA_STATIC_RELEASE_JSON_DOWNLOAD_PATH:-/tmp/kata-static-release.$$}.json"
  for attempt in $(seq 1 "${kata_release_wait_attempts}"); do
    rm -f "${release_json_download_path}"
    download_latest_release_json "${kata_release_repository}" "${release_json_download_path}" 5 10

    if [ -z "${kata_expected_commit}" ] ||
      jq -e --arg commit "${kata_expected_commit}" '(.body // "") | contains("kata-containers commit: `" + $commit + "`")' "${release_json_download_path}" >/dev/null; then
      break
    fi

    if [ "${attempt}" -eq "${kata_release_wait_attempts}" ]; then
      die "Latest Kata release in ${kata_release_repository} does not contain kata-containers commit ${kata_expected_commit}"
    fi

    echo "Latest Kata release is not for kata-containers commit ${kata_expected_commit}; retrying (${attempt}/${kata_release_wait_attempts})..." >&2
    sleep "${kata_release_wait_interval}"
  done

  kata_static_tarball_url="$(
    jq -r '
      .assets[]
      | select(.name | test("^kata-static-.*-asterinas-amd64\\.tar\\.zst$"))
      | .browser_download_url
    ' "${release_json_download_path}" | head -n 1
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
write_value "kata_static_tarball_url" "${kata_static_tarball_url}"
write_value "kata_static_tarball_sha256" "${kata_static_tarball_sha256}"
