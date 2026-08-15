#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
DELETE_DATA="${DELETE_DATA:-false}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

delete_manifest() {
  local path="$1"

  if [[ -e "${path}" ]]; then
    kubectl delete \
      --namespace "${NAMESPACE}" \
      --ignore-not-found \
      -f "${path}"
  fi
}

require_command minikube
require_command kubectl

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "Removing application workloads..."

delete_manifest \
  "${REPOSITORY_ROOT}/deploy/kubernetes/base/catalog-service"

delete_manifest \
  "${REPOSITORY_ROOT}/deploy/kubernetes/base/pricing-service"

echo
echo "Removing migration Jobs..."

delete_manifest \
  "${REPOSITORY_ROOT}/deploy/kubernetes/base/migrations"

echo
echo "Removing database workloads..."

delete_manifest \
  "${REPOSITORY_ROOT}/deploy/kubernetes/base/catalog-service-db"

delete_manifest \
  "${REPOSITORY_ROOT}/deploy/kubernetes/base/pricing-service-db"

if [[ "${DELETE_DATA}" == "true" ]]; then
  echo
  echo "Deleting persistent database data..."

  kubectl delete persistentvolumeclaim \
    data-catalog-service-db-0 \
    data-pricing-service-db-0 \
    --namespace "${NAMESPACE}" \
    --ignore-not-found
else
  echo
  echo "PersistentVolumeClaims were preserved."
  echo
  echo "Current PVCs:"

  kubectl get persistentvolumeclaims \
    --namespace "${NAMESPACE}" \
    || true
fi

echo
echo "Kubernetes workloads were removed."