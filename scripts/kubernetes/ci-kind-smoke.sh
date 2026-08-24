#!/usr/bin/env bash

set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-micros-02-qa}"

CATALOG_LOCAL_PORT="${CATALOG_LOCAL_PORT:-5101}"
PRICING_LOCAL_PORT="${PRICING_LOCAL_PORT:-5102}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"

CATALOG_URL="http://127.0.0.1:${CATALOG_LOCAL_PORT}"
PRICING_URL="http://127.0.0.1:${PRICING_LOCAL_PORT}"

CATALOG_PORT_FORWARD_PID=""
PRICING_PORT_FORWARD_PID=""

TEMP_DIRECTORY=""

TEST_PRODUCT_ID=""
TEST_SKU="K8S-KIND-CI-$(date +%s)-${RANDOM}"

cleanup() {
  local original_exit_code=$?

  set +e

  if [[ -n "${TEST_PRODUCT_ID}" ]] &&
     [[ -n "${CATALOG_PORT_FORWARD_PID}" ]] &&
     kill -0 "${CATALOG_PORT_FORWARD_PID}" >/dev/null 2>&1; then

    curl \
      --silent \
      --output /dev/null \
      --request DELETE \
      "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}" \
      || true
  fi

  if [[ -n "${CATALOG_PORT_FORWARD_PID}" ]]; then
    kill "${CATALOG_PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${CATALOG_PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${PRICING_PORT_FORWARD_PID}" ]]; then
    kill "${PRICING_PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PRICING_PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${TEMP_DIRECTORY}" &&
        -d "${TEMP_DIRECTORY}" ]]; then

    rm -rf "${TEMP_DIRECTORY}"
  fi

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

wait_for_http() {
  local name="$1"
  local url="$2"

  for ((attempt = 1; attempt <= 60; attempt++)); do
    if curl \
      --silent \
      --fail \
      --max-time 3 \
      "${url}" \
      >/dev/null 2>&1; then

      echo "PASS: ${name} is reachable."
      return 0
    fi

    sleep 1
  done

  echo "${name} did not become reachable:" >&2
  echo "  ${url}" >&2

  return 1
}

require_command kubectl
require_command curl
require_command grep
require_command sed
require_command mktemp

TEMP_DIRECTORY="$(mktemp -d)"

CATALOG_PORT_FORWARD_LOG="${TEMP_DIRECTORY}/catalog-port-forward.log"
PRICING_PORT_FORWARD_LOG="${TEMP_DIRECTORY}/pricing-port-forward.log"

CREATE_RESPONSE="${TEMP_DIRECTORY}/create-response.json"
CATALOG_RESPONSE="${TEMP_DIRECTORY}/catalog-response.json"
PRICING_RESPONSE="${TEMP_DIRECTORY}/pricing-response.json"

echo "============================================================"
echo "Kubernetes kind CI smoke test"
echo "============================================================"

echo
echo "Context:"
kubectl config current-context

echo
echo "1. Checking Kubernetes cluster..."

kubectl cluster-info

kubectl get nodes \
  -o wide

if ! kubectl get namespace \
  "${NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "Namespace '${NAMESPACE}' does not exist." >&2
  exit 1
fi

echo "PASS: Kubernetes cluster is available."

echo
echo "2. Checking database Pods..."

kubectl wait \
  --for=condition=Ready \
  pod/catalog-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

kubectl wait \
  --for=condition=Ready \
  pod/pricing-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: PostgreSQL Pods are Ready."

echo
echo "3. Checking migration Jobs..."

kubectl wait \
  --for=condition=Complete \
  job/catalog-database-migration \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

kubectl wait \
  --for=condition=Complete \
  job/pricing-database-migration \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: EF Core migrations completed."

echo
echo "4. Checking API Deployments..."

kubectl rollout status \
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

kubectl rollout status \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: API Deployments are available."

echo
echo "5. Checking Kubernetes Services..."

for service_name in \
  catalog-service \
  pricing-service \
  catalog-service-db \
  pricing-service-db; do

  if ! kubectl get service \
    "${service_name}" \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then

    echo "Service '${service_name}' was not found." >&2
    exit 1
  fi
done

echo "PASS: Required Services exist."

echo
echo "6. Checking API EndpointSlices..."

CATALOG_ENDPOINTS="$(
  kubectl get endpointslices \
    --namespace "${NAMESPACE}" \
    --selector='kubernetes.io/service-name=catalog-service' \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
)"

PRICING_ENDPOINTS="$(
  kubectl get endpointslices \
    --namespace "${NAMESPACE}" \
    --selector='kubernetes.io/service-name=pricing-service' \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
)"

if [[ -z "${CATALOG_ENDPOINTS}" ]]; then
  echo "Catalog Service has no endpoints." >&2
  exit 1
fi

if [[ -z "${PRICING_ENDPOINTS}" ]]; then
  echo "Pricing Service has no endpoints." >&2
  exit 1
fi

echo "Catalog endpoints:"
echo "${CATALOG_ENDPOINTS}"

echo "Pricing endpoints:"
echo "${PRICING_ENDPOINTS}"

echo "PASS: API Services have endpoints."

echo
echo "7. Starting API port-forwards..."

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  service/catalog-service \
  "${CATALOG_LOCAL_PORT}:80" \
  >"${CATALOG_PORT_FORWARD_LOG}" 2>&1 &

CATALOG_PORT_FORWARD_PID="$!"

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  service/pricing-service \
  "${PRICING_LOCAL_PORT}:80" \
  >"${PRICING_PORT_FORWARD_LOG}" 2>&1 &

PRICING_PORT_FORWARD_PID="$!"

if ! wait_for_http \
  "Catalog Service" \
  "${CATALOG_URL}/health/live"; then

  cat "${CATALOG_PORT_FORWARD_LOG}" >&2
  exit 1
fi

if ! wait_for_http \
  "Pricing Service" \
  "${PRICING_URL}/health/live"; then

  cat "${PRICING_PORT_FORWARD_LOG}" >&2
  exit 1
fi

echo
echo "8. Checking readiness endpoints..."

curl \
  --fail \
  --show-error \
  --silent \
  "${CATALOG_URL}/health/ready"

echo

curl \
  --fail \
  --show-error \
  --silent \
  "${PRICING_URL}/health/ready"

echo

echo "PASS: Both APIs are Ready."

echo
echo "9. Creating Catalog product..."

CREATE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${CREATE_RESPONSE}" \
    --write-out '%{http_code}' \
    --request POST \
    --header 'Content-Type: application/json' \
    --data "{
      \"name\": \"Kubernetes kind CI product\",
      \"description\": \"Temporary Kubernetes CI smoke product\",
      \"sku\": \"${TEST_SKU}\"
    }" \
    "${CATALOG_URL}/api/v1/catalog-products"
)"

if [[ "${CREATE_STATUS}" != "201" ]]; then
  echo "Expected HTTP 201 when creating Catalog product." >&2
  echo "Actual: ${CREATE_STATUS}" >&2
  cat "${CREATE_RESPONSE}" >&2
  exit 1
fi

TEST_PRODUCT_ID="$(
  grep -oE \
    '"id"[[:space:]]*:[[:space:]]*"[^"]+"' \
    "${CREATE_RESPONSE}" |
  head -n 1 |
  sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/'
)"

if [[ -z "${TEST_PRODUCT_ID}" ]]; then
  echo "Could not extract Catalog product ID." >&2
  cat "${CREATE_RESPONSE}" >&2
  exit 1
fi

echo "Created product: ${TEST_PRODUCT_ID}"
echo "PASS: Catalog create succeeded."

echo
echo "10. Verifying Catalog -> Pricing communication..."

CATALOG_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${CATALOG_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${CATALOG_STATUS}" != "200" ]]; then
  echo "Catalog lookup returned ${CATALOG_STATUS}." >&2
  cat "${CATALOG_RESPONSE}" >&2
  exit 1
fi

if ! grep -Eq \
  '"priceStatus"[[:space:]]*:[[:space:]]*"NotSet"' \
  "${CATALOG_RESPONSE}"; then

  echo "Expected priceStatus 'NotSet'." >&2
  cat "${CATALOG_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog reached Pricing Service."

echo
echo "11. Checking Pricing API directly..."

PRICING_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRICING_RESPONSE}" \
    --write-out '%{http_code}' \
    "${PRICING_URL}/api/v1/prices/${TEST_PRODUCT_ID}"
)"

if [[ "${PRICING_STATUS}" != "404" ]]; then
  echo "Expected Pricing HTTP 404 for product without a price." >&2
  echo "Actual: ${PRICING_STATUS}" >&2
  cat "${PRICING_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Pricing API returned expected 404."

echo
echo "12. Final Kubernetes state..."

kubectl get pods \
  --namespace "${NAMESPACE}" \
  -o wide

echo

kubectl get jobs \
  --namespace "${NAMESPACE}"

echo

kubectl get services \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "KIND KUBERNETES CI SMOKE TEST PASSED."
echo "============================================================"