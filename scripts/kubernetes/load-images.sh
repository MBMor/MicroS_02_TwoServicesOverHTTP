#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"

CATALOG_IMAGE="micros-02/catalog-service:${IMAGE_VERSION}"
PRICING_IMAGE="micros-02/pricing-service:${IMAGE_VERSION}"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

assert_local_image_exists() {
  local image_name="$1"

  if ! docker image inspect "${image_name}" >/dev/null 2>&1; then
    echo "Local Docker image was not found:" >&2
    echo "${image_name}" >&2
    echo "Run ./scripts/kubernetes/build-images.sh first." >&2
    exit 1
  fi
}

require_command docker
require_command minikube

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  echo "Run ./scripts/kubernetes/start-cluster.sh first." >&2
  exit 1
fi

assert_local_image_exists "${CATALOG_IMAGE}"
assert_local_image_exists "${PRICING_IMAGE}"

echo "Loading Catalog Service image into Minikube..."

minikube image load \
  "${CATALOG_IMAGE}" \
  --profile="${PROFILE_NAME}" \
  --daemon

echo
echo "Loading Pricing Service image into Minikube..."

minikube image load \
  "${PRICING_IMAGE}" \
  --profile="${PROFILE_NAME}" \
  --daemon

echo
echo "Application images available in Minikube:"

minikube image ls \
  --profile="${PROFILE_NAME}" |
  grep 'micros-02/' |
  sort

echo
echo "Images were loaded successfully."