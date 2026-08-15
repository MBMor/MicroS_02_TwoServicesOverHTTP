#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
BUILD_IMAGES="${BUILD_IMAGES:-false}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

NAMESPACE_MANIFEST="${REPOSITORY_ROOT}/deploy/kubernetes/base/namespace.yaml"

PRICING_CONFIGMAP="$(
  cd -- \
    "${REPOSITORY_ROOT}/deploy/kubernetes/base/pricing-service" \
    >/dev/null 2>&1
  pwd
)/configmap.yaml"

CATALOG_CONFIGMAP="$(
  cd -- \
    "${REPOSITORY_ROOT}/deploy/kubernetes/base/catalog-service" \
    >/dev/null 2>&1
  pwd
)/configmap.yaml"

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
    echo "Required file was not found:" >&2
    echo "${file_path}" >&2
    exit 1
  fi
}

run_script() {
  local script_name="$1"

  local script_path="${SCRIPT_DIRECTORY}/${script_name}"

  require_file "${script_path}"

  echo
  echo "============================================================"
  echo "Running: ${script_name}"
  echo "============================================================"

  "${script_path}"
}

require_command docker
require_command minikube
require_command kubectl

require_file "${NAMESPACE_MANIFEST}"
require_file "${PRICING_CONFIGMAP}"
require_file "${CATALOG_CONFIGMAP}"

echo "Kubernetes QA Lab deployment"
echo "Profile:   ${PROFILE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  echo
  echo "Start it with:" >&2
  echo "./scripts/kubernetes/start-cluster.sh" >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "Applying namespace..."

kubectl apply \
  -f "${NAMESPACE_MANIFEST}"

kubectl config set-context \
  --current \
  --namespace="${NAMESPACE}" \
  >/dev/null

if [[ "${BUILD_IMAGES}" == "true" ]]; then
  run_script "build-and-load-images.sh"
  run_script "build-and-load-migration-image.sh"
else
  echo
  echo "Skipping image builds."
  echo "Set BUILD_IMAGES=true to rebuild and reload all images."
fi

run_script "apply-secrets.sh"

run_script "deploy-pricing-database.sh"
run_script "deploy-catalog-database.sh"

echo
echo "============================================================"
echo "Applying application ConfigMaps"
echo "============================================================"

kubectl apply \
  -f "${PRICING_CONFIGMAP}" \
  -f "${CATALOG_CONFIGMAP}"

run_script "run-migrations.sh"

run_script "deploy-pricing-service.sh"
run_script "deploy-catalog-service.sh"

run_script "wait-for-rollout.sh"

echo
echo "============================================================"
echo "Deployment summary"
echo "============================================================"

kubectl get deployments \
  --namespace "${NAMESPACE}"

echo

kubectl get statefulsets \
  --namespace "${NAMESPACE}"

echo

kubectl get pods \
  --namespace "${NAMESPACE}" \
  -o wide

echo

kubectl get services \
  --namespace "${NAMESPACE}"

echo

kubectl get jobs \
  --namespace "${NAMESPACE}"

echo

kubectl get persistentvolumeclaims \
  --namespace "${NAMESPACE}"

echo
echo "Kubernetes QA Lab deployment completed successfully."