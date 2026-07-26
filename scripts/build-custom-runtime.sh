#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <order|user>" >&2
  exit 2
fi

service="$1"
case "$service" in
  order|user)
    ;;
  *)
    echo "unsupported service: $service" >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_root="$repo_root/dist"
service_output="$output_root/$service"
archive="$output_root/$service.zip"
version="${VERSION:-dev}"
commit_sha="${COMMIT_SHA:-$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unknown)}"
build_time="${BUILD_TIME:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
target_arch="${TARGET_ARCH:-amd64}"

rm -rf "$service_output"
rm -f "$archive"
mkdir -p "$service_output"

CGO_ENABLED=0 GOOS=linux GOARCH="$target_arch" go build \
  -trimpath \
  -ldflags "-s -w -X github.com/isrina129/go-demo/internal/webapp.Version=$version -X github.com/isrina129/go-demo/internal/webapp.CommitSHA=$commit_sha -X github.com/isrina129/go-demo/internal/webapp.BuildTime=$build_time" \
  -o "$service_output/bootstrap" \
  "$repo_root/services/$service"

chmod +x "$service_output/bootstrap"
(
  cd "$service_output"
  zip -q "$archive" bootstrap
)

echo "$archive"

