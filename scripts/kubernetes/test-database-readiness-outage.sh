#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

CATALOG_DEPLOYMENT="${CATALOG_DEPLOYMENT:-catalog-service}"
CATALOG_DB_STATEFULSET="${CATALOG_DB_STATEFULSET:-catalog-service-db}"
CATALOG_DB_POD="${CATALOG_DB_POD:-catalog-service-db-0}"

LOCAL_PORT="${LOCAL_PORT:-5105}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-3}"

PORT_FORWARD_PID=""
TEMP_DIRECTORY=""

ORIGINAL_DB_REPLICAS=""
RESTORE_REQUIRED="false"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

restore_database() {
  if [[ "${RESTORE_REQUIRED}" != "true" ||
        -z "${ORIGINAL_DB_REPLICAS}" ]]; then
    return
  fi

  echo
  echo "Restoring Catalog database replicas to ${ORIGINAL_DB_REPLICAS}..."

  kubectl scale statefulset \
    "${CATALOG_DB_STATEFULSET}" \
    --replicas="${ORIGINAL_DB_REPLICAS}" \
    --namespace "${NAMESPACE}" \
    >/dev/null

  if ((ORIGINAL_DB_REPLICAS > 0)); then
    kubectl wait \
      --for=condition=Ready \
      pod/"${CATALOG_DB_POD}" \
      --namespace "${NAMESPACE}" \
      --timeout="${WAIT_TIMEOUT}s" \
      >/dev/null
  fi

  RESTORE_REQUIRED="false"
}

cleanup() {
  local original_exit_code=$?

  set +e

  restore_database || true

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

port_forward_is_running() {
  [[ -n "${PORT_FORWARD_PID}" ]] &&
    kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1
}

get_http_status() {
  local url="$1"
  local output_file="$2"

  local status
  local curl_exit_code

  set +e

  status="$(
    curl \
      --silent \
      --show-error \
      --output "${output_file}" \
      --write-out '%{http_code}' \
      --connect-timeout 2 \
      --max-time "${HTTP_TIMEOUT}" \
      "${url}" \
      2>/dev/null
  )"

  curl_exit_code=$?

  set -e

  printf '%s %s\n' \
    "${status:-000}" \
    "${curl_exit_code}"
}

require_command minikube
require_command kubectl
require_command curl
require_command awk
require_command mktemp

TEMP_DIRECTORY="$(mktemp -d)"

PORT_FORWARD_LOG="${TEMP_DIRECTORY}/catalog-port-forward.log"
HTTP_RESPONSE="${TEMP_DIRECTORY}/http-response.txt"

CATALOG_URL="http://127.0.0.1:${LOCAL_PORT}"

echo "============================================================"
echo "Database readiness outage test"
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
  deployment/"${CATALOG_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

kubectl wait \
  --for=condition=Ready \
  pod/"${CATALOG_DB_POD}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

ORIGINAL_DB_REPLICAS="$(
  kubectl get statefulset \
    "${CATALOG_DB_STATEFULSET}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

if ! [[ "${ORIGINAL_DB_REPLICAS}" =~ ^[0-9]+$ ]] ||
   ((ORIGINAL_DB_REPLICAS < 1)); then

  echo "Catalog database must have at least one replica before the test." >&2
  exit 1
fi

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

RESTARTS_BEFORE="$(
  kubectl get pod \
    "${CATALOG_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}'
)"

echo "Catalog Pod:           ${CATALOG_POD}"
echo "Catalog DB replicas:   ${ORIGINAL_DB_REPLICAS}"
echo "Catalog restart count: ${RESTARTS_BEFORE}"

echo
echo "2. Starting direct Catalog Pod port-forward..."

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  pod/"${CATALOG_POD}" \
  "${LOCAL_PORT}:8080" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

CATALOG_REACHABLE="false"

for ((attempt = 1; attempt <= 30; attempt++)); do
  if ! port_forward_is_running; then
    echo "Catalog port-forward terminated unexpectedly." >&2
    cat "${PORT_FORWARD_LOG}" >&2
    exit 1
  fi

  read -r LIVE_STATUS LIVE_CURL_EXIT < <(
    get_http_status \
      "${CATALOG_URL}/health/live" \
      "${HTTP_RESPONSE}"
  )

  if [[ "${LIVE_CURL_EXIT}" == "0" &&
        "${LIVE_STATUS}" == "200" ]]; then

    CATALOG_REACHABLE="true"
    break
  fi

  sleep 1
done

if [[ "${CATALOG_REACHABLE}" != "true" ]]; then
  echo "Could not reach Catalog Pod directly." >&2
  cat "${PORT_FORWARD_LOG}" >&2
  exit 1
fi

echo "PASS: Catalog Pod is directly reachable."

echo
echo "3. Verifying healthy baseline..."

read -r LIVE_STATUS LIVE_CURL_EXIT < <(
  get_http_status \
    "${CATALOG_URL}/health/live" \
    "${HTTP_RESPONSE}"
)

read -r READY_STATUS READY_CURL_EXIT < <(
  get_http_status \
    "${CATALOG_URL}/health/ready" \
    "${HTTP_RESPONSE}"
)

echo "Liveness:  HTTP ${LIVE_STATUS}, curl exit ${LIVE_CURL_EXIT}"
echo "Readiness: HTTP ${READY_STATUS}, curl exit ${READY_CURL_EXIT}"

if [[ "${LIVE_CURL_EXIT}" != "0" ||
      "${LIVE_STATUS}" != "200" ||
      "${READY_CURL_EXIT}" != "0" ||
      "${READY_STATUS}" != "200" ]]; then

  echo "Expected healthy Catalog baseline." >&2
  exit 1
fi

echo "PASS: Catalog is Live and Ready."

RESTORE_REQUIRED="true"

echo
echo "4. Scaling Catalog database to zero..."

kubectl scale statefulset \
  "${CATALOG_DB_STATEFULSET}" \
  --replicas=0 \
  --namespace "${NAMESPACE}"

echo
echo "5. Waiting for database Pod termination..."

DATABASE_UNAVAILABLE="false"

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  if ! kubectl get pod \
    "${CATALOG_DB_POD}" \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then

    DATABASE_UNAVAILABLE="true"
    break
  fi

  sleep 1
done

if [[ "${DATABASE_UNAVAILABLE}" != "true" ]]; then
  echo "Catalog database Pod did not terminate." >&2
  exit 1
fi

echo "PASS: Catalog database is unavailable."

echo
echo "6. Waiting for Catalog readiness failure..."

READINESS_FAILED="false"
READY_STATUS=""
READY_CURL_EXIT=""

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  if ! port_forward_is_running; then
    echo "Catalog port-forward terminated unexpectedly." >&2
    cat "${PORT_FORWARD_LOG}" >&2
    exit 1
  fi

  read -r READY_STATUS READY_CURL_EXIT < <(
    get_http_status \
      "${CATALOG_URL}/health/ready" \
      "${HTTP_RESPONSE}"
  )

  if [[ "${READY_CURL_EXIT}" != "0" ||
        "${READY_STATUS}" != "200" ]]; then

    READINESS_FAILED="true"
    break
  fi

  sleep 1
done

if [[ "${READINESS_FAILED}" != "true" ]]; then
  echo "Catalog readiness remained healthy during database outage." >&2
  exit 1
fi

if [[ "${READY_CURL_EXIT}" == "0" ]]; then
  echo "PASS: Catalog readiness failed with HTTP ${READY_STATUS}."
else
  echo "PASS: Catalog readiness request failed as expected."
  echo "      curl exit=${READY_CURL_EXIT}, HTTP=${READY_STATUS}"
fi

echo
echo "7. Verifying liveness remains healthy..."

read -r LIVE_STATUS LIVE_CURL_EXIT < <(
  get_http_status \
    "${CATALOG_URL}/health/live" \
    "${HTTP_RESPONSE}"
)

if [[ "${LIVE_CURL_EXIT}" != "0" ||
      "${LIVE_STATUS}" != "200" ]]; then

  echo "Catalog liveness unexpectedly failed." >&2
  echo "HTTP: ${LIVE_STATUS}" >&2
  echo "curl exit: ${LIVE_CURL_EXIT}" >&2
  exit 1
fi

echo "PASS: Catalog liveness remains HTTP 200."

echo
echo "8. Waiting for Pod Ready=False..."

POD_READY=""
POD_NOT_READY="false"

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  POD_READY="$(
    kubectl get pod \
      "${CATALOG_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
      2>/dev/null || true
  )"

  if [[ "${POD_READY}" == "False" ]]; then
    POD_NOT_READY="true"
    break
  fi

  sleep 1
done

if [[ "${POD_NOT_READY}" != "true" ]]; then
  echo "Catalog Pod did not transition to Ready=False." >&2
  echo "Last Ready condition: ${POD_READY:-unknown}" >&2
  exit 1
fi

echo "PASS: Catalog Pod is Running but NotReady."

echo
echo "9. Verifying Service has no Ready Catalog endpoint..."

READY_ENDPOINTS="$(
  kubectl get endpointslices \
    --namespace "${NAMESPACE}" \
    --selector='kubernetes.io/service-name=catalog-service' \
    -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{" "}{.conditions.ready}{"\n"}{end}' |
  awk '$2 == "true" { print }'
)"

if [[ -n "${READY_ENDPOINTS}" ]]; then
  echo "Catalog Service unexpectedly has a Ready endpoint:" >&2
  printf '%s\n' "${READY_ENDPOINTS}" >&2
  exit 1
fi

echo "PASS: Catalog Service has no Ready backend."

echo
echo "10. Verifying container was not restarted..."

RESTARTS_DURING_OUTAGE="$(
  kubectl get pod \
    "${CATALOG_POD}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}'
)"

echo "Before outage: ${RESTARTS_BEFORE}"
echo "During outage: ${RESTARTS_DURING_OUTAGE}"

if [[ "${RESTARTS_DURING_OUTAGE}" != "${RESTARTS_BEFORE}" ]]; then
  echo "Catalog container unexpectedly restarted." >&2
  exit 1
fi

echo "PASS: Readiness failure did not restart the container."

echo
echo "11. Restoring Catalog database..."

kubectl scale statefulset \
  "${CATALOG_DB_STATEFULSET}" \
  --replicas="${ORIGINAL_DB_REPLICAS}" \
  --namespace "${NAMESPACE}"

kubectl wait \
  --for=condition=Ready \
  pod/"${CATALOG_DB_POD}" \
  --namespace "${NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: Catalog database recovered."

echo
echo "12. Waiting for Catalog readiness recovery..."

READINESS_RECOVERED="false"
READY_STATUS=""
READY_CURL_EXIT=""

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  if ! port_forward_is_running; then
    echo "Catalog port-forward terminated unexpectedly." >&2
    cat "${PORT_FORWARD_LOG}" >&2
    exit 1
  fi

  read -r READY_STATUS READY_CURL_EXIT < <(
    get_http_status \
      "${CATALOG_URL}/health/ready" \
      "${HTTP_RESPONSE}"
  )

  if [[ "${READY_CURL_EXIT}" == "0" &&
        "${READY_STATUS}" == "200" ]]; then

    READINESS_RECOVERED="true"
    break
  fi

  sleep 1
done

if [[ "${READINESS_RECOVERED}" != "true" ]]; then
  echo "Catalog readiness did not recover." >&2
  echo "Last HTTP status: ${READY_STATUS:-unknown}" >&2
  echo "Last curl exit: ${READY_CURL_EXIT:-unknown}" >&2
  exit 1
fi

echo "PASS: Catalog readiness returned HTTP 200."

echo
echo "13. Waiting for Pod Ready=True..."

kubectl wait \
  --for=condition=Ready \
  pod/"${CATALOG_POD}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo "PASS: Catalog Pod is Ready again."

echo
echo "14. Verifying Service endpoint recovery..."

READY_ENDPOINTS=""
ENDPOINT_RECOVERED="false"

for ((attempt = 1; attempt <= 60; attempt++)); do
  READY_ENDPOINTS="$(
    kubectl get endpointslices \
      --namespace "${NAMESPACE}" \
      --selector='kubernetes.io/service-name=catalog-service' \
      -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{" "}{.conditions.ready}{"\n"}{end}' |
    awk '$2 == "true" { print }'
  )"

  if [[ -n "${READY_ENDPOINTS}" ]]; then
    ENDPOINT_RECOVERED="true"
    break
  fi

  sleep 1
done

if [[ "${ENDPOINT_RECOVERED}" != "true" ]]; then
  echo "Catalog Service Ready endpoint did not recover." >&2
  exit 1
fi

printf '%s\n' "${READY_ENDPOINTS}"

echo "PASS: Catalog Service backend recovered."

RESTORE_REQUIRED="false"

echo
echo "============================================================"
echo "DATABASE READINESS OUTAGE TEST PASSED."
echo "============================================================"