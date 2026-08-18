#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-pricing-service}"
TARGET_CONTAINER="${TARGET_CONTAINER:-pricing-service}"
TARGET_ENV="${TARGET_ENV:-PRICING_DATABASE_PASSWORD}"
MISSING_SECRET="${MISSING_SECRET:-pricing-database-secret-missing}"
SECRET_KEY="${SECRET_KEY:-postgres-password}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"

ORIGINAL_SECRET=""
RESTORE_REQUIRED="false"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

restore_secret_reference() {
  if [[ "${RESTORE_REQUIRED}" != "true" ||
        -z "${ORIGINAL_SECRET}" ]]; then
    return
  fi

  echo
  echo "Restoring Secret reference '${ORIGINAL_SECRET}'..."

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
                \"env\": [
                  {
                    \"name\": \"${TARGET_ENV}\",
                    \"valueFrom\": {
                      \"secretKeyRef\": {
                        \"name\": \"${ORIGINAL_SECRET}\",
                        \"key\": \"${SECRET_KEY}\"
                      }
                    }
                  }
                ]
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

  restore_secret_reference || true

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

require_command minikube
require_command kubectl
require_command awk

echo "============================================================"
echo "Missing Secret failure test"
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
echo "1. Checking baseline Deployment..."

kubectl wait \
  --for=condition=Available \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

ORIGINAL_SECRET="$(
  kubectl get deployment \
    "${TARGET_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name==\"${TARGET_CONTAINER}\")].env[?(@.name==\"${TARGET_ENV}\")].valueFrom.secretKeyRef.name}"
)"

if [[ -z "${ORIGINAL_SECRET}" ]]; then
  echo "Could not determine original Secret reference." >&2
  exit 1
fi

echo "Original Secret: ${ORIGINAL_SECRET}"
echo "Missing Secret:  ${MISSING_SECRET}"

if kubectl get secret \
  "${MISSING_SECRET}" \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "Secret '${MISSING_SECRET}' unexpectedly exists." >&2
  echo "Choose another MISSING_SECRET value." >&2
  exit 1
fi

RESTORE_REQUIRED="true"

echo
echo "2. Applying missing Secret reference..."

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
              \"env\": [
                {
                  \"name\": \"${TARGET_ENV}\",
                  \"valueFrom\": {
                    \"secretKeyRef\": {
                      \"name\": \"${MISSING_SECRET}\",
                      \"key\": \"${SECRET_KEY}\"
                    }
                  }
                }
              ]
            }
          ]
        }
      }
    }
  }"

echo
echo "3. Waiting for CreateContainerConfigError..."

FAILED_POD=""

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
      awk '$2 == "CreateContainerConfigError" { print $1; exit }'
  )"

  if [[ -n "${FAILED_POD}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${FAILED_POD}" ]]; then
  echo "Expected CreateContainerConfigError was not observed." >&2

  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector="app.kubernetes.io/name=${TARGET_DEPLOYMENT}" \
    -o wide \
    >&2

  exit 1
fi

echo "PASS: Pod '${FAILED_POD}' entered CreateContainerConfigError."

echo
echo "4. Checking Pod Events..."

POD_DESCRIPTION="$(
  kubectl describe pod \
    "${FAILED_POD}" \
    --namespace "${NAMESPACE}"
)"

printf '%s\n' "${POD_DESCRIPTION}"

if ! printf '%s\n' "${POD_DESCRIPTION}" |
  grep -Fq "secret \"${MISSING_SECRET}\" not found"; then

  echo
  echo "Expected missing Secret Event was not found." >&2
  exit 1
fi

echo
echo "PASS: Pod Event identifies missing Secret '${MISSING_SECRET}'."

echo
echo "5. Restoring original Secret reference..."

restore_secret_reference

echo
echo "6. Verifying recovered Deployment..."

kubectl wait \
  --for=condition=Available \
  deployment/"${TARGET_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo
echo "PASS: Deployment recovered successfully."

echo
echo "============================================================"
echo "MISSING SECRET FAILURE TEST PASSED."
echo "============================================================"