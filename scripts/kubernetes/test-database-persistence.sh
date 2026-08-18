#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

DB_POD="${DB_POD:-catalog-service-db-0}"

CATALOG_LOCAL_PORT="${CATALOG_LOCAL_PORT:-5101}"
CATALOG_URL="http://127.0.0.1:${CATALOG_LOCAL_PORT}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"

PORT_FORWARD_PID=""
TEMP_DIRECTORY=""
TEST_PRODUCT_ID=""

TEST_SKU="K8S-PERSISTENCE-$(date +%s)-${RANDOM}"

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

echo "============================================================"
echo "Database persistence test"
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
  --for=condition=Ready \
  pod/"${DB_POD}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

kubectl wait \
  --for=condition=Available \
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo "PASS: Catalog and database are healthy."

echo
echo "2. Capturing database Pod and storage identity..."

OLD_DB_UID="$(
  kubectl get pod \
    "${DB_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.metadata.uid}'
)"

DB_PVC="$(
  kubectl get pod \
    "${DB_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}'
)"

if [[ -z "${DB_PVC}" ]]; then
  echo "Could not determine database PVC." >&2
  exit 1
fi

DB_PV="$(
  kubectl get pvc \
    "${DB_PVC}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.volumeName}'
)"

if [[ -z "${DB_PV}" ]]; then
  echo "Could not determine PersistentVolume." >&2
  exit 1
fi

echo "Pod:     ${DB_POD}"
echo "Pod UID: ${OLD_DB_UID}"
echo "PVC:     ${DB_PVC}"
echo "PV:      ${DB_PV}"

echo
echo "3. Starting Catalog port-forward..."

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
    "${CATALOG_URL}/health/ready" \
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

echo "PASS: Catalog is reachable."

echo
echo "4. Creating persistent test data..."

CREATE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${CREATE_RESPONSE}" \
    --write-out '%{http_code}' \
    --request POST \
    --header 'Content-Type: application/json' \
    --data "{
      \"name\": \"Kubernetes Persistence Test\",
      \"description\": \"Product created before PostgreSQL Pod restart\",
      \"sku\": \"${TEST_SKU}\"
    }" \
    "${CATALOG_URL}/api/v1/catalog-products"
)"

if [[ "${CREATE_STATUS}" != "201" ]]; then
  echo "Expected HTTP 201, got ${CREATE_STATUS}." >&2
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

echo
echo "5. Verifying data before database restart..."

BEFORE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRODUCT_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${BEFORE_STATUS}" != "200" ]]; then
  echo "Product was not readable before restart." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

if ! grep -Fq "${TEST_SKU}" "${PRODUCT_RESPONSE}"; then
  echo "Expected SKU was not found before restart." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Test data exists before restart."

echo
echo "6. Deleting PostgreSQL Pod..."

kubectl delete pod \
  "${DB_POD}" \
  --namespace "${NAMESPACE}" \
  --wait=false

echo
echo "7. Waiting for replacement Pod object..."

NEW_DB_UID=""

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  NEW_DB_UID="$(
    kubectl get pod \
      "${DB_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.metadata.uid}' \
      2>/dev/null || true
  )"

  if [[ -n "${NEW_DB_UID}" &&
        "${NEW_DB_UID}" != "${OLD_DB_UID}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${NEW_DB_UID}" ||
      "${NEW_DB_UID}" == "${OLD_DB_UID}" ]]; then

  echo "Replacement database Pod was not observed." >&2
  exit 1
fi

echo "Old UID: ${OLD_DB_UID}"
echo "New UID: ${NEW_DB_UID}"

echo "PASS: StatefulSet created a new Pod object."

echo
echo "8. Waiting for database readiness..."

kubectl wait \
  --for=condition=Ready \
  pod/"${DB_POD}" \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: Replacement database Pod is Ready."

echo
echo "9. Verifying persistent storage identity..."

NEW_DB_PVC="$(
  kubectl get pod \
    "${DB_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}'
)"

NEW_DB_PV="$(
  kubectl get pvc \
    "${NEW_DB_PVC}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.volumeName}'
)"

echo "PVC before: ${DB_PVC}"
echo "PVC after:  ${NEW_DB_PVC}"
echo
echo "PV before:  ${DB_PV}"
echo "PV after:   ${NEW_DB_PV}"

if [[ "${NEW_DB_PVC}" != "${DB_PVC}" ]]; then
  echo "Database Pod did not reuse the same PVC." >&2
  exit 1
fi

if [[ "${NEW_DB_PV}" != "${DB_PV}" ]]; then
  echo "PVC does not reference the original PersistentVolume." >&2
  exit 1
fi

echo "PASS: Replacement Pod reused the same persistent storage."

echo
echo "10. Waiting for Catalog readiness recovery..."

CATALOG_READY="false"

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  STATUS="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 3 \
      "${CATALOG_URL}/health/ready" \
      2>/dev/null || true
  )"

  if [[ "${STATUS}" == "200" ]]; then
    CATALOG_READY="true"
    break
  fi

  sleep 1
done

if [[ "${CATALOG_READY}" != "true" ]]; then
  echo "Catalog did not recover after database restart." >&2
  exit 1
fi

echo "PASS: Catalog recovered."

echo
echo "11. Verifying data after database restart..."

AFTER_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRODUCT_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${AFTER_STATUS}" != "200" ]]; then
  echo "Product was not readable after database restart." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

if ! grep -Fq "${TEST_SKU}" "${PRODUCT_RESPONSE}"; then
  echo "Persistent test data was lost." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Test data survived PostgreSQL Pod replacement."

echo
echo "============================================================"
echo "DATABASE PERSISTENCE TEST PASSED."
echo "============================================================"