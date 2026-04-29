Kata helpers live here.

- `common.sh`: shared shell helpers used by the other Kata scripts
- `run_kata.sh`: provides predefined `smoke`, `pass`, and `workload` Kata tasks
- `kata_env.sh`: provides `install` and `check` for the shared Kata environment lifecycle, including repo-owned config installation
- `kata_services.sh`: provides `start`, `stop`, and `status` for the background Kata smoke-test services
- `interactive_doc_test.py`: replays the documented `docker run -it` and
  inner `nerdctl run -it` flows with `pexpect` for both the `asterinas/kata`
  and `asterinas/asterinas` images
- `check_overlayfs.sh`: probes whether the current host-side backing filesystem
  can support overlayfs `upperdir` and `workdir` for local Kata runs
- `asterinas_metadata.sh`: loads pinned Asterinas metadata for non-upstream
  repositories, resolves live metadata from `asterinas/asterinas`, or refreshes
  the repo-owned metadata file
- `config/`: repo-owned Kata, CNI, `containerd`, and smoke-test config files used by the scripts

## Configuration

- Default smoke-test settings live in `tools/kata/config/smoke-test.env`.
- `bash tools/kata/kata_env.sh install` installs the repo-owned Kata,
  `containerd`, and CNI config files into `/etc`; `kata_services.sh start`
  only validates those files and starts the background services.
- To install the config with a specific guest kernel path, use
  `bash tools/kata/kata_env.sh install --kernel /path/to/kernel`. Without this
  option, the script keeps the current guest kernel selection logic.
- Pinned Asterinas source/image metadata lives in
  `tools/kata/config/asterinas-metadata.env`.
- Refresh that metadata with `bash tools/kata/asterinas_metadata.sh update`.
- Load that metadata with `bash tools/kata/asterinas_metadata.sh load`.
- By default, `bash tools/kata/kata_env.sh install` resolves the latest
  Kata static tarball with Asterinas as the guest kernel from
  `asterinas/kata-containers`.
- Repository workflows override `KATA_STATIC_TARBALL_RELEASE_REPO` to the
  current GitHub repository so pull requests in a fork can validate that
  repository's latest Kata release with Asterinas as the guest kernel assets.
- Override a value ad hoc with environment variables, for example:
  `KATA_TEST_IMAGE=docker.io/library/ubuntu:24.04 bash tools/kata/run_kata.sh smoke`
- Pin a specific tarball explicitly with `KATA_STATIC_TARBALL_URL=...` when you
  do not want the latest release.
- Force the Linux guest kernel from a multi-kernel Kata release with
  `KATA_GUEST_KERNEL=linux`.
- Or point `KATA_CONFIG_FILE` at another Bash config fragment.
- Legacy `KATA_ALPINE_*` overrides still map to the new `KATA_TEST_*` names.
- The default workload still pulls Alpine and runs `cat /etc/alpine-release`, but
  the image, in-container command, and output check are now script-configurable.
- `interactive_doc_test.py` uses `KATA_DOC_TEST_WORKLOAD_IMAGE`, which defaults
  to `docker.io/alpine:latest`. For local validation in environments where
  Docker Hub is unreachable, you can temporarily switch it to
  `docker.1ms.run/alpine:latest`.

## Asterinas metadata selection

- Workflows should resolve metadata with
  `bash tools/kata/asterinas_metadata.sh resolve` instead of loading the pinned
  file directly.
- `tools/kata/config/asterinas-metadata.env` acts as both the selector and the
  pinned fallback. Keep it pointed at `jjf-dev/asterinas` until
  `asterinas/asterinas:main` is ready for Kata CI.
- When `ASTERINAS_REPOSITORY` is exactly `asterinas/asterinas`, `resolve` reads
  live metadata from GitHub at `ASTERINAS_REF`, including the commit SHA,
  commit date, `VERSION`, and `DOCKER_IMAGE_VERSION`.
- When `ASTERINAS_REPOSITORY` points to any other Asterinas repository, `resolve`
  uses the pinned commit/version/image values from
  `tools/kata/config/asterinas-metadata.env`. This avoids cross-organization
  `gh` access problems for repositories such as `jjf-dev/asterinas`.
- The workflow summaries include `asterinas_metadata_source`, which is
  `upstream` for live `asterinas/asterinas` metadata and `file` for pinned
  metadata.

## Scheduled Asterinas workflows

- The Asterinas workflows keep their existing manual and push triggers. The
  scheduled triggers only add daily background runs.
- `Publish | Kata Image with Asterinas as the Guest Kernel` runs daily at
  `01:10 UTC`. On scheduled runs, it builds and publishes only when metadata
  comes from `asterinas/asterinas` and the target `asterinas/kata:<version>` tag
  does not already exist.
- `Release | Kata Bundle with Asterinas as the Guest Kernel` runs daily at
  `03:10 UTC`. On scheduled runs, it builds and publishes only when metadata
  comes from `asterinas/asterinas` and no existing release records the current
  `DOCKER_IMAGE_VERSION`.
- `Test | Kata with Asterinas as the Guest Kernel` runs daily at `05:10 UTC`.
  Scheduled runs are unconditional and always execute the test matrix.
- `Test | Documentation Flow for Kata with Asterinas as the Guest Kernel` runs
  daily at `07:10 UTC`. Scheduled runs are unconditional and always execute the
  documented flows.
- While `tools/kata/config/asterinas-metadata.env` points at
  `jjf-dev/asterinas`, scheduled publish and release runs stop at their gate
  jobs. After switching to `asterinas/asterinas`, the same gates detect new
  upstream versions and continue only when publication is needed.

## Asterinas workflow dependencies

- The Asterinas workflows are intentionally not serialized at the workflow
  level. Metadata checks, source-kernel smoke tests, release packaging, image
  publishing, and documentation replay all start from the same push so
  independent work can run in parallel.
- Consumers of release artifacts use readiness checks instead of a global
  workflow dependency. On push events, jobs that need the current Asterinas Kata
  tarball set `KATA_STATIC_TARBALL_EXPECTED_KATA_COMMIT`; `kata_env.sh` and
  `resolve_release_assets.sh` then wait for the latest release notes to
  advertise that commit before using the tarball. Jobs without that expected
  commit, such as the Linux guest smoke-test matrix member, keep using the
  latest available release immediately.
- The published-image documentation flow uses the same pattern for Docker Hub:
  it pulls `asterinas/kata:<DOCKER_IMAGE_VERSION>` and validates the image
  layout before replaying the end-user flow. If the tag still points at an older
  image, it waits and pulls again instead of failing or forcing the whole docs
  workflow to wait behind image publication every time.
- The release workflow updates an existing same-day release tag on push. This
  lets a later push replace the static tarball for the same dated tag, and the
  artifact readiness checks above prevent dependent jobs from consuming the
  previous push's tarball.
- `Test | Kata with Asterinas as the Guest Kernel` still runs its Linux guest
  matrix member independently; only the Asterinas guest setup needs the
  Asterinas-flavoured static tarball. Keeping this as a consumer-side gate
  avoids blocking unrelated checks when no new release artifact is required.

## Local virtio-fs note

- The local `bash tools/kata/run_kata.sh smoke` flow now uses `virtio-fs`.
- In the current dev container, `/dev/shm` is only `64M`, which is too small
  for Kata's default shared guest memory backend when the VM memory is `2048M`.
- The repo-owned Kata drop-in therefore sets `file_mem_backend = "/tmp"` so
  `virtio-fs` local runs do not fail during early VM boot.
- If local `virtio-fs` bring-up fails again, check both:
  - the outer container flags (`--privileged --cgroupns=host`)
  - the available space of the configured file-backed memory directory
- If you want to use host-side overlayfs rootfs staging, run
  `bash tools/kata/check_overlayfs.sh` first to verify that the current backing
  filesystem can host overlay `upperdir` and `workdir`.
