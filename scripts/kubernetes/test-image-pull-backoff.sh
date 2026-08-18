#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-pricing-service}"
BROKEN_IMAGE="${BROKEN_IMAGE:-micros-02/pricing-service:does-not-exist}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"

ORIGINAL_IMAGE=""
RESTORE_REQUIRED="false"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

cleanup() {
  local original_exit_code=$?

  set +e

  if [[ "${RESTORE_REQUIRED}" == "true" &&
        -n "${ORIGINAL_IMAGE}" ]]; then

    echo
    echo "Restoring original image '${ORIGINAL_IMAGE}'..."

    kubectl set image \
      deployment/"${TARGET_DEPLOYMENT}" \
      "${TARGET_DEPLOYMENT}=${ORIGINAL_IMAGE}" \
      --namespace "${NAMESPACE}" \
      >/dev/null 2>&1 || true

    kubectl rollout status \
      deployment/"${TARGET_DEPLOYMENT}" \
      --namespace "${NAMESPACE}" \
      --timeout=120s \
      >/dev/null 2>&1 || true
  fi

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

require_command minikube
require_command kubectl
require_command awk

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then

  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "============================================================"
echo "ImagePullBackOff failure test"
echo "============================================================"

echo
echo "1. Checking baseline Deployment..."

kubectl wait \
  --for=condition=Available \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

ORIGINAL_IMAGE="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
)"

echo "Original image: ${ORIGINAL_IMAGE}"
echo "Broken image:   ${BROKEN_IMAGE}"

RESTORE_REQUIRED="true"

echo
echo "2. Applying broken image..."

kubectl set image \
  deployment/"${TARGET_DEPLOYMENT}" \
  "${TARGET_DEPLOYMENT}=${BROKEN_IMAGE}" \
  --namespace "${NAMESPACE}"

echo
echo "3. Waiting for image pull failure..."

FAILED_POD=""
FAILURE_REASON=""

for ((attempt = 1; attempt <= TIMEOUT_SECONDS; attempt++)); do
  POD_STATUS="$(
    kubectl get pods \
      --namespace "${NAMESPACE}" \
      --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT},app.kubernetes.io/component=api" \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' \
      2>/dev/null || true
  )"

  FAILED_POD="$(
    printf '%s\n' "${POD_STATUS}" |
      awk '$2 == "ImagePullBackOff" || $2 == "ErrImagePull" { print $1; exit }'
  )"

  FAILURE_REASON="$(
    printf '%s\n' "${POD_STATUS}" |
      awk '$2 == "ImagePullBackOff" || $2 == "ErrImagePull" { print $2; exit }'
  )"

  if [[ -n "${FAILED_POD}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${FAILED_POD}" ]]; then
  echo "Expected image pull failure was not observed." >&2

  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT}" \
    -o wide \
    >&2

  exit 1
fi

echo "PASS: Pod '${FAILED_POD}' entered '${FAILURE_REASON}'."

echo
echo "4. Showing Pod events..."

kubectl describe pod \
  "${FAILED_POD}" \
  --namespace "${NAMESPACE}"

echo
echo "5. Restoring original image..."

kubectl set image \
  deployment/"${TARGET_DEPLOYMENT}" \
  "${TARGET_DEPLOYMENT}=${ORIGINAL_IMAGE}" \
  --namespace "${NAMESPACE}"

kubectl rollout status \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=120s

RESTORE_REQUIRED="false"

echo
echo "PASS: Deployment recovered successfully."

echo
echo "============================================================"
echo "IMAGE PULL FAILURE TEST PASSED."
echo "============================================================"