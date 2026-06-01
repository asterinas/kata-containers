#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
containerd_pid_file=/tmp/containerd.pid
syslogd_pid_file=/tmp/syslogd.pid
# shellcheck source=tools/kata/common.sh
source "${script_dir}/common.sh"
# shellcheck source=tools/kata/kata_config.sh
source "${script_dir}/kata_config.sh"

show_help() {
  cat <<'EOF'
Usage: bash tools/kata/kata_services.sh <start|stop|status>

Manages the background Kata smoke-test services.

Commands:
  start   Starts the background services using already-installed configs.
  stop    Stops the background services if they are running.
  status  Prints whether the managed services are running.

Environment:
  KATA_CONFIG_FILE          Optional Bash config fragment. Default:
                            tools/kata/config/smoke-test.env.
  KATA_TEST_NETWORK_NAME    Managed nerdctl network name.
  KATA_TEST_NETWORK_SUBNET  Managed nerdctl network subnet.
  KATA_TEST_NETWORK_GATEWAY Managed nerdctl network gateway.
EOF
}

run_optional_host_prerequisite() {
  "$@" >/dev/null 2>&1 || true
}

prepare_host_prerequisites() {
  run_optional_host_prerequisite modprobe overlay
  run_optional_host_prerequisite modprobe br_netfilter
  run_optional_host_prerequisite sysctl -w net.ipv4.ip_forward=1
  if [ -e /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
    run_optional_host_prerequisite sysctl -w net.bridge.bridge-nf-call-iptables=1
  fi
  iptables -P FORWARD ACCEPT
}

should_manage_test_network() {
  [ -n "${KATA_TEST_NETWORK_NAME:-}" ] &&
    [ "${KATA_TEST_NET:-}" = "${KATA_TEST_NETWORK_NAME}" ]
}

ensure_test_network() {
  local network_name="${KATA_TEST_NETWORK_NAME:-}"
  local network_subnet="${KATA_TEST_NETWORK_SUBNET:-}"
  local network_gateway="${KATA_TEST_NETWORK_GATEWAY:-}"

  if ! should_manage_test_network; then
    return 0
  fi

  if nerdctl --address "${CONTAINERD_ADDRESS}" network inspect "${network_name}" >/dev/null 2>&1; then
    echo "Kata test network ${network_name} already exists."
    return 0
  fi

  if [ -z "${network_subnet}" ] || [ -z "${network_gateway}" ]; then
    echo "KATA_TEST_NETWORK_SUBNET and KATA_TEST_NETWORK_GATEWAY are required to create ${network_name}." >&2
    return 1
  fi

  nerdctl --address "${CONTAINERD_ADDRESS}" network create \
    --subnet "${network_subnet}" \
    --gateway "${network_gateway}" \
    "${network_name}"
}

wait_for_socket() {
  local socket_path="$1"
  local service_name="$2"
  local timeout_seconds="$3"

  if timeout "${timeout_seconds}" bash -c '
    socket_path="$1"
    until [ -S "${socket_path}" ]; do
      sleep 1
    done
  ' bash "${socket_path}"; then
    return 0
  fi

  echo "Timed out waiting for ${service_name} socket: ${socket_path}" >&2
  return 1
}

print_log_tail() {
  local log_file="$1"

  if [ ! -f "${log_file}" ]; then
    return 0
  fi

  echo "--- ${log_file} ---" >&2
  tail -40 "${log_file}" >&2 || true
}

read_pid_file() {
  local pid_file="$1"
  local process_id

  if [ ! -f "${pid_file}" ]; then
    return 1
  fi

  process_id="$(cat "${pid_file}")"
  case "${process_id}" in
    '' | *[!0-9]*)
      return 1
      ;;
  esac

  printf '%s\n' "${process_id}"
}

pid_is_running() {
  local process_id="$1"

  kill -0 "${process_id}" 2>/dev/null
}

cleanup_pid_file() {
  local pid_file="$1"
  local process_id

  if ! process_id="$(read_pid_file "${pid_file}")"; then
    rm -f "${pid_file}"
    return 1
  fi

  if ! pid_is_running "${process_id}"; then
    rm -f "${pid_file}"
    return 1
  fi

  return 0
}

service_is_running() {
  local pid_file="$1"

  cleanup_pid_file "${pid_file}" >/dev/null 2>&1
}

print_status() {
  local service_name="$1"
  local pid_file="$2"
  local expected_socket="${3:-}"
  local process_id='-'
  local state="stopped"

  if service_is_running "${pid_file}"; then
    process_id="$(cat "${pid_file}")"
    state="running"
  fi

  if [ -n "${expected_socket}" ] && [ ! -S "${expected_socket}" ] && [ "${state}" = "running" ]; then
    state="degraded"
  fi

  printf '%s: %s (pid: %s)\n' "${service_name}" "${state}" "${process_id}"
  if [ -n "${expected_socket}" ]; then
    if [ -S "${expected_socket}" ]; then
      printf '  socket: %s (ready)\n' "${expected_socket}"
    else
      printf '  socket: %s (missing)\n' "${expected_socket}"
    fi
  fi
}

services_are_fully_running() {
  service_is_running "${syslogd_pid_file}" &&
    service_is_running "${containerd_pid_file}" &&
    [ -S /dev/log ] &&
    [ -S "${CONTAINERD_ADDRESS}" ]
}

stop_service_from_pid_file() {
  local pid_file="$1"
  local service_name="$2"
  local process_id

  if ! process_id="$(read_pid_file "${pid_file}")"; then
    rm -f "${pid_file}"
    echo "${service_name} is not running."
    return 0
  fi

  if ! pid_is_running "${process_id}"; then
    rm -f "${pid_file}"
    echo "${service_name} is not running."
    return 0
  fi

  kill "${process_id}" 2>/dev/null || true
  wait_for_exit "${process_id}"
  rm -f "${pid_file}"
  echo "Stopped ${service_name}."
}

stop_services() {
  stop_service_from_pid_file "${containerd_pid_file}" "containerd"
  stop_service_from_pid_file "${syslogd_pid_file}" "syslogd"
}

start_services() {
  if services_are_fully_running; then
    echo "Kata services are already running."
    ensure_test_network
    return 0
  fi

  if service_is_running "${syslogd_pid_file}" || service_is_running "${containerd_pid_file}"; then
    echo "Kata services are partially running; restarting them."
    stop_services
  fi

  kata_require_installed_configs
  install -d -m 0755 /run/containerd /var/lib/containerd
  prepare_host_prerequisites

  rm -f /dev/log /tmp/containerd.log /tmp/kata-syslog.log /tmp/kata-console.log /tmp/kata-qemu-serial.log /tmp/console.log /tmp/qemu-serial.log

  nohup syslogd -n -O /tmp/kata-syslog.log >/tmp/kata-syslog.stdout 2>&1 &
  echo $! > "${syslogd_pid_file}"

  if ! wait_for_socket /dev/log syslogd 10; then
    print_log_tail /tmp/kata-syslog.stdout
    return 1
  fi

  nohup containerd --config /etc/containerd/config.toml --log-level debug >/tmp/containerd.log 2>&1 &
  echo $! > "${containerd_pid_file}"

  if ! wait_for_socket "${CONTAINERD_ADDRESS}" containerd 30; then
    print_log_tail /tmp/containerd.log
    return 1
  fi

  ensure_test_network

  echo "Started Kata services."
}

status_services() {
  print_status "syslogd" "${syslogd_pid_file}" /dev/log
  print_status "containerd" "${containerd_pid_file}" "${CONTAINERD_ADDRESS:-/run/containerd/containerd.sock}"
  if should_manage_test_network &&
    nerdctl --address "${CONTAINERD_ADDRESS}" network inspect "${KATA_TEST_NETWORK_NAME}" >/dev/null 2>&1; then
    printf 'nerdctl network: %s (ready)\n' "${KATA_TEST_NETWORK_NAME}"
  elif should_manage_test_network; then
    printf 'nerdctl network: %s (missing)\n' "${KATA_TEST_NETWORK_NAME}"
  fi

  if services_are_fully_running; then
    echo "Kata services are running."
    return 0
  fi

  echo "Kata services are not fully running."
  return 1
}

main() {
  local action="${1:-}"

  case "${action}" in
    -h | --help)
      show_help
      exit 0
      ;;
    start | stop | status)
      ;;
    '')
      echo "Missing command." >&2
      echo >&2
      show_help >&2
      exit 1
      ;;
    *)
      echo "Unsupported command: ${action}" >&2
      echo >&2
      show_help >&2
      exit 1
      ;;
  esac

  if [ "$#" -ne 1 ]; then
    echo "Unexpected arguments: ${*:2}" >&2
    echo >&2
    show_help >&2
    exit 1
  fi

  case "${action}" in
    start)
      kata_load_config "${script_dir}/config/smoke-test.env"
      start_services
      ;;
    stop)
      stop_services
      ;;
    status)
      kata_load_config "${script_dir}/config/smoke-test.env"
      status_services
      ;;
  esac
}

main "$@"
