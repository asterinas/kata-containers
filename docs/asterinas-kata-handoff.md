# Kata with Asterinas as the Guest Kernel Handoff

## Scope

This handoff note summarizes the current CI, release, and metadata flow for
the `asterinas` branch in this repository.

## Current Source of Truth

The pinned Asterinas source and image metadata now live in:

- `tools/kata/config/asterinas-metadata.env`

That file currently records:

- `ASTERINAS_REPOSITORY=asterinas/asterinas`
- `ASTERINAS_REF=main`
- `ASTERINAS_COMMIT=cdf412ed25b62afe811cdbc19b157be532cc729a`
- `ASTERINAS_VERSION=0.17.2`
- `ASTERINAS_DOCKER_IMAGE_VERSION=0.17.2-20260523`

The builder image is no longer stored separately in the metadata file. It is
derived consistently as:

- `asterinas/asterinas:${ASTERINAS_DOCKER_IMAGE_VERSION}`

## Metadata Helper

The metadata helper entry point is now:

- `tools/kata/asterinas_metadata.sh`

Supported subcommands:

- `bash tools/kata/asterinas_metadata.sh load`
- `bash tools/kata/asterinas_metadata.sh resolve`
- `bash tools/kata/asterinas_metadata.sh update`

`load` emits shell-style `key=value` pairs and GitHub Actions outputs.

`resolve` resolves live metadata from `asterinas/asterinas` when the selector
points at the upstream repository, and otherwise falls back to the pinned
metadata in this repository.

`update` refreshes `tools/kata/config/asterinas-metadata.env` from the pinned
upstream repository and ref.

## Workflow Behavior

These workflows resolve Asterinas metadata through the shared helper, using live
upstream metadata for `asterinas/asterinas@main` by default:

- `.github/workflows/test-asterinas-kata.yml`
- `.github/workflows/test-asterinas-kata-docs.yml`
- `.github/workflows/publish-asterinas-kata-image.yml`
- `.github/workflows/release-asterinas-kata-bundle.yml`

The shared Kata tarball resolution still happens in:

- `tools/kata/resolve_release_assets.sh`

That script now:

1. resolves Asterinas metadata through `tools/kata/asterinas_metadata.sh`; and
2. resolves the latest Kata static tarball asset from the configured release
   repository.

## Release Packaging

`tools/packaging/release/build-asterinas-release.sh` now records additional
Asterinas fields in the generated manifest and release notes:

- `asterinas_commit`
- `asterinas_version`
- `asterinas_docker_image_version`

The regular qemu-direct kernel is packaged as
`/opt/kata/share/kata-containers/aster-kernel-osdk-bin.qemu_elf`. The TDX
kernel is built from `asterinas/target/osdk/aster-kernel-osdk-bin` and packaged
as `/opt/kata/share/kata-containers/aster-kernel-osdk-bin-tdx`.

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
