#!/usr/bin/env bash

set -Eeuo pipefail

IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"

CATALOG_IMAGE="micros-02/catalog-service:${IMAGE_VERSION}"
PRICING_IMAGE="micros-02/pricing-service:${IMAGE_VERSION}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

CATALOG_DOCKERFILE="${REPOSITORY_ROOT}/src/CatalogService/CatalogService.Api/Dockerfile"
PRICING_DOCKERFILE="${REPOSITORY_ROOT}/src/PricingService/PricingService.Api/Dockerfile"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

assert_file_exists() {
  local file_path="$1"

  if [[ ! -f "${file_path}" ]]; then
    echo "Required file was not found:" >&2
    echo "${file_path}" >&2
    exit 1
  fi
}

require_command docker

assert_file_exists "${CATALOG_DOCKERFILE}"
assert_file_exists "${PRICING_DOCKERFILE}"

echo "Checking Docker..."

docker info >/dev/null

echo
echo "Building Catalog Service image:"
echo "${CATALOG_IMAGE}"

docker build \
  --file "${CATALOG_DOCKERFILE}" \
  --tag "${CATALOG_IMAGE}" \
  "${REPOSITORY_ROOT}"

echo
echo "Building Pricing Service image:"
echo "${PRICING_IMAGE}"

docker build \
  --file "${PRICING_DOCKERFILE}" \
  --tag "${PRICING_IMAGE}" \
  "${REPOSITORY_ROOT}"

echo
echo "Built images:"

docker image ls \
  --filter "reference=micros-02/catalog-service:${IMAGE_VERSION}" \
  --filter "reference=micros-02/pricing-service:${IMAGE_VERSION}"

echo
echo "Docker images were built successfully."