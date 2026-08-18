#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-pricing-service}"
TARGET_CONTAINER="${TARGET_CONTAINER:-pricing-service}"

BROKEN_READINESS_PATH="${BROKEN_READINESS_PATH:-/health/does-not-exist}"

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"
LOCAL_PORT="${LOCAL_PORT:-5104}"

ORIGINAL_READINESS_PATH=""
RESTORE_REQUIRED="false"

FAILED_POD=""

PORT_FORWARD_PID=""
PORT_FORWARD_LOG=""
TEMP_DIRECTORY=""

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

restore_readiness() {
  if [[ "${RESTORE_REQUIRED}" != "true" ||
        -z "${ORIGINAL_READINESS_PATH}" ]]; then
    return
  fi

  echo
  echo "Restoring readiness path '${ORIGINAL_READINESS_PATH}'..."

  kubectl patch deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    --type=strategic \
    --patch="{
      \"spec\": {
        \"template\": {
          \"spec\": {
            \"containers\": [
              {
                \"name\": \"${TARGET_CONTAINER}\",
                \"readinessProbe\": {
                  \"httpGet\": {
                    \"path\": \"${ORIGINAL_READINESS_PATH}\",
                    \"port\": \"http\",
                    \"scheme\": \"HTTP\"
                  },
                  \"periodSeconds\": 5,
                  \"timeoutSeconds\": 3,
                  \"failureThreshold\": 3,
                  \"successThreshold\": 1
                }
              }
            ]
          }
        }
      }
    }" \
    >/dev/null

  kubectl rollout status \
    deployment/"${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    --timeout=120s

  RESTORE_REQUIRED="false"
}

cleanup() {
  local original_exit_code=$?

  set +e

  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi

  restore_readiness || true

  if [[ -n "${TEMP_DIRECTORY}" &&
        -d "${TEMP_DIRECTORY}" ]]; then
    rm -rf "${TEMP_DIRECTORY}"
  fi

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

require_command minikube
require_command kubectl
require_command curl
require_command awk
require_command mktemp

TEMP_DIRECTORY="$(mktemp -d)"
PORT_FORWARD_LOG="${TEMP_DIRECTORY}/port-forward.log"

echo "============================================================"
echo "Failed readiness probe test"
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

ORIGINAL_READINESS_PATH="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name==\"${TARGET_CONTAINER}\")].readinessProbe.httpGet.path}"
)"

if [[ -z "${ORIGINAL_READINESS_PATH}" ]]; then
  echo "Could not determine original readiness path." >&2
  exit 1
fi

echo "Original readiness path: ${ORIGINAL_READINESS_PATH}"
echo "Broken readiness path:   ${BROKEN_READINESS_PATH}"

RESTORE_REQUIRED="true"

echo
echo "2. Applying broken readiness probe..."

kubectl patch deployment \
  "${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --type=strategic \
  --patch="{
    \"spec\": {
      \"template\": {
        \"spec\": {
          \"containers\": [
            {
              \"name\": \"${TARGET_CONTAINER}\",
              \"readinessProbe\": {
                \"httpGet\": {
                  \"path\": \"${BROKEN_READINESS_PATH}\",
                  \"port\": \"http\",
                  \"scheme\": \"HTTP\"
                },
                \"periodSeconds\": 5,
                \"timeoutSeconds\": 3,
                \"failureThreshold\": 3,
                \"successThreshold\": 1
              }
            }
          ]
        }
      }
    }
  }"

echo
echo "3. Waiting for a Running but NotReady Pod..."

for ((attempt = 1; attempt <= TIMEOUT_SECONDS; attempt++)); do
  POD_STATUS="$(
    kubectl get pods \
      --namespace "${NAMESPACE}" \
      --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT},app.kubernetes.io/component=api" \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].ready}{" "}{.status.phase}{"\n"}{end}' \
      2>/dev/null || true
  )"

  FAILED_POD="$(
    printf '%s\n' "${POD_STATUS}" |
      awk '$2 == "false" && $3 == "Running" { print $1; exit }'
  )"

  if [[ -n "${FAILED_POD}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${FAILED_POD}" ]]; then
  echo "Expected Running/NotReady Pod was not observed." >&2

  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT}" \
    -o wide \
    >&2

  exit 1
fi

echo "PASS: Pod '${FAILED_POD}' is Running but NotReady."

echo
echo "4. Checking restart count..."

RESTART_COUNT="$(
  kubectl get pod \
    "${FAILED_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}'
)"

echo "Restart count: ${RESTART_COUNT}"

if [[ "${RESTART_COUNT}" != "0" ]]; then
  echo "Expected restart count 0 for readiness-only failure." >&2
  exit 1
fi

echo "PASS: Container was not restarted."

echo
echo "5. Showing readiness failure..."

kubectl describe pod \
  "${FAILED_POD}" \
  --namespace "${NAMESPACE}"

echo
echo "6. Starting direct Pod port-forward..."

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  pod/"${FAILED_POD}" \
  "${LOCAL_PORT}:8080" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

for ((attempt = 1; attempt <= 30; attempt++)); do
  if curl \
    --silent \
    --fail \
    --max-time 2 \
    "http://127.0.0.1:${LOCAL_PORT}/health/live" \
    >/dev/null 2>&1; then
    break
  fi

  if ((attempt == 30)); then
    echo "Could not reach failed Pod directly." >&2
    cat "${PORT_FORWARD_LOG}" >&2
    exit 1
  fi

  sleep 1
done

echo "PASS: Application is alive inside the NotReady Pod."

echo
echo "7. Verifying application's real readiness endpoint..."

REAL_READINESS_STATUS="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    "http://127.0.0.1:${LOCAL_PORT}${ORIGINAL_READINESS_PATH}"
)"

if [[ "${REAL_READINESS_STATUS}" != "200" ]]; then
  echo "Application's real readiness endpoint returned ${REAL_READINESS_STATUS}." >&2
  exit 1
fi

echo "PASS: ${ORIGINAL_READINESS_PATH} returns HTTP 200."

echo
echo "8. Verifying broken endpoint..."

BROKEN_STATUS="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    "http://127.0.0.1:${LOCAL_PORT}${BROKEN_READINESS_PATH}"
)"

if [[ "${BROKEN_STATUS}" == "200" ]]; then
  echo "Broken readiness endpoint unexpectedly returned HTTP 200." >&2
  exit 1
fi

echo "PASS: Broken readiness endpoint returns HTTP ${BROKEN_STATUS}."

kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
PORT_FORWARD_PID=""

echo
echo "9. Restoring correct readiness probe..."

restore_readiness

echo
echo "10. Verifying Deployment recovery..."

kubectl wait \
  --for=condition=Available \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo "PASS: Deployment recovered."

echo
echo "============================================================"
echo "FAILED READINESS PROBE TEST PASSED."
echo "============================================================"