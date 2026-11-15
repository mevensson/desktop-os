# Universal Blue image-template pattern: mount build files without shipping them.
ARG BASE_IMAGE
FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files

FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG BASE_DIGEST
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx,ro \
    --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    /bin/bash /ctx/build_files/build.sh

# Release-specific inputs come after package work so new identities can reuse it.
COPY --from=release release.json /usr/share/desktop-os/release.json
ARG RELEASE_ID
ARG SOURCE_URL
ARG SOURCE_REVISION
ARG RELEASE_CREATED
ARG BUILD_KIND
ARG RUN_ID
ARG RUN_ATTEMPT
ARG RUN_NUMBER
ARG WORKFLOW_REF
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      org.opencontainers.image.version="${RELEASE_ID}" \
      org.opencontainers.image.created="${RELEASE_CREATED}" \
      io.github.mevensson.desktop-os.build-kind="${BUILD_KIND}" \
      io.github.mevensson.desktop-os.run-id="${RUN_ID}" \
      io.github.mevensson.desktop-os.run-attempt="${RUN_ATTEMPT}" \
      io.github.mevensson.desktop-os.run-number="${RUN_NUMBER}" \
      io.github.mevensson.desktop-os.workflow-ref="${WORKFLOW_REF}"

# Keep the exact selected base available from the deployed filesystem too.
RUN mkdir -p /usr/share/desktop-os && \
    printf '%s\n' "${BASE_IMAGE}" > /usr/share/desktop-os/base-image

RUN bootc container lint --fatal-warnings
