#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"

if ! command -v minikube >/dev/null 2>&1; then
  echo "Required command 'minikube' was not found in PATH." >&2
  exit 1
fi

echo "This will delete Minikube profile '${PROFILE_NAME}'"
echo "including all workloads and cluster data."
echo

read -r -p "Type 'delete' to continue: " confirmation

if [[ "${confirmation}" != "delete" ]]; then
  echo "Deletion cancelled."
  exit 0
fi

minikube delete --profile "${PROFILE_NAME}"

echo "Minikube profile '${PROFILE_NAME}' was deleted."