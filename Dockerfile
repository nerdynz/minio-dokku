FROM golang:1.22-alpine AS build

ARG TARGETARCH="amd64"
ARG MINIO_VERSION="RELEASE.2024-11-07T00-52-20Z"

ENV GOPATH=/go
ENV CGO_ENABLED=0

WORKDIR /build

# Install curl and minisign
RUN apk add -U --no-cache ca-certificates && \
    apk add -U --no-cache curl && \
    apk add -U --no-cache bash && \
    go install aead.dev/minisign/cmd/minisign@v0.2.1

# Download minio binary and signature files
RUN curl -s -q https://dl.min.io/server/minio/release/linux-${TARGETARCH}/archive/minio.${MINIO_VERSION} -o /go/bin/minio && \
    curl -s -q https://dl.min.io/server/minio/release/linux-${TARGETARCH}/archive/minio.${MINIO_VERSION}.minisig -o /go/bin/minio.minisig && \
    curl -s -q https://dl.min.io/server/minio/release/linux-${TARGETARCH}/archive/minio.${MINIO_VERSION}.sha256sum -o /go/bin/minio.sha256sum && \
    chmod +x /go/bin/minio

# Download mc binary and signature files
RUN curl -s -q https://dl.min.io/client/mc/release/linux-${TARGETARCH}/mc -o /go/bin/mc && \
    curl -s -q https://dl.min.io/client/mc/release/linux-${TARGETARCH}/mc.minisig -o /go/bin/mc.minisig && \
    curl -s -q https://dl.min.io/client/mc/release/linux-${TARGETARCH}/mc.sha256sum -o /go/bin/mc.sha256sum && \
    chmod +x /go/bin/mc

RUN curl -s -q https://raw.githubusercontent.com/minio/minio/${MINIO_VERSION}/dockerscripts/docker-entrypoint.sh -o /docker-entrypoint.sh
RUN curl -s -q https://raw.githubusercontent.com/minio/minio/${MINIO_VERSION}/dockerscripts/download-static-curl.sh -o /download-static-curl.sh

RUN curl -s -q https://raw.githubusercontent.com/minio/minio/${MINIO_VERSION}/CREDITS -o /CREDITS && \
    curl -s -q https://raw.githubusercontent.com/minio/minio/${MINIO_VERSION}/LICENSE -o /LICENSE

# Verify binary signature using public key "RWTx5Zr1tiHQLwG9keckT0c45M3AGeHD6IvimQHpyRywVWGbP1aVSGavRUN"
RUN minisign -Vqm /go/bin/minio -x /go/bin/minio.minisig -P RWTx5Zr1tiHQLwG9keckT0c45M3AGeHD6IvimQHpyRywVWGbP1aVSGav && \
    minisign -Vqm /go/bin/mc -x /go/bin/mc.minisig -P RWTx5Zr1tiHQLwG9keckT0c45M3AGeHD6IvimQHpyRywVWGbP1aVSGav

RUN chmod +x /download-static-curl.sh && /download-static-curl.sh

FROM registry.access.redhat.com/ubi9/ubi-micro:latest

ARG MINIO_VERSION="RELEASE.2024-11-07T00-52-20Z"

LABEL name="MinIO" \
      vendor="MinIO Inc <dev@min.io>" \
      maintainer="MinIO Inc <dev@min.io>" \
      version="${MINIO_VERSION}" \
      release="${MINIO_VERSION}" \
      summary="MinIO is a High Performance Object Storage, API compatible with Amazon S3 cloud storage service." \
      description="MinIO object storage is fundamentally different. Designed for performance and the S3 API, it is 100% open-source. MinIO is ideal for large, private cloud environments with stringent security requirements and delivers mission-critical availability across a diverse range of workloads."

ENV MINIO_ACCESS_KEY_FILE=access_key \
    MINIO_SECRET_KEY_FILE=secret_key \
    MINIO_ROOT_USER_FILE=access_key \
    MINIO_ROOT_PASSWORD_FILE=secret_key \
    MINIO_KMS_SECRET_KEY_FILE=kms_master_key \
    MINIO_UPDATE_MINISIGN_PUBKEY="RWTx5Zr1tiHQLwG9keckT0c45M3AGeHD6IvimQHpyRywVWGbP1aVSGav" \
    MINIO_CONFIG_ENV_FILE=config.env \
    MC_CONFIG_DIR=/tmp/.mc

RUN chmod -R 777 /usr/bin

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /go/bin/minio* /usr/bin/
COPY --from=build /go/bin/mc* /usr/bin/
COPY --from=build /go/bin/curl* /usr/bin/

COPY --from=build /docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
RUN chmod +x /usr/bin/docker-entrypoint.sh

RUN mkdir -p /licenses
COPY --from=build /CREDITS /licenses/CREDITS
COPY --from=build /LICENSE /licenses/LICENSE

ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]

# Run the server and point to the created directory
CMD ["server", "--address", ":5000", "--console-address", ":9001", "/data"]