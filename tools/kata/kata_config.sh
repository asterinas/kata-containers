#!/usr/bin/env bash

# Shared Kata configuration installation helpers.

kata_config_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/config"

kata_select_config_source() {
  case "${KATA_GUEST_KERNEL:-}" in
    linux)
      if [ -f /opt/kata/share/defaults/kata-containers/configuration-qemu.toml ]; then
        echo /opt/kata/share/defaults/kata-containers/configuration-qemu.toml
        return
      fi

      cat >&2 <<'EOF'
Cannot find Kata's Linux guest configuration.
Expected:
  /opt/kata/share/defaults/kata-containers/configuration-qemu.toml

Run `bash tools/kata/kata_env.sh install` before starting Kata services.
EOF
      return 1
      ;;
    asterinas)
      if [ -f /opt/kata/share/defaults/kata-containers/configuration-asterinas.toml ]; then
        echo /opt/kata/share/defaults/kata-containers/configuration-asterinas.toml
        return
      fi

      cat >&2 <<'EOF'
Cannot find Kata's Asterinas guest configuration.
Expected:
  /opt/kata/share/defaults/kata-containers/configuration-asterinas.toml

Run `bash tools/kata/kata_env.sh install` before starting Kata services.
EOF
      return 1
      ;;
    '')
      ;;
    *)
      echo "Unsupported KATA_GUEST_KERNEL: ${KATA_GUEST_KERNEL}" >&2
      echo "Expected \`linux\`, \`asterinas\`, or empty." >&2
      return 1
      ;;
  esac

  if [ -f /opt/kata/share/defaults/kata-containers/configuration.toml ]; then
    echo /opt/kata/share/defaults/kata-containers/configuration.toml
    return
  fi

  if [ -f /opt/kata/share/defaults/kata-containers/configuration-qemu.toml ]; then
    echo /opt/kata/share/defaults/kata-containers/configuration-qemu.toml
    return
  fi

  cat >&2 <<'EOF'
Cannot find Kata's default configuration.
Expected one of:
  /opt/kata/share/defaults/kata-containers/configuration.toml
  /opt/kata/share/defaults/kata-containers/configuration-qemu.toml

Run `bash tools/kata/kata_env.sh install` before starting Kata services.
EOF
  return 1
}

kata_select_qemu_binary_path() {
  local qemu_candidate
  local qemu_candidates=(
    /opt/kata/bin/qemu-system-x86_64
    /usr/local/qemu/bin/qemu-system-x86_64
    /usr/bin/qemu-system-x86_64
    /usr/bin/qemu-kvm
    /usr/libexec/qemu-kvm
    /usr/lib/qemu/qemu-system-x86_64
  )

  if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    command -v qemu-system-x86_64
    return 0
  fi

  for qemu_candidate in "${qemu_candidates[@]}"; do
    if [ -x "${qemu_candidate}" ]; then
      printf '%s\n' "${qemu_candidate}"
      return 0
    fi
  done

  return 1
}

kata_normalize_qemu_config_path() {
  local kata_config_path="$1"
  local qemu_binary_path

  if ! qemu_binary_path="$(kata_select_qemu_binary_path)"; then
    echo "Cannot find a usable QEMU binary for Kata." >&2
    return 1
  fi

  sed -i \
    -e 's#^\(path = \)".*"#\1"'"${qemu_binary_path}"'"#' \
    -e 's#^\(valid_hypervisor_paths = \)\[.*\]#\1["'"${qemu_binary_path}"'"]#' \
    "${kata_config_path}"
}

kata_normalize_guest_artifact_paths() {
  local kata_config_path="$1"
  local packaged_initrd=/opt/kata/share/kata-containers/kata-containers-initrd.img

  if [ -f "${packaged_initrd}" ]; then
    sed -i \
      -e 's#^\([[:space:]]*initrd = \)".*"#\1"'"${packaged_initrd}"'"#' \
      "${kata_config_path}"
  fi
}

kata_normalize_debug_log_paths() {
  local kata_config_path="$1"

  sed -i \
    -e 's#/home/[^"]*/kata-asterinas/console\.log#/tmp/kata-console.log#g' \
    -e 's#/home/[^"]*/kata-asterinas/qemu-serial\.log#/tmp/kata-qemu-serial.log#g' \
    "${kata_config_path}"
}

kata_select_linux_guest_kernel_path() {
  local kernel_candidate
  local share_dir=/opt/kata/share/kata-containers

  for kernel_candidate in "${share_dir}"/vmlinux-[0-9]* "${share_dir}"/vmlinuz-[0-9]*; do
    if [ -f "${kernel_candidate}" ]; then
      printf '%s\n' "${kernel_candidate}"
      return 0
    fi
  done

  echo "Cannot find a Linux guest kernel under ${share_dir}." >&2
  return 1
}

kata_normalize_linux_guest_kernel_artifacts() {
  local kata_config_path="$1"
  local linux_kernel_path
  local share_dir=/opt/kata/share/kata-containers

  if [ "${KATA_GUEST_KERNEL:-}" != linux ]; then
    return 0
  fi

  linux_kernel_path="$(kata_select_linux_guest_kernel_path)"
  ln -sfn "$(basename "${linux_kernel_path}")" "${share_dir}/vmlinux.container"
  ln -sfn "$(basename "${linux_kernel_path}")" "${share_dir}/vmlinuz.container"
  sed -i \
    -e 's#^\([[:space:]]*kernel = \)".*"#\1"'"${share_dir}/vmlinux.container"'"#' \
    "${kata_config_path}"
}

kata_set_kernel_path() {
  local kata_config_path="$1"
  local kernel_path="$2"
  local escaped_kernel_path

  if [ -z "${kernel_path}" ]; then
    return 0
  fi

  if ! grep -Eq '^[[:space:]]*kernel = ".*"' "${kata_config_path}"; then
    echo "Cannot find a kernel setting in ${kata_config_path}." >&2
    return 1
  fi

  escaped_kernel_path="$(printf '%s\n' "${kernel_path}" | sed -e 's/[#&\\]/\\&/g')"
  sed -i \
    -e 's#^\([[:space:]]*kernel = \)".*"#\1"'"${escaped_kernel_path}"'"#' \
    "${kata_config_path}"
}

kata_install_repo_configs() {
  local kata_config_source
  local kernel_path="${1:-}"

  : "${PAUSE_IMAGE:?PAUSE_IMAGE must be set}"

  kata_config_source="$(kata_select_config_source)"

  install -d -m 0755 /etc/kata-containers
  rm -rf /etc/kata-containers/config.d
  install -d -m 0755 /etc/kata-containers/config.d
  install -m 0644 "${kata_config_source}" /etc/kata-containers/configuration.toml
  kata_normalize_qemu_config_path /etc/kata-containers/configuration.toml
  kata_normalize_linux_guest_kernel_artifacts /etc/kata-containers/configuration.toml
  kata_normalize_guest_artifact_paths /etc/kata-containers/configuration.toml
  kata_normalize_debug_log_paths /etc/kata-containers/configuration.toml
  kata_set_kernel_path /etc/kata-containers/configuration.toml "${kernel_path}"
  install -m 0644 "${kata_config_dir}/kata-10-container.toml" /etc/kata-containers/config.d/10-container.toml

  install -d -m 0755 /opt/cni /etc/cni/net.d /etc/containerd /run/containerd /var/lib/containerd
  if [ ! -e /opt/cni/bin ]; then
    ln -s /usr/lib/cni /opt/cni/bin
  fi
  install -m 0644 "${kata_config_dir}/cni-10-kata.conflist" /etc/cni/net.d/10-kata.conflist
  sed "s|__PAUSE_IMAGE__|${PAUSE_IMAGE}|g" "${kata_config_dir}/containerd-config.toml.in" > /etc/containerd/config.toml
}

kata_require_installed_configs() {
  local missing=0
  local required_path
  local required_paths=(
    /etc/kata-containers/configuration.toml
    /etc/kata-containers/config.d/10-container.toml
    /etc/cni/net.d/10-kata.conflist
    /etc/containerd/config.toml
  )

  for required_path in "${required_paths[@]}"; do
    if [ ! -f "${required_path}" ]; then
      echo "Missing required Kata configuration file: ${required_path}" >&2
      missing=1
    fi
  done

  if [ ! -e /opt/cni/bin ]; then
    echo "Missing required CNI plugin path: /opt/cni/bin" >&2
    missing=1
  fi

  if [ "${missing}" -ne 0 ]; then
    echo "Run \`bash tools/kata/kata_env.sh install\` before starting Kata services." >&2
    return 1
  fi
}
