ARG ASTERINAS_BASE_IMAGE=asterinas/asterinas:0.17.2-20260407
FROM ${ASTERINAS_BASE_IMAGE}

ARG KATA_STATIC_TARBALL_RELEASE_REPO=kata-containers/kata-containers
ARG KATA_STATIC_TARBALL_URL=
ARG KATA_STATIC_TARBALL_SHA256=
ARG ASTERINAS_RELEASE_VERSION=
ARG ASTERINAS_DOCKER_IMAGE_VERSION=

WORKDIR /root/asterinas

COPY tools/kata /root/asterinas/tools/kata

RUN KATA_STATIC_TARBALL_RELEASE_REPO="${KATA_STATIC_TARBALL_RELEASE_REPO}" \
    KATA_STATIC_TARBALL_URL="${KATA_STATIC_TARBALL_URL}" \
    KATA_STATIC_TARBALL_SHA256="${KATA_STATIC_TARBALL_SHA256}" \
    bash /root/asterinas/tools/kata/kata_env.sh install

RUN printf '%s\n' "${ASTERINAS_RELEASE_VERSION}" > /root/asterinas/.asterinas-version && \
    printf '%s\n' "${ASTERINAS_DOCKER_IMAGE_VERSION}" > /root/asterinas/.asterinas-docker-image-version

RUN set -eux; \
    install -d -m 0755 /run/containerd /var/lib/containerd; \
    containerd \
      --address /run/containerd/containerd.sock \
      --root /var/lib/containerd \
      --state /run/containerd \
      >/tmp/containerd-prepull.log 2>&1 & \
    containerd_pid="$!"; \
    cleanup_containerd() { \
      kill "${containerd_pid}" 2>/dev/null || true; \
      wait "${containerd_pid}" 2>/dev/null || true; \
    }; \
    trap cleanup_containerd EXIT; \
    timeout 60 sh -c 'until [ -S /run/containerd/containerd.sock ]; do sleep 1; done'; \
    nerdctl --address /run/containerd/containerd.sock --snapshotter native pull --unpack=false docker.io/alpine:latest; \
    cleanup_containerd; \
    trap - EXIT; \
    rm -rf /run/containerd /tmp/containerd-prepull.log
