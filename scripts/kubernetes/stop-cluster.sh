#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"

if ! command -v minikube >/dev/null 2>&1; then
  echo "Required command 'minikube' was not found in PATH." >&2
  exit 1
fi

echo "Stopping Minikube profile '${PROFILE_NAME}'..."

minikube stop --profile "${PROFILE_NAME}"

echo "Minikube profile '${PROFILE_NAME}' was stopped."