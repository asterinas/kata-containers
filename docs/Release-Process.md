# How to do a Kata Containers Release

This document lists the tasks required to create a Kata Release.

## Requirements

- GitHub permissions to run workflows.

## Release Model

Kata Containers follows a rolling release model with monthly snapshots.
New features, bug fixes, and improvements are continuously integrated into
`main`. Each month, a snapshot is tagged as a new `MINOR` release.

### Versioning

Releases use the `MAJOR.MINOR.PATCH` scheme. Monthly snapshots increment
`MINOR`; `PATCH` is typically `0`. Major releases are rare (years apart) and
signal significant architectural changes that may require updates to container
managers (Containerd, CRI-O) or other infrastructure. Breaking changes in
`MINOR` releases are avoided where possible, but may occasionally occur as
features are deprecated or removed.

### No Stable Branches

The Kata Containers project does not maintain stable branches (see
[#9064](https://github.com/kata-containers/kata-containers/issues/9064)).
Bug fixes land on `main` and ship in the next monthly snapshot rather than
being backported. Downstream projects that need extended support or compliance
certifications should select a monthly snapshot as their stable base and manage
their own validation and patch backporting from there.

## Release Process

### Bump the `VERSION` and `Chart.yaml` file

When the `kata-containers/kata-containers` repository is ready for a new
release, first create a PR to set the release in the [`VERSION`](./../VERSION)
file and update the `version` and `appVersion` in the
[`Chart.yaml`](./../tools/packaging/kata-deploy/helm-chart/kata-deploy/Chart.yaml)
file and have it merged.

### Lock the `main` branch

In order to prevent any PRs getting merged during the release process, and
slowing the release process down, by impacting the payload caches, we have
recently trialed setting the `main` branch to read only whilst the release
action runs.

> [!NOTE]
> Admin permission is needed to complete this task.

### Check GitHub Actions

We make use of [GitHub actions](https://github.com/features/actions) in the
[release-asterinas-kata-bundle](https://github.com/kata-containers/kata-containers/actions/workflows/release-asterinas-kata-bundle.yml)
workflow from the `kata-containers/kata-containers` repository to build and upload
Asterinas release artifacts.

The action can be started manually with
[`workflow_dispatch`](https://docs.github.com/actions/using-workflows/manually-running-a-workflow)
or automatically by any push. It is responsible for generating or updating an
Asterinas bundle release (including a release tag when needed) in the
`kata-containers/kata-containers` repository.

Manual runs may choose a custom release tag/name and can keep the GitHub release
as a draft. Push-triggered runs publish a `<VERSION>-<YYYYMMDD>-asterinas`
release automatically; if that release tag already exists, the workflow skips
publishing for that duplicate push build.

Check the [actions status
page](https://github.com/kata-containers/kata-containers/actions) to verify all
steps in the actions workflow have completed successfully. On success, a static
tarball containing Kata release artifacts will be uploaded to the [Release
page](https://github.com/kata-containers/kata-containers/releases).

The Asterinas-flavoured static tarball also carries the Kata helper scripts
under `/opt/kata/share/kata-containers/tools/kata`, so CI and downstream image
builds can reuse the same repo-owned helper set that is exercised by the
`test-asterinas-kata` workflow.

The release workflow packages the regular Asterinas qemu-direct kernel as
`/opt/kata/share/kata-containers/aster-kernel-osdk-bin.qemu_elf` and the TDX
kernel as `/opt/kata/share/kata-containers/aster-kernel-osdk-bin-tdx`. The TDX
kernel source artifact is `asterinas/target/osdk/aster-kernel-osdk-bin` after
the `INTEL_TDX=1` build.

The [publish-asterinas-kata-image](https://github.com/kata-containers/kata-containers/actions/workflows/publish-asterinas-kata-image.yml)
workflow builds the matching Docker Hub image. It reads the pinned Asterinas
source/image metadata from `tools/kata/config/asterinas-metadata.env`, layers the repo-owned
`tools/kata/` helpers into `/root/kata-containers/tools/kata`, sets
`/root/kata-containers` as the image working directory, runs
`kata_env.sh install`, and then pushes `asterinas/kata` when Docker
Hub credentials are available.

The Asterinas CI workflows use consumer-side readiness gates instead of a
strict workflow chain. Release packaging can update the same dated release tag
for a later push. Jobs that need the Asterinas Kata static tarball set
`KATA_STATIC_TARBALL_EXPECTED_KATA_COMMIT`; `kata_env.sh` and
`resolve_release_assets.sh` then wait until the latest release notes contain
that commit before using the tarball. The end-user documentation replay
similarly waits until the Docker Hub `asterinas/kata:<DOCKER_IMAGE_VERSION>` tag
has the expected `/root/kata-containers` helper layout. This keeps independent
checks parallel while preventing consumers from using stale release or image
artifacts.

Update `tools/kata/config/asterinas-metadata.env` with
`bash tools/kata/asterinas_metadata.sh update` before rolling the repository
forward to a newer Asterinas source/image pairing.

If the workflow fails because of some external environmental causes, e.g.
network timeout, simply re-run the failed jobs until they eventually succeed.

If for some reason you need to cancel the workflow or re-run it entirely, go
first to the [Release
page](https://github.com/kata-containers/kata-containers/releases) and delete
the draft release from the previous run.

### Unlock the `main` branch

After the release process has concluded, either unlock the `main` branch, or ask
an admin to do it.

### Improve the release notes

Release notes are auto-generated by the GitHub CLI tool used as part of our
release workflow.  However, some manual tweaking may still be necessary in order
to highlight the most important features and bug fixes in a specific release.

With this in mind, please, poke @channel on #kata-dev and people who worked on
the release will be able to contribute to that.

### Announce the release

Publish in [Slack and Kata mailing
list](https://github.com/kata-containers/community#join-us) that new release is
ready.
