#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

IMAGE_NAME="micros-02/catalog-service:${IMAGE_VERSION}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

SERVICE_DIRECTORY="$(
  cd -- \
    "${REPOSITORY_ROOT}/deploy/kubernetes/base/catalog-service" \
    >/dev/null 2>&1
  pwd
)"

CONFIGMAP_MANIFEST="${SERVICE_DIRECTORY}/configmap.yaml"
SERVICE_MANIFEST="${SERVICE_DIRECTORY}/service.yaml"
DEPLOYMENT_MANIFEST="${SERVICE_DIRECTORY}/deployment.yaml"

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
require_command grep

require_file "${CONFIGMAP_MANIFEST}"
require_file "${SERVICE_MANIFEST}"
require_file "${DEPLOYMENT_MANIFEST}"

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

if ! kubectl get secret \
  catalog-database-secret \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then
  echo "Secret 'catalog-database-secret' does not exist." >&2
  echo "Run ./scripts/kubernetes/apply-secrets.sh first." >&2
  exit 1
fi

if ! kubectl wait \
  --for=condition=Ready \
  pod/catalog-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout=30s \
  >/dev/null 2>&1; then
  echo "Catalog PostgreSQL Pod is not ready." >&2
  exit 1
fi

if ! kubectl wait \
  --for=condition=Available \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout=30s \
  >/dev/null 2>&1; then
  echo "Pricing Service Deployment is not available." >&2
  echo "Run ./scripts/kubernetes/deploy-pricing-service.sh first." >&2
  exit 1
fi

if ! kubectl get service \
  pricing-service \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then
  echo "Service 'pricing-service' does not exist." >&2
  exit 1
fi

if ! minikube image ls \
  --profile "${PROFILE_NAME}" |
  grep -Fq "${IMAGE_NAME}"; then
  echo "Application image is not available in Minikube:" >&2
  echo "${IMAGE_NAME}" >&2
  echo >&2
  echo "Run:" >&2
  echo "IMAGE_VERSION=${IMAGE_VERSION} ./scripts/kubernetes/build-and-load-images.sh" >&2
  exit 1
fi

echo "Using image '${IMAGE_NAME}'."

echo
echo "Applying Catalog Service ConfigMap..."

kubectl apply \
  -f "${CONFIGMAP_MANIFEST}"

echo
echo "Applying Catalog Service..."

kubectl apply \
  -f "${SERVICE_MANIFEST}" \
  -f "${DEPLOYMENT_MANIFEST}"

echo
echo "Waiting for Catalog Service rollout..."

kubectl rollout status \
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout="${ROLLOUT_TIMEOUT}"

echo
echo "Waiting for Catalog Service readiness..."

kubectl wait \
  --for=condition=Ready \
  pod \
  --selector='app.kubernetes.io/name=catalog-service,app.kubernetes.io/component=api' \
  --namespace "${NAMESPACE}" \
  --timeout="${ROLLOUT_TIMEOUT}"

echo
echo "Catalog Service resources:"

kubectl get \
  deployment,replicaset,pod,service,configmap \
  --namespace "${NAMESPACE}" \
  --selector='app.kubernetes.io/name=catalog-service' \
  -o wide

echo
echo "Catalog Service was deployed successfully."