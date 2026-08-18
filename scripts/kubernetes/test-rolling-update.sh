#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-pricing-service}"
TARGET_CONTAINER="${TARGET_CONTAINER:-pricing-service}"

UPDATE_IMAGE="${UPDATE_IMAGE:-micros-02/pricing-service:1.0.1}"
TEST_REPLICAS="${TEST_REPLICAS:-3}"

ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-120s}"

ORIGINAL_IMAGE=""
ORIGINAL_REPLICAS=""

RESTORE_REQUIRED="false"

TRAFFIC_PID=""
TRAFFIC_LOG=""

TEMP_DIRECTORY=""

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

restore_deployment() {
  if [[ "${RESTORE_REQUIRED}" != "true" ]]; then
    return
  fi

  echo
  echo "Restoring original Deployment state..."
  echo "Image:    ${ORIGINAL_IMAGE}"
  echo "Replicas: ${ORIGINAL_REPLICAS}"

  kubectl set image \
    deployment/"${TARGET_DEPLOYMENT}" \
    "${TARGET_CONTAINER}=${ORIGINAL_IMAGE}" \
    --namespace "${NAMESPACE}" \
    >/dev/null

  kubectl scale deployment \
    "${TARGET_DEPLOYMENT}" \
    --replicas="${ORIGINAL_REPLICAS}" \
    --namespace "${NAMESPACE}" \
    >/dev/null

  kubectl rollout status \
    deployment/"${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    --timeout="${ROLLOUT_TIMEOUT}"

  RESTORE_REQUIRED="false"
}

cleanup() {
  local original_exit_code=$?

  set +e

  if [[ -n "${TRAFFIC_PID}" ]]; then
    kill "${TRAFFIC_PID}" >/dev/null 2>&1 || true
    wait "${TRAFFIC_PID}" >/dev/null 2>&1 || true
  fi

  restore_deployment || true

  if [[ -n "${TEMP_DIRECTORY}" &&
        -d "${TEMP_DIRECTORY}" ]]; then
    rm -rf "${TEMP_DIRECTORY}"
  fi

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

require_command minikube
require_command kubectl
require_command grep
require_command mktemp

TEMP_DIRECTORY="$(mktemp -d)"
TRAFFIC_LOG="${TEMP_DIRECTORY}/traffic.log"

echo "============================================================"
echo "Rolling Update test"
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

ORIGINAL_REPLICAS="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

echo "Original image:    ${ORIGINAL_IMAGE}"
echo "Original replicas: ${ORIGINAL_REPLICAS}"
echo "Update image:      ${UPDATE_IMAGE}"

if [[ "${ORIGINAL_IMAGE}" == "${UPDATE_IMAGE}" ]]; then
  echo "UPDATE_IMAGE must differ from the current image." >&2
  exit 1
fi

echo
echo "2. Checking update image in Minikube..."

if ! minikube image ls \
  --profile "${PROFILE_NAME}" |
  grep -Fq "${UPDATE_IMAGE}"; then

  echo "Image '${UPDATE_IMAGE}' is not available in Minikube." >&2
  echo >&2
  echo "Build and load it first:" >&2
  echo "  IMAGE_VERSION=1.0.1 ./scripts/kubernetes/build-and-load-images.sh" >&2
  exit 1
fi

echo "PASS: Update image is available."

RESTORE_REQUIRED="true"

echo
echo "3. Scaling Pricing to ${TEST_REPLICAS} replicas..."

kubectl scale deployment \
  "${TARGET_DEPLOYMENT}" \
  --replicas="${TEST_REPLICAS}" \
  --namespace "${NAMESPACE}"

kubectl rollout status \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout="${ROLLOUT_TIMEOUT}"

echo "PASS: ${TEST_REPLICAS} replicas are available."

echo
echo "4. Finding Catalog Pod for in-cluster traffic..."

CATALOG_POD="$(
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/name=catalog-service,app.kubernetes.io/component=api' \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${CATALOG_POD}" ]]; then
  echo "Could not find Catalog Pod." >&2
  exit 1
fi

echo "Catalog Pod: ${CATALOG_POD}"

echo
echo "5. Starting traffic through pricing-service..."

kubectl exec \
  --namespace "${NAMESPACE}" \
  "${CATALOG_POD}" \
  -- \
  sh -ec '
    i=1

    while [ "$i" -le 40 ]; do
      code="$(
        curl \
          --silent \
          --output /dev/null \
          --write-out "%{http_code}" \
          http://pricing-service/health/live \
          || true
      )"

      printf "%02d HTTP %s\n" "$i" "$code"

      if [ "$code" != "200" ]; then
        exit 1
      fi

      i=$((i + 1))
      sleep 0.5
    done
  ' \
  >"${TRAFFIC_LOG}" 2>&1 &

TRAFFIC_PID="$!"

sleep 1

echo
echo "6. Updating image..."

kubectl set image \
  deployment/"${TARGET_DEPLOYMENT}" \
  "${TARGET_CONTAINER}=${UPDATE_IMAGE}" \
  --namespace "${NAMESPACE}"

echo
echo "7. Waiting for Rolling Update..."

kubectl rollout status \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout="${ROLLOUT_TIMEOUT}"

echo "PASS: Rolling Update completed."

echo
echo "8. Waiting for traffic test..."

if ! wait "${TRAFFIC_PID}"; then
  echo "Traffic failed during Rolling Update." >&2
  echo >&2
  cat "${TRAFFIC_LOG}" >&2
  TRAFFIC_PID=""
  exit 1
fi

TRAFFIC_PID=""

cat "${TRAFFIC_LOG}"

echo
echo "PASS: All traffic requests returned HTTP 200."

echo
echo "9. Verifying Pod images..."

POD_IMAGES="$(
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT},app.kubernetes.io/component=api" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}'
)"

printf '%s\n' "${POD_IMAGES}"

INVALID_PODS="$(
  printf '%s\n' "${POD_IMAGES}" |
  awk -v image="${UPDATE_IMAGE}" '
    $2 != image || $3 != "true" {
      print
    }
  '
)"

if [[ -n "${INVALID_PODS}" ]]; then
  echo "Not all Pricing Pods use the expected image and are Ready." >&2
  printf '%s\n' "${INVALID_PODS}" >&2
  exit 1
fi

echo
echo "PASS: All Pricing Pods are Ready on '${UPDATE_IMAGE}'."

echo
echo "10. ReplicaSets after update..."

kubectl get replicasets \
  --namespace "${NAMESPACE}" \
  --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT}"

echo
echo "11. Rollout history..."

kubectl rollout history \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}"

echo
echo "12. Restoring original state..."

restore_deployment

echo
echo "============================================================"
echo "ROLLING UPDATE TEST PASSED."
echo "============================================================"