# Comments are provided throughout this file to help you get started.
# If you need more help, visit the Dockerfile reference guide at
# https://docs.docker.com/go/dockerfile-reference/

# Use a specific Go version with Alpine for a small footprint and security.
ARG GO_VERSION=1.26.1-alpine3.23
FROM golang:${GO_VERSION} AS builder


# Set Go Proxy for faster dependency downloads (optional based on network environment).
ARG GOPROXY="https://goproxy.cn,direct"
ENV GOPROXY=${GOPROXY}

WORKDIR /workspace

# Leverage Docker layer caching by downloading dependencies first.
# These layers are only rebuilt if go.mod or go.sum changes.
COPY go.mod go.sum ./
RUN go mod download

# Copy the remaining source code after dependencies are fetched.
COPY . .

# These ARGs are automatically populated by Docker Buildx during multi-platform builds.
# Moving them close to the RUN command ensures maximum cache usage for earlier steps.
ARG TARGETOS
ARG TARGETARCH
ARG VERSION
ARG GITCOMMIT
ARG BRANCH
ARG BUILDDATE

# NOTICE: Quote values in ARG variables that contain commas, semicolons, or special characters.

# Build the binary:
# 1. CGO_ENABLED=0 creates a statically linked binary for maximum portability.
# 2. --trimpath removes local file system paths from the binary for reproducible builds.
# 3. -ldflags "-s -w" strips debug information to reduce binary size.
# 4. -X injects build-time metadata into the Go package variables.
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} \
              go build -trimpath -ldflags "-s -w \
              -X k8s.io/kube-state-metrics/v2/version.Version=${VERSION} \
              -X k8s.io/kube-state-metrics/v2/version.Revision=${GITCOMMIT} \
              -X k8s.io/kube-state-metrics/v2/version.Branch=${BRANCH} \
              -X k8s.io/kube-state-metrics/v2/version.BuildUser=${USER}@${HOST} \
              -X k8s.io/kube-state-metrics/v2/version.BuildDate=${BUILDDATE}" \
              -a -o kube-state-metrics cmd/main.go

# Use Google's distroless static image for a minimal attack surface.
# It contains only the binary and essential system files (no shell or package manager).
FROM gcr.io/distroless/static-debian12:latest

# Copy the compiled binary from the builder stage.
COPY --from=builder /workspace/kube-state-metrics /

# Use UID 65534 (nobody) for security compliance in restricted Kubernetes environments.
USER 65534:65534

# Standard ports for kube-state-metrics and its telemetry/metrics endpoint.
ENTRYPOINT ["/kube-state-metrics", "--port=8080", "--telemetry-port=8081"]

EXPOSE 8080 8081
