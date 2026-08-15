#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
TARGET_SERVICE="${TARGET_SERVICE:-catalog-service}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-90}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_command minikube
require_command kubectl

case "${TARGET_SERVICE}" in
  catalog-service|pricing-service)
    ;;
  *)
    echo "Unsupported TARGET_SERVICE '${TARGET_SERVICE}'." >&2
    echo "Supported values:" >&2
    echo "  catalog-service" >&2
    echo "  pricing-service" >&2
    exit 1
    ;;
esac

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then

  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "Testing self-healing for '${TARGET_SERVICE}'..."
echo

kubectl wait \
  --for=condition=Available \
  deployment/"${TARGET_SERVICE}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

ORIGINAL_POD="$(
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_SERVICE},app.kubernetes.io/component=api" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${ORIGINAL_POD}" ]]; then
  echo "Could not find a running Pod for '${TARGET_SERVICE}'." >&2
  exit 1
fi

echo "Original Pod: ${ORIGINAL_POD}"

echo
echo "Deleting Pod..."

kubectl delete pod \
  "${ORIGINAL_POD}" \
  --namespace "${NAMESPACE}"

echo
echo "Waiting for replacement Pod..."

NEW_POD=""

for ((attempt = 1; attempt <= TIMEOUT_SECONDS; attempt++)); do
  NEW_POD="$(
    kubectl get pods \
      --namespace "${NAMESPACE}" \
      --selector="app.kubernetes.io/name=${TARGET_SERVICE},app.kubernetes.io/component=api" \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' |
      awk -v old="${ORIGINAL_POD}" \
        '$1 != old && $2 == "Running" { print $1; exit }'
  )"

  if [[ -n "${NEW_POD}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${NEW_POD}" ]]; then
  echo "Replacement Pod was not created within ${TIMEOUT_SECONDS} seconds." >&2

  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_SERVICE}" \
    -o wide \
    >&2

  exit 1
fi

echo "Replacement Pod: ${NEW_POD}"

if [[ "${NEW_POD}" == "${ORIGINAL_POD}" ]]; then
  echo "Replacement Pod has the same name as the original Pod." >&2
  exit 1
fi

echo
echo "Waiting for replacement Pod readiness..."

kubectl wait \
  --for=condition=Ready \
  pod/"${NEW_POD}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo
echo "Waiting for Deployment availability..."

kubectl wait \
  --for=condition=Available \
  deployment/"${TARGET_SERVICE}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo
echo "PASS: Kubernetes replaced '${ORIGINAL_POD}' with '${NEW_POD}'."

if [[ -x "${SCRIPT_DIRECTORY}/smoke-test.sh" ]]; then
  echo
  echo "Running Kubernetes smoke tests..."

  "${SCRIPT_DIRECTORY}/smoke-test.sh"
fi

echo
echo "Self-healing test completed successfully."