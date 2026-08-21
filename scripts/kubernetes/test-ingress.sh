#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

KONG_NAMESPACE="${KONG_NAMESPACE:-kong}"

LOCAL_PORT="${LOCAL_PORT:-8088}"
BASE_URL="http://127.0.0.1:${LOCAL_PORT}"

PORT_FORWARD_PID=""
TEMP_DIRECTORY=""
TEST_PRODUCT_ID=""

TEST_SKU="K8S-INGRESS-$(date +%s)-${RANDOM}"

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

  if [[ -n "${TEST_PRODUCT_ID}" ]] &&
     [[ -n "${PORT_FORWARD_PID}" ]] &&
     kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then

    echo
    echo "Cleaning up Catalog test product..."

    curl \
      --silent \
      --output /dev/null \
      --request DELETE \
      "${BASE_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}" \
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
require_command awk
require_command grep
require_command sed
require_command mktemp

TEMP_DIRECTORY="$(mktemp -d)"

PORT_FORWARD_LOG="${TEMP_DIRECTORY}/kong-port-forward.log"
CREATE_RESPONSE="${TEMP_DIRECTORY}/create-response.json"
CATALOG_RESPONSE="${TEMP_DIRECTORY}/catalog-response.json"
PRICING_RESPONSE="${TEMP_DIRECTORY}/pricing-response.json"

echo "============================================================"
echo "Kong Ingress routing test"
echo "============================================================"

echo
echo "1. Checking Minikube..."

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then

  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "PASS: Minikube is running."

echo
echo "2. Checking application baseline..."

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

echo "PASS: Catalog and Pricing are available."

echo
echo "3. Checking Ingress..."

if ! kubectl get ingress \
  micros-02-api \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "Ingress 'micros-02-api' was not found." >&2
  echo "Run ./scripts/kubernetes/setup-ingress.sh first." >&2
  exit 1
fi

echo "PASS: Ingress exists."

echo
echo "4. Finding Kong proxy Service..."

KONG_PROXY_SERVICE="$(
  kubectl get services \
    --namespace "${KONG_NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .spec.ports[*]}{.port}{" "}{end}{"\n"}{end}' |
  awk '$1 ~ /proxy/ && $0 ~ /(^| )80( |$)/ { print $1; exit }'
)"

if [[ -z "${KONG_PROXY_SERVICE}" ]]; then
  echo "Could not find Kong proxy Service exposing port 80." >&2

  kubectl get services \
    --namespace "${KONG_NAMESPACE}" \
    >&2

  exit 1
fi

echo "Kong proxy Service: ${KONG_PROXY_SERVICE}"

echo
echo "5. Starting Kong proxy port-forward..."

kubectl port-forward \
  --namespace "${KONG_NAMESPACE}" \
  service/"${KONG_PROXY_SERVICE}" \
  "${LOCAL_PORT}:80" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

echo
echo "6. Waiting for Catalog route..."

CATALOG_ROUTE_READY="false"

for ((attempt = 1; attempt <= 30; attempt++)); do
  STATUS="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 3 \
      "${BASE_URL}/api/v1/catalog-products" \
      2>/dev/null || true
  )"

  if [[ "${STATUS}" == "200" ]]; then
    CATALOG_ROUTE_READY="true"
    break
  fi

  sleep 1
done

if [[ "${CATALOG_ROUTE_READY}" != "true" ]]; then
  echo "Catalog Ingress route did not become reachable." >&2
  echo >&2
  echo "Port-forward log:" >&2
  cat "${PORT_FORWARD_LOG}" >&2
  echo >&2
  echo "Ingress:" >&2
  kubectl describe ingress \
    micros-02-api \
    --namespace "${NAMESPACE}" \
    >&2
  exit 1
fi

echo "PASS: Catalog route is reachable through Kong."

echo
echo "7. Creating Catalog product through Ingress..."

CREATE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${CREATE_RESPONSE}" \
    --write-out '%{http_code}' \
    --request POST \
    --header 'Content-Type: application/json' \
    --data "{
      \"name\": \"Kubernetes Ingress Test\",
      \"description\": \"Temporary product created through Kong Ingress\",
      \"sku\": \"${TEST_SKU}\"
    }" \
    "${BASE_URL}/api/v1/catalog-products"
)"

if [[ "${CREATE_STATUS}" != "201" ]]; then
  echo "Expected Catalog HTTP 201." >&2
  echo "Actual: ${CREATE_STATUS}" >&2
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
  cat "${CREATE_RESPONSE}" >&2
  exit 1
fi

echo "Product ID: ${TEST_PRODUCT_ID}"
echo "PASS: Catalog POST routed correctly."

echo
echo "8. Reading Catalog product through Ingress..."

CATALOG_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${CATALOG_RESPONSE}" \
    --write-out '%{http_code}' \
    "${BASE_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${CATALOG_STATUS}" != "200" ]]; then
  echo "Expected Catalog HTTP 200." >&2
  echo "Actual: ${CATALOG_STATUS}" >&2
  cat "${CATALOG_RESPONSE}" >&2
  exit 1
fi

if ! grep -Fq "${TEST_SKU}" "${CATALOG_RESPONSE}"; then
  echo "Catalog response does not contain expected SKU." >&2
  cat "${CATALOG_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog GET routed correctly."

echo
echo "9. Testing Pricing route..."

PRICING_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRICING_RESPONSE}" \
    --write-out '%{http_code}' \
    "${BASE_URL}/api/v1/prices/${TEST_PRODUCT_ID}"
)"

if [[ "${PRICING_STATUS}" != "404" ]]; then
  echo "Expected Pricing HTTP 404 because no price is configured." >&2
  echo "Actual: ${PRICING_STATUS}" >&2
  cat "${PRICING_RESPONSE}" >&2
  exit 1
fi

if grep -qi 'no Route matched' "${PRICING_RESPONSE}"; then
  echo "Kong did not match the Pricing Ingress route." >&2
  cat "${PRICING_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Pricing request was routed through Kong."

echo
echo "10. Testing unmatched path..."

UNMATCHED_STATUS="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${BASE_URL}/not-configured"
)"

if [[ "${UNMATCHED_STATUS}" != "404" ]]; then
  echo "Expected HTTP 404 for unmatched path." >&2
  echo "Actual: ${UNMATCHED_STATUS}" >&2
  exit 1
fi

echo "PASS: Unmatched path returns HTTP 404."

echo
echo "11. Current Ingress configuration..."

kubectl describe ingress \
  micros-02-api \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "KONG INGRESS ROUTING TEST PASSED."
echo "============================================================"