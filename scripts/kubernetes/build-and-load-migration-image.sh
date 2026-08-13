#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"

IMAGE_NAME="micros-02/ef-migrations:${IMAGE_VERSION}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

DOCKERFILE="$(
  cd -- "${REPOSITORY_ROOT}/deploy/kubernetes/migrations" >/dev/null 2>&1
  pwd
)/Dockerfile"

if ! command -v docker >/dev/null 2>&1; then
  echo "Required command 'docker' was not found." >&2
  exit 1
fi

if ! command -v minikube >/dev/null 2>&1; then
  echo "Required command 'minikube' was not found." >&2
  exit 1
fi

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

echo "Building migration image:"
echo "${IMAGE_NAME}"

docker build \
  --file "${DOCKERFILE}" \
  --tag "${IMAGE_NAME}" \
  "${REPOSITORY_ROOT}"

echo
echo "Loading migration image into Minikube..."

minikube image load \
  "${IMAGE_NAME}" \
  --profile="${PROFILE_NAME}" \
  --daemon \
  --overwrite

echo
echo "Verifying migration image..."

if ! minikube image ls \
  --profile "${PROFILE_NAME}" |
  grep -Fq "${IMAGE_NAME}"; then
  echo "Migration image was not found in Minikube." >&2
  exit 1
fi

echo
echo "Migration image '${IMAGE_NAME}' is ready."