#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-pricing-service}"
TARGET_CONTAINER="${TARGET_CONTAINER:-pricing-service}"

BROKEN_IMAGE="${BROKEN_IMAGE:-micros-02/pricing-service:1.0.1}"
BROKEN_READINESS_PATH="${BROKEN_READINESS_PATH:-/health/does-not-exist}"

TEST_REPLICAS="${TEST_REPLICAS:-3}"
FAILURE_TIMEOUT="${FAILURE_TIMEOUT:-30s}"
RECOVERY_TIMEOUT="${RECOVERY_TIMEOUT:-120s}"

ORIGINAL_IMAGE=""
ORIGINAL_READINESS_PATH=""
ORIGINAL_REPLICAS=""
ORIGINAL_REVISION=""

ROLLBACK_REQUIRED="false"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

restore_replicas() {
  if [[ -z "${ORIGINAL_REPLICAS}" ]]; then
    return
  fi

  kubectl scale deployment \
    "${TARGET_DEPLOYMENT}" \
    --replicas="${ORIGINAL_REPLICAS}" \
    --namespace "${NAMESPACE}" \
    >/dev/null
}

rollback_if_required() {
  if [[ "${ROLLBACK_REQUIRED}" != "true" ]]; then
    return
  fi

  echo
  echo "Emergency rollback..."

  kubectl rollout undo \
    deployment/"${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    >/dev/null

  kubectl rollout status \
    deployment/"${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    --timeout="${RECOVERY_TIMEOUT}"

  ROLLBACK_REQUIRED="false"
}

cleanup() {
  local original_exit_code=$?

  set +e

  rollback_if_required || true
  restore_replicas || true

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

require_command minikube
require_command kubectl
require_command awk
require_command grep

echo "============================================================"
echo "Failed rollout and rollback test"
echo "============================================================"

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then

  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo
echo "1. Checking baseline..."

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

ORIGINAL_READINESS_PATH="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}'
)"

ORIGINAL_REPLICAS="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

ORIGINAL_REVISION="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'
)"

echo "Original image:      ${ORIGINAL_IMAGE}"
echo "Original readiness:  ${ORIGINAL_READINESS_PATH}"
echo "Original replicas:   ${ORIGINAL_REPLICAS}"
echo "Original revision:   ${ORIGINAL_REVISION}"

echo
echo "2. Checking broken candidate image..."

if ! minikube image ls \
  --profile "${PROFILE_NAME}" |
  grep -Fq "${BROKEN_IMAGE}"; then

  echo "Image '${BROKEN_IMAGE}' is not available in Minikube." >&2
  echo "Build/load version 1.0.1 first." >&2
  exit 1
fi

echo "PASS: Candidate image exists."

echo
echo "3. Scaling to ${TEST_REPLICAS} replicas..."

kubectl scale deployment \
  "${TARGET_DEPLOYMENT}" \
  --replicas="${TEST_REPLICAS}" \
  --namespace "${NAMESPACE}"

kubectl rollout status \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=120s

echo "PASS: Baseline replicas are Ready."

echo
echo "4. Applying intentionally broken release..."

ROLLBACK_REQUIRED="true"

kubectl patch deployment \
  "${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --type=json \
  --patch="[
    {
      \"op\": \"replace\",
      \"path\": \"/spec/template/spec/containers/0/image\",
      \"value\": \"${BROKEN_IMAGE}\"
    },
    {
      \"op\": \"replace\",
      \"path\": \"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",
      \"value\": \"${BROKEN_READINESS_PATH}\"
    }
  ]"

echo
echo "5. Waiting for Running but NotReady candidate Pod..."

FAILED_POD=""

for ((attempt = 1; attempt <= 60; attempt++)); do
  FAILED_POD="$(
    kubectl get pods \
      --namespace "${NAMESPACE}" \
      --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT},app.kubernetes.io/component=api" \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{" "}{.status.containerStatuses[0].ready}{" "}{.status.phase}{"\n"}{end}' \
      2>/dev/null |
    awk -v image="${BROKEN_IMAGE}" \
      '$2 == image && $3 == "false" && $4 == "Running" { print $1; exit }'
  )"

  if [[ -n "${FAILED_POD}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${FAILED_POD}" ]]; then
  echo "Broken candidate Pod was not observed." >&2

  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT}" \
    -o wide \
    >&2

  exit 1
fi

echo "PASS: Candidate Pod '${FAILED_POD}' is Running but NotReady."

echo
echo "6. Verifying readiness failure..."

FAILED_READINESS="$(
  kubectl get pod \
    "${FAILED_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.path}'
)"

if [[ "${FAILED_READINESS}" != "${BROKEN_READINESS_PATH}" ]]; then
  echo "Unexpected readiness path '${FAILED_READINESS}'." >&2
  exit 1
fi

echo "PASS: Candidate uses broken readiness '${FAILED_READINESS}'."

echo
echo "7. Verifying rollout does NOT complete..."

if kubectl rollout status \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout="${FAILURE_TIMEOUT}"; then

  echo "Rollout unexpectedly succeeded." >&2
  exit 1
fi

echo "PASS: Rollout failed as expected."

BROKEN_REVISION="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'
)"

echo
echo "Original revision: ${ORIGINAL_REVISION}"
echo "Broken revision:   ${BROKEN_REVISION}"

if [[ "${BROKEN_REVISION}" == "${ORIGINAL_REVISION}" ]]; then
  echo "Expected a new Deployment revision." >&2
  exit 1
fi

echo
echo "8. Checking that healthy Service traffic remains available..."

CATALOG_POD="$(
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/name=catalog-service,app.kubernetes.io/component=api' \
    -o jsonpath='{.items[0].metadata.name}'
)"

for ((request = 1; request <= 10; request++)); do
  STATUS="$(
    MSYS_NO_PATHCONV=1 kubectl exec \
      --namespace "${NAMESPACE}" \
      "${CATALOG_POD}" \
      -- \
      curl \
        --silent \
        --output /dev/null \
        --write-out '%{http_code}' \
        http://pricing-service/health/live
  )"

  printf '%02d -> HTTP %s\n' "${request}" "${STATUS}"

  if [[ "${STATUS}" != "200" ]]; then
    echo "Service traffic failed during broken rollout." >&2
    exit 1
  fi
done

echo "PASS: Existing Ready Pods continue serving traffic."

echo
echo "9. ReplicaSets before rollback..."

kubectl get replicasets \
  --namespace "${NAMESPACE}" \
  --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT}"

echo
echo "10. Rolling back..."

kubectl rollout undo \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}"

kubectl rollout status \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout="${RECOVERY_TIMEOUT}"

ROLLBACK_REQUIRED="false"

echo "PASS: Rollback completed."

echo
echo "11. Verifying restored Pod template..."

CURRENT_IMAGE="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
)"

CURRENT_READINESS_PATH="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}'
)"

echo "Current image:     ${CURRENT_IMAGE}"
echo "Current readiness: ${CURRENT_READINESS_PATH}"

if [[ "${CURRENT_IMAGE}" != "${ORIGINAL_IMAGE}" ]]; then
  echo "Rollback did not restore original image." >&2
  exit 1
fi

if [[ "${CURRENT_READINESS_PATH}" != "${ORIGINAL_READINESS_PATH}" ]]; then
  echo "Rollback did not restore original readiness path." >&2
  exit 1
fi

echo "PASS: Original Pod template was restored."

echo
echo "12. Restoring replica count..."

restore_replicas

kubectl rollout status \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=120s

echo "PASS: Original replica count restored."

echo
echo "13. Final rollout history..."

kubectl rollout history \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "FAILED ROLLOUT AND ROLLBACK TEST PASSED."
echo "============================================================"