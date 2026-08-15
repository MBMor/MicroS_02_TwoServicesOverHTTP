#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

CATALOG_LOCAL_PORT="${CATALOG_LOCAL_PORT:-5101}"
PRICING_LOCAL_PORT="${PRICING_LOCAL_PORT:-5102}"

WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-30}"

CATALOG_URL="http://127.0.0.1:${CATALOG_LOCAL_PORT}"
PRICING_URL="http://127.0.0.1:${PRICING_LOCAL_PORT}"

CATALOG_PORT_FORWARD_PID=""
PRICING_PORT_FORWARD_PID=""

CATALOG_PORT_FORWARD_LOG=""
PRICING_PORT_FORWARD_LOG=""

TEST_PRODUCT_ID=""
TEST_SKU="K8S-SMOKE-$(date +%s)-${RANDOM}"

TEMP_DIRECTORY=""

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
     [[ -n "${CATALOG_PORT_FORWARD_PID}" ]] &&
     kill -0 "${CATALOG_PORT_FORWARD_PID}" >/dev/null 2>&1; then

    echo
    echo "Cleaning up smoke-test Catalog product..."

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

assert_http_status() {
  local description="$1"
  local expected_status="$2"
  local method="$3"
  local url="$4"
  local body_file="$5"
  local request_body="${6:-}"

  local actual_status

  if [[ -n "${request_body}" ]]; then
    actual_status="$(
      curl \
        --silent \
        --show-error \
        --output "${body_file}" \
        --write-out '%{http_code}' \
        --request "${method}" \
        --header 'Content-Type: application/json' \
        --data "${request_body}" \
        "${url}"
    )"
  else
    actual_status="$(
      curl \
        --silent \
        --show-error \
        --output "${body_file}" \
        --write-out '%{http_code}' \
        --request "${method}" \
        "${url}"
    )"
  fi

  if [[ "${actual_status}" != "${expected_status}" ]]; then
    echo "FAILED: ${description}" >&2
    echo "Expected HTTP status: ${expected_status}" >&2
    echo "Actual HTTP status:   ${actual_status}" >&2
    echo >&2
    echo "Response body:" >&2
    cat "${body_file}" >&2 || true
    echo >&2
    exit 1
  fi

  echo "PASS: ${description} (${actual_status})"
}

wait_for_endpoint() {
  local description="$1"
  local url="$2"

  for ((attempt = 1; attempt <= WAIT_TIMEOUT_SECONDS; attempt++)); do
    if curl \
      --silent \
      --fail \
      --max-time 2 \
      "${url}" \
      >/dev/null 2>&1; then

      echo "PASS: ${description}"
      return 0
    fi

    sleep 1
  done

  echo "FAILED: ${description}" >&2
  echo "Endpoint did not become available: ${url}" >&2
  exit 1
}

require_command minikube
require_command kubectl
require_command curl
require_command grep
require_command sed
require_command mktemp

TEMP_DIRECTORY="$(mktemp -d)"

CATALOG_PORT_FORWARD_LOG="${TEMP_DIRECTORY}/catalog-port-forward.log"
PRICING_PORT_FORWARD_LOG="${TEMP_DIRECTORY}/pricing-port-forward.log"

CATALOG_RESPONSE="${TEMP_DIRECTORY}/catalog-response.json"
PRICING_RESPONSE="${TEMP_DIRECTORY}/pricing-response.json"
PRODUCT_RESPONSE="${TEMP_DIRECTORY}/product-response.json"

echo "============================================================"
echo "Kubernetes QA Lab smoke tests"
echo "============================================================"
echo
echo "Profile:   ${PROFILE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

echo "1. Checking Minikube cluster..."

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "FAILED: Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

echo "PASS: Minikube cluster is running."

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

# ---------------------------------------------------------------------------
# Databases
# ---------------------------------------------------------------------------

echo
echo "2. Checking database Pods..."

kubectl wait \
  --for=condition=Ready \
  pod/catalog-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout=30s

kubectl wait \
  --for=condition=Ready \
  pod/pricing-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout=30s

echo "PASS: Both PostgreSQL Pods are ready."

# ---------------------------------------------------------------------------
# Migrations
# ---------------------------------------------------------------------------

echo
echo "3. Checking database migrations..."

for job_name in \
  pricing-database-migration \
  catalog-database-migration
do
  if ! kubectl get job \
    "${job_name}" \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then

    echo "FAILED: Migration Job '${job_name}' does not exist." >&2
    exit 1
  fi

  kubectl wait \
    --for=condition=Complete \
    job/"${job_name}" \
    --namespace "${NAMESPACE}" \
    --timeout=30s
done

echo "PASS: Both migration Jobs are complete."

# ---------------------------------------------------------------------------
# Deployments
# ---------------------------------------------------------------------------

echo
echo "4. Checking application Deployments..."

for deployment_name in \
  pricing-service \
  catalog-service
do
  kubectl wait \
    --for=condition=Available \
    deployment/"${deployment_name}" \
    --namespace "${NAMESPACE}" \
    --timeout=30s
done

echo "PASS: Both application Deployments are available."

# ---------------------------------------------------------------------------
# Services / endpoints
# ---------------------------------------------------------------------------

echo
echo "5. Checking Kubernetes Services..."

for service_name in \
  catalog-service \
  pricing-service \
  catalog-service-db \
  pricing-service-db
do
  if ! kubectl get service \
    "${service_name}" \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then

    echo "FAILED: Service '${service_name}' does not exist." >&2
    exit 1
  fi
done

echo "PASS: Required Kubernetes Services exist."

# ---------------------------------------------------------------------------
# Port forwarding
# ---------------------------------------------------------------------------

echo
echo "6. Starting temporary port-forwards..."

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

wait_for_endpoint \
  "Catalog Service is reachable" \
  "${CATALOG_URL}/health/live"

wait_for_endpoint \
  "Pricing Service is reachable" \
  "${PRICING_URL}/health/live"

# ---------------------------------------------------------------------------
# Health checks
# ---------------------------------------------------------------------------

echo
echo "7. Checking application health..."

assert_http_status \
  "Catalog liveness" \
  "200" \
  "GET" \
  "${CATALOG_URL}/health/live" \
  "${CATALOG_RESPONSE}"

assert_http_status \
  "Catalog readiness" \
  "200" \
  "GET" \
  "${CATALOG_URL}/health/ready" \
  "${CATALOG_RESPONSE}"

assert_http_status \
  "Pricing liveness" \
  "200" \
  "GET" \
  "${PRICING_URL}/health/live" \
  "${PRICING_RESPONSE}"

assert_http_status \
  "Pricing readiness" \
  "200" \
  "GET" \
  "${PRICING_URL}/health/ready" \
  "${PRICING_RESPONSE}"

# ---------------------------------------------------------------------------
# Kubernetes internal service-to-service connectivity
# ---------------------------------------------------------------------------

echo
echo "8. Checking Catalog -> Pricing Kubernetes DNS communication..."

CATALOG_POD="$(
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/name=catalog-service,app.kubernetes.io/component=api' \
    --output=jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${CATALOG_POD}" ]]; then
  echo "FAILED: Catalog Pod was not found." >&2
  exit 1
fi

kubectl exec \
  --namespace "${NAMESPACE}" \
  "${CATALOG_POD}" \
  -- \
  curl \
    --fail \
    --silent \
    --show-error \
    http://pricing-service/health/live \
    >/dev/null

echo "PASS: Catalog Pod can reach Pricing Service through Kubernetes DNS."

# ---------------------------------------------------------------------------
# Business smoke test
# ---------------------------------------------------------------------------

echo
echo "9. Running Catalog business smoke test..."

CREATE_PRODUCT_BODY="$(
  cat <<EOF
{
  "name": "Kubernetes Smoke Test Product",
  "description": "Temporary product created by Kubernetes smoke test",
  "sku": "${TEST_SKU}"
}
EOF
)"

assert_http_status \
  "Create Catalog product" \
  "201" \
  "POST" \
  "${CATALOG_URL}/api/v1/catalog-products" \
  "${PRODUCT_RESPONSE}" \
  "${CREATE_PRODUCT_BODY}"

TEST_PRODUCT_ID="$(
  grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' \
    "${PRODUCT_RESPONSE}" |
  head -n 1 |
  sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/'
)"

if [[ -z "${TEST_PRODUCT_ID}" ]]; then
  echo "FAILED: Could not extract Catalog product ID." >&2
  echo "Response:" >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "Created Catalog product: ${TEST_PRODUCT_ID}"

assert_http_status \
  "Get Catalog product with Pricing lookup" \
  "200" \
  "GET" \
  "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}" \
  "${PRODUCT_RESPONSE}"

if ! grep -Eq \
  '"priceStatus"[[:space:]]*:[[:space:]]*"NotSet"' \
  "${PRODUCT_RESPONSE}"; then

  echo "FAILED: Expected priceStatus 'NotSet'." >&2
  echo "Response:" >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog -> Pricing business lookup returned priceStatus 'NotSet'."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "Smoke test summary"
echo "============================================================"

kubectl get deployments \
  --namespace "${NAMESPACE}"

echo

kubectl get statefulsets \
  --namespace "${NAMESPACE}"

echo

kubectl get jobs \
  --namespace "${NAMESPACE}"

echo

kubectl get pods \
  --namespace "${NAMESPACE}"

echo
echo "ALL KUBERNETES SMOKE TESTS PASSED."