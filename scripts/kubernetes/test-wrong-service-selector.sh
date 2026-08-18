#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

SERVICE_NAME="pricing-service"
DEPLOYMENT_NAME="pricing-service"

CATALOG_LOCAL_PORT="${CATALOG_LOCAL_PORT:-5101}"
CATALOG_URL="http://127.0.0.1:${CATALOG_LOCAL_PORT}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

SERVICE_MANIFEST="${REPOSITORY_ROOT}/deploy/kubernetes/base/pricing-service/service.yaml"

PORT_FORWARD_PID=""
TEMP_DIRECTORY=""
TEST_PRODUCT_ID=""

TEST_SKU="K8S-BROKEN-SELECTOR-$(date +%s)-${RANDOM}"

SERVICE_RESTORE_REQUIRED="false"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

restore_service() {
  if [[ "${SERVICE_RESTORE_REQUIRED}" != "true" ]]; then
    return
  fi

  echo
  echo "Restoring Pricing Service manifest..."

  kubectl apply \
    -f "${SERVICE_MANIFEST}" \
    >/dev/null

  SERVICE_RESTORE_REQUIRED="false"
}

cleanup() {
  local original_exit_code=$?

  set +e

  restore_service || true

  if [[ -n "${TEST_PRODUCT_ID}" ]] &&
     [[ -n "${PORT_FORWARD_PID}" ]] &&
     kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then

    curl \
      --silent \
      --output /dev/null \
      --request DELETE \
      "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}" \
      || true
  fi

  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi

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
require_command grep
require_command sed
require_command mktemp

if [[ ! -f "${SERVICE_MANIFEST}" ]]; then
  echo "Service manifest was not found:" >&2
  echo "${SERVICE_MANIFEST}" >&2
  exit 1
fi

TEMP_DIRECTORY="$(mktemp -d)"

PORT_FORWARD_LOG="${TEMP_DIRECTORY}/catalog-port-forward.log"
CREATE_RESPONSE="${TEMP_DIRECTORY}/create-response.json"
PRODUCT_RESPONSE="${TEMP_DIRECTORY}/product-response.json"

echo "============================================================"
echo "Wrong Service selector failure test"
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
  deployment/"${DEPLOYMENT_NAME}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

kubectl wait \
  --for=condition=Available \
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo "PASS: Catalog and Pricing Deployments are available."

echo
echo "2. Starting Catalog port-forward..."

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  service/catalog-service \
  "${CATALOG_LOCAL_PORT}:80" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

for ((attempt = 1; attempt <= 30; attempt++)); do
  if curl \
    --silent \
    --fail \
    --max-time 2 \
    "${CATALOG_URL}/health/live" \
    >/dev/null 2>&1; then

    break
  fi

  if ((attempt == 30)); then
    echo "Catalog Service did not become reachable." >&2
    cat "${PORT_FORWARD_LOG}" >&2
    exit 1
  fi

  sleep 1
done

echo "PASS: Catalog Service is reachable."

echo
echo "3. Creating temporary Catalog product..."

CREATE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${CREATE_RESPONSE}" \
    --write-out '%{http_code}' \
    --request POST \
    --header 'Content-Type: application/json' \
    --data "{
      \"name\": \"Kubernetes Service Selector Test\",
      \"description\": \"Temporary wrong Service selector test\",
      \"sku\": \"${TEST_SKU}\"
    }" \
    "${CATALOG_URL}/api/v1/catalog-products"
)"

if [[ "${CREATE_STATUS}" != "201" ]]; then
  echo "Could not create Catalog test product." >&2
  cat "${CREATE_RESPONSE}" >&2
  exit 1
fi

TEST_PRODUCT_ID="$(
  grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' \
    "${CREATE_RESPONSE}" |
  head -n 1 |
  sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/'
)"

if [[ -z "${TEST_PRODUCT_ID}" ]]; then
  echo "Could not extract Catalog product ID." >&2
  exit 1
fi

echo "Product: ${TEST_PRODUCT_ID}"

echo
echo "4. Breaking Pricing Service selector..."

SERVICE_RESTORE_REQUIRED="true"

kubectl patch service \
  "${SERVICE_NAME}" \
  --namespace "${NAMESPACE}" \
  --type=merge \
  --patch='{
    "spec": {
      "selector": {
        "app.kubernetes.io/name": "pricing-service",
        "app.kubernetes.io/component": "broken-api"
      }
    }
  }'

echo
echo "5. Verifying Pricing Pod remains Ready..."

kubectl wait \
  --for=condition=Ready \
  pod \
  --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api' \
  --namespace "${NAMESPACE}" \
  --timeout=30s

echo "PASS: Pricing Pod is still Ready."

echo
echo "6. Waiting for Service endpoints to disappear..."

ENDPOINTS=""

for ((attempt = 1; attempt <= 30; attempt++)); do
  ENDPOINTS="$(
    kubectl get endpoints \
      "${SERVICE_NAME}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.subsets[*].addresses[*].ip}' \
      2>/dev/null || true
  )"

  if [[ -z "${ENDPOINTS}" ]]; then
    break
  fi

  sleep 1
done

if [[ -n "${ENDPOINTS}" ]]; then
  echo "Pricing Service still has endpoints unexpectedly:" >&2
  echo "${ENDPOINTS}" >&2
  exit 1
fi

echo "PASS: Pricing Service has no endpoints."

echo
echo "7. Verifying Catalog fallback..."

OUTAGE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRODUCT_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${OUTAGE_STATUS}" != "200" ]]; then
  echo "Catalog returned unexpected HTTP ${OUTAGE_STATUS}." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

if ! grep -Eq \
  '"priceStatus"[[:space:]]*:[[:space:]]*"Unavailable"' \
  "${PRODUCT_RESPONSE}"; then

  echo "Expected priceStatus 'Unavailable'." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog returned priceStatus 'Unavailable'."

echo
echo "8. Restoring Pricing Service..."

restore_service

echo
echo "9. Waiting for Pricing endpoint recovery..."

ENDPOINTS=""

for ((attempt = 1; attempt <= 30; attempt++)); do
  ENDPOINTS="$(
    kubectl get endpoints \
      "${SERVICE_NAME}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.subsets[*].addresses[*].ip}' \
      2>/dev/null || true
  )"

  if [[ -n "${ENDPOINTS}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${ENDPOINTS}" ]]; then
  echo "Pricing Service endpoints did not recover." >&2
  exit 1
fi

echo "PASS: Pricing Service endpoint recovered."

echo
echo "10. Verifying Catalog after recovery..."

RECOVERY_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRODUCT_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${RECOVERY_STATUS}" != "200" ]]; then
  echo "Catalog lookup failed after Service recovery." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

if ! grep -Eq \
  '"priceStatus"[[:space:]]*:[[:space:]]*"NotSet"' \
  "${PRODUCT_RESPONSE}"; then

  echo "Expected priceStatus 'NotSet' after recovery." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog returned to priceStatus 'NotSet'."

echo
echo "============================================================"
echo "WRONG SERVICE SELECTOR TEST PASSED."
echo "============================================================"