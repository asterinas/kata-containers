Kata helpers live here.

- `common.sh`: shared shell helpers used by the other Kata scripts
- `run_kata.sh`: provides predefined `smoke`, `pass`, and `workload` Kata tasks
- `kata_env.sh`: provides `install` and `check` for the shared Kata environment lifecycle
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
- Pinned Asterinas source/image metadata lives in
  `tools/kata/config/asterinas-metadata.env`.
- Refresh that metadata with `bash tools/kata/asterinas_metadata.sh update`.
- Load that metadata with `bash tools/kata/asterinas_metadata.sh load`.
- By default, `bash tools/kata/kata_env.sh install` resolves the latest
  Kata static tarball with Asterinas as the guest kernel from `kata-containers/kata-containers`.
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
