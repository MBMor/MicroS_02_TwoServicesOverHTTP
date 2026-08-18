#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-pricing-service}"
TARGET_CONTAINER="${TARGET_CONTAINER:-pricing-service}"

BROKEN_ASSEMBLY="${BROKEN_ASSEMBLY:-DefinitelyMissing.dll}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-90}"

RESTORE_REQUIRED="false"
FAILED_POD=""

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

restore_command() {
  if [[ "${RESTORE_REQUIRED}" != "true" ]]; then
    return
  fi

  echo
  echo "Restoring container command..."

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
                \"command\": null,
                \"args\": null
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

  restore_command || true

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

require_command minikube
require_command kubectl
require_command awk

echo "============================================================"
echo "CrashLoopBackOff failure test"
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

echo "PASS: Deployment is available."

echo
echo "2. Applying crashing command..."

RESTORE_REQUIRED="true"

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
              \"command\": [
                \"dotnet\"
              ],
              \"args\": [
                \"${BROKEN_ASSEMBLY}\"
              ]
            }
          ]
        }
      }
    }
  }"

echo
echo "3. Waiting for CrashLoopBackOff..."

for ((attempt = 1; attempt <= TIMEOUT_SECONDS; attempt++)); do
  POD_STATUS="$(
    kubectl get pods \
      --namespace "${NAMESPACE}" \
      --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT},app.kubernetes.io/component=api" \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].state.waiting.reason}{" "}{.status.containerStatuses[0].restartCount}{"\n"}{end}' \
      2>/dev/null || true
  )"

  FAILED_POD="$(
    printf '%s\n' "${POD_STATUS}" |
      awk '$2 == "CrashLoopBackOff" { print $1; exit }'
  )"

  if [[ -n "${FAILED_POD}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${FAILED_POD}" ]]; then
  echo "Expected CrashLoopBackOff was not observed." >&2

  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT}" \
    -o wide \
    >&2

  exit 1
fi

echo "PASS: Pod '${FAILED_POD}' entered CrashLoopBackOff."

echo
echo "4. Checking restart count..."

RESTART_COUNT="$(
  kubectl get pod \
    "${FAILED_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}'
)"

echo "Restart count: ${RESTART_COUNT}"

if ! [[ "${RESTART_COUNT}" =~ ^[0-9]+$ ]] ||
   ((RESTART_COUNT < 1)); then

  echo "Expected restart count greater than zero." >&2
  exit 1
fi

echo "PASS: Container has been restarted."

echo
echo "5. Checking last termination state..."

LAST_REASON="$(
  kubectl get pod \
    "${FAILED_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'
)"

EXIT_CODE="$(
  kubectl get pod \
    "${FAILED_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'
)"

echo "Last reason: ${LAST_REASON}"
echo "Exit code:   ${EXIT_CODE}"

if [[ "${EXIT_CODE}" == "0" ]]; then
  echo "Expected non-zero exit code." >&2
  exit 1
fi

echo "PASS: Previous container terminated with an error."

echo
echo "6. Previous container logs:"
echo "------------------------------------------------------------"

PREVIOUS_LOGS="$(
  kubectl logs \
    "${FAILED_POD}" \
    --namespace "${NAMESPACE}" \
    --container "${TARGET_CONTAINER}" \
    --previous \
    2>&1 || true
)"

printf '%s\n' "${PREVIOUS_LOGS}"

echo "------------------------------------------------------------"

if [[ -z "${PREVIOUS_LOGS}" ]]; then
  echo "Expected previous container logs were empty." >&2
  exit 1
fi

echo "PASS: Previous container logs were retrieved."

echo
echo "7. Pod details..."

kubectl describe pod \
  "${FAILED_POD}" \
  --namespace "${NAMESPACE}"

echo
echo "8. Restoring normal container startup..."

restore_command

echo
echo "9. Verifying Deployment recovery..."

kubectl wait \
  --for=condition=Available \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo "PASS: Deployment recovered."

echo
echo "============================================================"
echo "CRASH LOOP BACKOFF TEST PASSED."
echo "============================================================"