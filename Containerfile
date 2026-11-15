# Universal Blue image-template pattern: mount build files without shipping them.
ARG BASE_IMAGE
FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files

FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG BASE_DIGEST
LABEL org.opencontainers.image.source="https://github.com/mevensson/desktop-os" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx,ro \
    --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    /bin/bash /ctx/build_files/build.sh

# Keep the exact selected base available from the deployed filesystem too.
RUN mkdir -p /usr/share/desktop-os && \
    printf '%s\n' "${BASE_IMAGE}" > /usr/share/desktop-os/base-image

RUN bootc container lint --fatal-warnings
