#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

CATALOG_LOCAL_PORT="${CATALOG_LOCAL_PORT:-5101}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"
OUTAGE_TIMEOUT="${OUTAGE_TIMEOUT:-60}"

CATALOG_URL="http://127.0.0.1:${CATALOG_LOCAL_PORT}"

PORT_FORWARD_PID=""
PORT_FORWARD_LOG=""
TEMP_DIRECTORY=""

TEST_PRODUCT_ID=""
TEST_SKU="K8S-PRICING-OUTAGE-$(date +%s)-${RANDOM}"

ORIGINAL_PRICING_REPLICAS=""

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

  echo

  if [[ -n "${ORIGINAL_PRICING_REPLICAS}" ]]; then
    echo "Restoring Pricing replicas to ${ORIGINAL_PRICING_REPLICAS}..."

    kubectl scale deployment \
      pricing-service \
      --replicas="${ORIGINAL_PRICING_REPLICAS}" \
      --namespace "${NAMESPACE}" \
      >/dev/null 2>&1 || true

    if [[ "${ORIGINAL_PRICING_REPLICAS}" != "0" ]]; then
      kubectl rollout status \
        deployment/pricing-service \
        --namespace "${NAMESPACE}" \
        --timeout="${WAIT_TIMEOUT}s" \
        >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "${TEST_PRODUCT_ID}" ]] &&
     [[ -n "${PORT_FORWARD_PID}" ]] &&
     kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then

    echo "Cleaning up Catalog test product..."

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

TEMP_DIRECTORY="$(mktemp -d)"

PORT_FORWARD_LOG="${TEMP_DIRECTORY}/catalog-port-forward.log"
CREATE_RESPONSE="${TEMP_DIRECTORY}/create-response.json"
PRODUCT_RESPONSE="${TEMP_DIRECTORY}/product-response.json"
HEALTH_RESPONSE="${TEMP_DIRECTORY}/health-response.json"

echo "============================================================"
echo "Pricing outage resilience test"
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
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout=60s

kubectl wait \
  --for=condition=Available \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout=60s

ORIGINAL_PRICING_REPLICAS="$(
  kubectl get deployment \
    pricing-service \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

echo "Original Pricing replicas: ${ORIGINAL_PRICING_REPLICAS}"

if ! [[ "${ORIGINAL_PRICING_REPLICAS}" =~ ^[0-9]+$ ]]; then
  echo "Could not determine original Pricing replica count." >&2
  exit 1
fi

if [[ "${ORIGINAL_PRICING_REPLICAS}" == "0" ]]; then
  echo "Pricing Service must have at least one replica before the test." >&2
  exit 1
fi

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
      \"name\": \"Kubernetes Pricing Outage Test\",
      \"description\": \"Temporary resilience test product\",
      \"sku\": \"${TEST_SKU}\"
    }" \
    "${CATALOG_URL}/api/v1/catalog-products"
)"

if [[ "${CREATE_STATUS}" != "201" ]]; then
  echo "Expected Catalog create status 201, got ${CREATE_STATUS}." >&2
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
  echo "Could not extract test product ID." >&2
  cat "${CREATE_RESPONSE}" >&2
  exit 1
fi

echo "Created product: ${TEST_PRODUCT_ID}"

echo
echo "4. Verifying baseline Pricing lookup..."

BASELINE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRODUCT_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${BASELINE_STATUS}" != "200" ]]; then
  echo "Baseline Catalog lookup returned ${BASELINE_STATUS}." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

if ! grep -Eq \
  '"priceStatus"[[:space:]]*:[[:space:]]*"NotSet"' \
  "${PRODUCT_RESPONSE}"; then

  echo "Expected baseline priceStatus 'NotSet'." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Baseline priceStatus is 'NotSet'."

echo
echo "5. Scaling Pricing Service to zero..."

kubectl scale deployment \
  pricing-service \
  --replicas=0 \
  --namespace "${NAMESPACE}"

echo
echo "Waiting for Pricing Deployment to have zero available replicas..."

PRICING_UNAVAILABLE="false"

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  AVAILABLE_REPLICAS="$(
    kubectl get deployment \
      pricing-service \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.availableReplicas}' \
      2>/dev/null || true
  )"

  AVAILABLE_REPLICAS="${AVAILABLE_REPLICAS:-0}"

  if [[ "${AVAILABLE_REPLICAS}" == "0" ]]; then
    PRICING_UNAVAILABLE="true"
    break
  fi

  echo "Available Pricing replicas: ${AVAILABLE_REPLICAS}"
  sleep 1
done

if [[ "${PRICING_UNAVAILABLE}" != "true" ]]; then
  echo "Pricing Service still has available replicas after ${WAIT_TIMEOUT} seconds." >&2

  kubectl get deployment \
    pricing-service \
    --namespace "${NAMESPACE}" \
    >&2

  exit 1
fi

echo "PASS: Pricing Service has no available replicas."

echo
echo "Waiting for Pricing Pods to terminate completely..."

PRICING_PODS_TERMINATED="false"

for ((attempt = 1; attempt <= OUTAGE_TIMEOUT; attempt++)); do
  PRICING_POD_COUNT="$(
    kubectl get pods \
      --namespace "${NAMESPACE}" \
      --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api' \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
      2>/dev/null |
    grep -c . || true
  )"

  if [[ "${PRICING_POD_COUNT}" == "0" ]]; then
    PRICING_PODS_TERMINATED="true"
    break
  fi

  echo "Pricing Pods still present: ${PRICING_POD_COUNT}"
  sleep 1
done

if [[ "${PRICING_PODS_TERMINATED}" != "true" ]]; then
  echo "Pricing Pods did not terminate within ${OUTAGE_TIMEOUT} seconds." >&2

  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api' \
    -o wide \
    >&2

  exit 1
fi

echo "PASS: Pricing Pods are fully terminated."

echo
echo "Waiting for Pricing Service endpoints to disappear..."

PRICING_ENDPOINTS_CLEARED="false"

for ((attempt = 1; attempt <= OUTAGE_TIMEOUT; attempt++)); do
  PRICING_ENDPOINT_COUNT="$(
    kubectl get endpointslices \
      --namespace "${NAMESPACE}" \
      --selector='kubernetes.io/service-name=pricing-service' \
      -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' \
      2>/dev/null |
    grep -c . || true
  )"

  if [[ "${PRICING_ENDPOINT_COUNT}" == "0" ]]; then
    PRICING_ENDPOINTS_CLEARED="true"
    break
  fi

  echo "Pricing endpoints still present: ${PRICING_ENDPOINT_COUNT}"
  sleep 1
done

if [[ "${PRICING_ENDPOINTS_CLEARED}" != "true" ]]; then
  echo "Pricing Service endpoints did not disappear within ${OUTAGE_TIMEOUT} seconds." >&2

  kubectl get endpointslices \
    --namespace "${NAMESPACE}" \
    --selector='kubernetes.io/service-name=pricing-service' \
    -o yaml \
    >&2

  exit 1
fi

echo "PASS: Pricing Service has no endpoints."

echo
echo "6. Verifying Catalog readiness during Pricing outage..."

CATALOG_HEALTH_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${HEALTH_RESPONSE}" \
    --write-out '%{http_code}' \
    --max-time 10 \
    "${CATALOG_URL}/health/ready"
)"

if [[ "${CATALOG_HEALTH_STATUS}" != "200" ]]; then
  echo "Catalog readiness failed during Pricing outage." >&2
  cat "${HEALTH_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog remains Ready."

echo
echo "7. Verifying Catalog fallback..."

FALLBACK_OBSERVED="false"

for ((attempt = 1; attempt <= OUTAGE_TIMEOUT; attempt++)); do
  OUTAGE_STATUS="$(
    curl \
      --silent \
      --show-error \
      --output "${PRODUCT_RESPONSE}" \
      --write-out '%{http_code}' \
      --max-time 10 \
      "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}" \
      2>/dev/null || true
  )"

  if [[ "${OUTAGE_STATUS}" != "200" ]]; then
    echo "Attempt ${attempt}: Catalog HTTP ${OUTAGE_STATUS:-unavailable}"

    sleep 1
    continue
  fi

  if grep -Eq \
    '"priceStatus"[[:space:]]*:[[:space:]]*"Unavailable"' \
    "${PRODUCT_RESPONSE}"; then

    FALLBACK_OBSERVED="true"
    break
  fi

  CURRENT_PRICE_STATUS="$(
    grep -oE \
      '"priceStatus"[[:space:]]*:[[:space:]]*"[^"]+"' \
      "${PRODUCT_RESPONSE}" |
    head -n 1 || true
  )"

  echo "Attempt ${attempt}: ${CURRENT_PRICE_STATUS:-priceStatus not found}"

  sleep 1
done

if [[ "${FALLBACK_OBSERVED}" != "true" ]]; then
  echo "Expected priceStatus 'Unavailable' during Pricing outage." >&2
  echo >&2
  echo "Last Catalog response:" >&2
  cat "${PRODUCT_RESPONSE}" >&2
  echo >&2

  echo "Pricing Pods:" >&2
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api' \
    -o wide \
    >&2 || true

  echo >&2
  echo "Pricing EndpointSlices:" >&2
  kubectl get endpointslices \
    --namespace "${NAMESPACE}" \
    --selector='kubernetes.io/service-name=pricing-service' \
    -o yaml \
    >&2 || true

  exit 1
fi

echo "PASS: Catalog returned priceStatus 'Unavailable'."

echo
echo "8. Restoring Pricing Service..."

kubectl scale deployment \
  pricing-service \
  --replicas="${ORIGINAL_PRICING_REPLICAS}" \
  --namespace "${NAMESPACE}"

kubectl rollout status \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

kubectl wait \
  --for=condition=Available \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: Pricing Service recovered."

echo
echo "9. Verifying Catalog after recovery..."

RECOVERY_OBSERVED="false"

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  RECOVERY_STATUS="$(
    curl \
      --silent \
      --show-error \
      --output "${PRODUCT_RESPONSE}" \
      --write-out '%{http_code}' \
      --max-time 10 \
      "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}" \
      2>/dev/null || true
  )"

  if [[ "${RECOVERY_STATUS}" != "200" ]]; then
    echo "Attempt ${attempt}: Catalog HTTP ${RECOVERY_STATUS:-unavailable}"

    sleep 1
    continue
  fi

  if grep -Eq \
    '"priceStatus"[[:space:]]*:[[:space:]]*"NotSet"' \
    "${PRODUCT_RESPONSE}"; then

    RECOVERY_OBSERVED="true"
    break
  fi

  CURRENT_PRICE_STATUS="$(
    grep -oE \
      '"priceStatus"[[:space:]]*:[[:space:]]*"[^"]+"' \
      "${PRODUCT_RESPONSE}" |
    head -n 1 || true
  )"

  echo "Attempt ${attempt}: ${CURRENT_PRICE_STATUS:-priceStatus not found}"

  sleep 1
done

if [[ "${RECOVERY_OBSERVED}" != "true" ]]; then
  echo "Expected priceStatus 'NotSet' after Pricing recovery." >&2
  echo >&2
  echo "Last Catalog response:" >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog returned to priceStatus 'NotSet'."

echo
echo "10. Verifying final Pricing state..."

kubectl get deployment \
  pricing-service \
  --namespace "${NAMESPACE}"

kubectl get pods \
  --namespace "${NAMESPACE}" \
  --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api'

kubectl get endpointslices \
  --namespace "${NAMESPACE}" \
  --selector='kubernetes.io/service-name=pricing-service'

echo
echo "============================================================"
echo "PRICING OUTAGE RESILIENCE TEST PASSED."
echo "============================================================"