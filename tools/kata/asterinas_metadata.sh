#!/usr/bin/env bash

set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  bash tools/kata/asterinas_metadata.sh load [--file <path>]
  bash tools/kata/asterinas_metadata.sh update [--repo <owner/name>] [--ref <git-ref>] [--output <path>]

Commands:
  load    Load the repo-owned Asterinas metadata and emit shell-style key=value pairs.
  update  Refresh the repo-owned Asterinas metadata file from the configured upstream repository and ref.
EOF
}

log() {
  echo "==> $*" >&2
}

run() {
  printf '+' >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
  "$@"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_metadata_file="${script_dir}/config/asterinas-metadata.env"

write_value() {
  local key="$1"
  local value="$2"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
  else
    printf '%s=%s\n' "${key}" "${value}"
  fi

  if [ -n "${RESOLVED_ASTERINAS_METADATA_ENV_FILE:-}" ]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${RESOLVED_ASTERINAS_METADATA_ENV_FILE}"
  fi
}

load_metadata_file() {
  local metadata_file="$1"

  [ -f "${metadata_file}" ] || die "Asterinas metadata file not found: ${metadata_file}"

  # shellcheck disable=SC1090
  . "${metadata_file}"

  [ -n "${ASTERINAS_REPOSITORY:-}" ] || die "ASTERINAS_REPOSITORY is missing from ${metadata_file}"
  [ -n "${ASTERINAS_REF:-}" ] || die "ASTERINAS_REF is missing from ${metadata_file}"
  [ -n "${ASTERINAS_COMMIT:-}" ] || die "ASTERINAS_COMMIT is missing from ${metadata_file}"
  [ -n "${ASTERINAS_VERSION:-}" ] || die "ASTERINAS_VERSION is missing from ${metadata_file}"
  [ -n "${ASTERINAS_DOCKER_IMAGE_VERSION:-}" ] || die "ASTERINAS_DOCKER_IMAGE_VERSION is missing from ${metadata_file}"
}

load_command() {
  local metadata_file="${default_metadata_file}"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --file)
        [ "$#" -ge 2 ] || die "--file requires a value"
        metadata_file="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown load argument: $1"
        ;;
    esac
  done

  load_metadata_file "${metadata_file}"

  write_value "asterinas_repository" "${ASTERINAS_REPOSITORY}"
  write_value "asterinas_ref" "${ASTERINAS_REF}"
  write_value "asterinas_commit" "${ASTERINAS_COMMIT}"
  write_value "asterinas_commit_date_utc" "${ASTERINAS_COMMIT_DATE_UTC:-}"
  write_value "asterinas_version" "${ASTERINAS_VERSION}"
  write_value "docker_image_version" "${ASTERINAS_DOCKER_IMAGE_VERSION}"
  write_value "asterinas_builder_image" "asterinas/asterinas:${ASTERINAS_DOCKER_IMAGE_VERSION}"
  write_value "asterinas_metadata_updated_at" "${ASTERINAS_METADATA_UPDATED_AT:-}"
}

read_github_text_file() {
  local repository="$1"
  local ref="$2"
  local path="$3"

  run gh api "repos/${repository}/contents/${path}?ref=${ref}" --jq '.content' |
    tr -d '\n' |
    base64 -d
}

update_command() {
  local repository=""
  local ref=""
  local output_file="${default_metadata_file}"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        [ "$#" -ge 2 ] || die "--repo requires a value"
        repository="$2"
        shift 2
        ;;
      --ref)
        [ "$#" -ge 2 ] || die "--ref requires a value"
        ref="$2"
        shift 2
        ;;
      --output)
        [ "$#" -ge 2 ] || die "--output requires a value"
        output_file="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown update argument: $1"
        ;;
    esac
  done

  if [ -f "${output_file}" ]; then
    load_metadata_file "${output_file}"
  fi

  repository="${repository:-${ASTERINAS_REPOSITORY:-jjf-dev/asterinas}}"
  ref="${ref:-${ASTERINAS_REF:-kata-support}}"

  log "Updating Asterinas metadata from ${repository}@${ref}"

  commit="$(run gh api "repos/${repository}/commits/${ref}" --jq '.sha')"
  commit_date_utc="$(run gh api "repos/${repository}/commits/${ref}" --jq '.commit.committer.date')"
  version="$(read_github_text_file "${repository}" "${ref}" VERSION | tr -d '\n')"
  docker_image_version="$(read_github_text_file "${repository}" "${ref}" DOCKER_IMAGE_VERSION | tr -d '\n')"
  updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  [ -n "${commit}" ] || die "failed to resolve ASTERINAS_COMMIT"
  [ -n "${commit_date_utc}" ] || die "failed to resolve ASTERINAS_COMMIT_DATE_UTC"
  [ -n "${version}" ] || die "failed to resolve ASTERINAS_VERSION"
  [ -n "${docker_image_version}" ] || die "failed to resolve ASTERINAS_DOCKER_IMAGE_VERSION"

  tmp_file="$(mktemp)"
  trap 'rm -f "${tmp_file}"' EXIT

  cat > "${tmp_file}" <<EOF
# Managed by tools/kata/asterinas_metadata.sh.
# Update this file with:
#   bash tools/kata/asterinas_metadata.sh update
ASTERINAS_REPOSITORY=${repository}
ASTERINAS_REF=${ref}
ASTERINAS_COMMIT=${commit}
ASTERINAS_COMMIT_DATE_UTC=${commit_date_utc}
ASTERINAS_VERSION=${version}
ASTERINAS_DOCKER_IMAGE_VERSION=${docker_image_version}
ASTERINAS_METADATA_UPDATED_AT=${updated_at}
EOF

  mkdir -p "$(dirname "${output_file}")"
  run mv "${tmp_file}" "${output_file}"
  trap - EXIT

  log "Updated ${output_file}"
  run cat "${output_file}"
}

[ "$#" -gt 0 ] || {
  usage >&2
  exit 1
}

command_name="$1"
shift

case "${command_name}" in
  load)
    load_command "$@"
    ;;
  update)
    update_command "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    die "unknown command: ${command_name}"
    ;;
esac
