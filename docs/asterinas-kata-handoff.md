# Kata with Asterinas as the Guest Kernel Handoff

## Scope

This handoff note summarizes the current CI, release, and metadata flow for
the `asterinas` branch in this repository.

## Current Source of Truth

The pinned Asterinas source and image metadata now live in:

- `tools/kata/config/asterinas-metadata.env`

That file currently records:

- `ASTERINAS_REPOSITORY=jjf-dev/asterinas`
- `ASTERINAS_REF=kata-support`
- `ASTERINAS_COMMIT=81a7d00c75553745afded98a3932db43e25b9873`
- `ASTERINAS_VERSION=0.17.1`
- `ASTERINAS_DOCKER_IMAGE_VERSION=0.17.2-20260407`

The builder image is no longer stored separately in the metadata file. It is
derived consistently as:

- `asterinas/asterinas:${ASTERINAS_DOCKER_IMAGE_VERSION}`

## Metadata Helper

The metadata helper entry point is now:

- `tools/kata/asterinas_metadata.sh`

Supported subcommands:

- `bash tools/kata/asterinas_metadata.sh load`
- `bash tools/kata/asterinas_metadata.sh update`

`load` emits shell-style `key=value` pairs and GitHub Actions outputs.

`update` refreshes `tools/kata/config/asterinas-metadata.env` from the pinned
upstream repository and ref.

## Workflow Behavior

These workflows now read the repo-owned metadata instead of resolving the
Asterinas source dynamically from a separate repository API call during each
run:

- `.github/workflows/test-asterinas-kata.yml`
- `.github/workflows/test-asterinas-kata-docs.yml`
- `.github/workflows/publish-asterinas-kata-image.yml`
- `.github/workflows/release-asterinas-kata-bundle.yml`

The shared Kata tarball resolution still happens in:

- `tools/kata/resolve_release_assets.sh`

That script now:

1. loads the pinned Asterinas metadata from this repository; and
2. resolves the latest Kata static tarball asset from the configured release
   repository.

## Release Packaging

`tools/packaging/release/build-asterinas-release.sh` now records additional
Asterinas fields in the generated manifest and release notes:

- `asterinas_commit`
- `asterinas_version`
- `asterinas_docker_image_version`

## Docs Updated

The following documentation has already been updated to match the new metadata
flow:

- `tools/kata/README.md`
- `docs/Release-Process.md`

## Validation Done

The current changes were sanity-checked with:

- `bash tools/kata/asterinas_metadata.sh load`
- `bash tools/kata/asterinas_metadata.sh update`
- `KATA_RELEASE_REPOSITORY=asterinas/kata-containers bash tools/kata/resolve_release_assets.sh`
- `python3 -m py_compile tools/kata/interactive_doc_test.py`
- YAML parsing for all files under `.github/workflows/`

## Suggested Next Cleanup

The next likely cleanup is to trim metadata outputs and workflow variables that
are still carried through jobs but are no longer consumed downstream.
