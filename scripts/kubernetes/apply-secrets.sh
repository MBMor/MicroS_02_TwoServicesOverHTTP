#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

SECRETS_MANIFEST="${REPOSITORY_ROOT}/deploy/kubernetes/local/secrets.local.yaml"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_command minikube
require_command kubectl

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  echo "Run ./scripts/kubernetes/start-cluster.sh first." >&2
  exit 1
fi

if [[ ! -f "${SECRETS_MANIFEST}" ]]; then
  echo "Local Kubernetes secrets manifest was not found:" >&2
  echo "${SECRETS_MANIFEST}" >&2
  echo >&2
  echo "Create it from:" >&2
  echo "deploy/kubernetes/base/secrets.example.yaml" >&2
  exit 1
fi

if ! kubectl get namespace \
  "${NAMESPACE}" \
  >/dev/null 2>&1; then
  echo "Namespace '${NAMESPACE}' does not exist." >&2
  exit 1
fi

echo "Applying local Kubernetes secrets..."

kubectl apply \
  -f "${SECRETS_MANIFEST}"

echo
echo "Verifying required Secrets..."

required_secrets=(
  "catalog-database-secret"
  "pricing-database-secret"
)

for secret_name in "${required_secrets[@]}"; do
  if ! kubectl get secret \
    "${secret_name}" \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then
    echo "Secret '${secret_name}' was not created." >&2
    exit 1
  fi

  echo "Secret '${secret_name}' exists."
done

echo
echo "Secrets in namespace '${NAMESPACE}':"

kubectl get secrets \
  --namespace "${NAMESPACE}"

echo
echo "Local Kubernetes secrets were applied successfully."