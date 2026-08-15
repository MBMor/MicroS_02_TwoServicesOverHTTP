#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

DATABASE_DIRECTORY="$(
  cd -- \
    "${REPOSITORY_ROOT}/deploy/kubernetes/base/catalog-service-db" \
    >/dev/null 2>&1
  pwd
)"

SERVICE_MANIFEST="${DATABASE_DIRECTORY}/service.yaml"
STATEFULSET_MANIFEST="${DATABASE_DIRECTORY}/statefulset.yaml"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_file() {
  local file_path="$1"

  if [[ ! -f "${file_path}" ]]; then
    echo "Required manifest was not found:" >&2
    echo "${file_path}" >&2
    exit 1
  fi
}

require_command minikube
require_command kubectl

require_file "${SERVICE_MANIFEST}"
require_file "${STATEFULSET_MANIFEST}"

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  echo "Run ./scripts/kubernetes/start-cluster.sh first." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

if ! kubectl get namespace \
  "${NAMESPACE}" \
  >/dev/null 2>&1; then
  echo "Namespace '${NAMESPACE}' does not exist." >&2
  exit 1
fi

if ! kubectl get secret \
  catalog-database-secret \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then
  echo "Secret 'catalog-database-secret' does not exist." >&2
  echo "Run ./scripts/kubernetes/apply-secrets.sh first." >&2
  exit 1
fi

default_storage_class="$(
  kubectl get storageclass \
    -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{end}' |
    tr -d '[:space:]'
)"

if [[ -z "${default_storage_class}" ]]; then
  echo "No default Kubernetes StorageClass was found." >&2
  echo "Check: kubectl get storageclass" >&2
  exit 1
fi

echo "Using default StorageClass '${default_storage_class}'."

echo
echo "Applying Catalog PostgreSQL Services..."

kubectl apply \
  -f "${SERVICE_MANIFEST}"

echo
echo "Applying Catalog PostgreSQL StatefulSet..."

kubectl apply \
  -f "${STATEFULSET_MANIFEST}"

echo
echo "Waiting for StatefulSet rollout..."

kubectl rollout status \
  statefulset/catalog-service-db \
  --namespace "${NAMESPACE}" \
  --timeout "${ROLLOUT_TIMEOUT}"

echo
echo "Waiting for Catalog PostgreSQL Pod readiness..."

kubectl wait \
  --for=condition=Ready \
  pod \
  --selector='app.kubernetes.io/name=catalog-service-db,app.kubernetes.io/component=database' \
  --namespace "${NAMESPACE}" \
  --timeout "${ROLLOUT_TIMEOUT}"

echo
echo "Catalog PostgreSQL resources:"

kubectl get \
  statefulset,pod,service,persistentvolumeclaim \
  --namespace "${NAMESPACE}" \
  --selector='app.kubernetes.io/name=catalog-service-db' \
  -o wide

echo
echo "Catalog PostgreSQL was deployed successfully."