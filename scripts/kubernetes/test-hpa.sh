#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

DEPLOYMENT="${DEPLOYMENT:-pricing-service}"
HPA_NAME="${HPA_NAME:-pricing-service}"

KONG_NAMESPACE="${KONG_NAMESPACE:-kong}"
LOCAL_PORT="${LOCAL_PORT:-8088}"

LOAD_WORKERS="${LOAD_WORKERS:-20}"

SCALE_UP_TIMEOUT="${SCALE_UP_TIMEOUT:-180}"
SCALE_DOWN_TIMEOUT="${SCALE_DOWN_TIMEOUT:-240}"

PORT_FORWARD_PID=""
TEMP_DIRECTORY=""

LOAD_PIDS=()

cleanup() {
  local original_exit_code=$?

  set +e

  for pid in "${LOAD_PIDS[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done

  for pid in "${LOAD_PIDS[@]:-}"; do
    wait "${pid}" >/dev/null 2>&1 || true
  done

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

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_command minikube
require_command kubectl
require_command curl
require_command awk
require_command mktemp

TEMP_DIRECTORY="$(mktemp -d)"
PORT_FORWARD_LOG="${TEMP_DIRECTORY}/kong-port-forward.log"

BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
PRICING_URL="${BASE_URL}/api/v1/prices/00000000-0000-0000-0000-000000000001"

echo "============================================================"
echo "Horizontal Pod Autoscaler test"
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
echo "2. Checking Metrics API..."

AVAILABLE="$(
  kubectl get apiservice \
    v1beta1.metrics.k8s.io \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' \
    2>/dev/null || true
)"

if [[ "${AVAILABLE}" != "True" ]]; then
  echo "Metrics API is not available." >&2
  echo "Run ./scripts/kubernetes/setup-hpa.sh first." >&2
  exit 1
fi

echo "PASS: Metrics API is available."

echo
echo "3. Checking Pod metrics..."

if ! kubectl top pods \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "Pod metrics are not currently available." >&2
  exit 1
fi

echo "PASS: Pod metrics are available."

echo
echo "4. Checking HPA..."

if ! kubectl get hpa \
  "${HPA_NAME}" \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "HPA '${HPA_NAME}' was not found." >&2
  exit 1
fi

kubectl get hpa \
  "${HPA_NAME}" \
  --namespace "${NAMESPACE}"

echo
echo "5. Waiting for one-replica baseline..."

BASELINE_READY="false"

for ((attempt = 1; attempt <= SCALE_DOWN_TIMEOUT; attempt++)); do
  REPLICAS="$(
    kubectl get deployment \
      "${DEPLOYMENT}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.spec.replicas}'
  )"

  AVAILABLE_REPLICAS="$(
    kubectl get deployment \
      "${DEPLOYMENT}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.availableReplicas}'
  )"

  AVAILABLE_REPLICAS="${AVAILABLE_REPLICAS:-0}"

  if [[ "${REPLICAS}" == "1" &&
        "${AVAILABLE_REPLICAS}" == "1" ]]; then

    BASELINE_READY="true"
    break
  fi

  sleep 1
done

if [[ "${BASELINE_READY}" != "true" ]]; then
  echo "Pricing Service did not reach one-replica baseline." >&2
  exit 1
fi

echo "PASS: Pricing baseline is one replica."

echo
echo "6. Finding Kong proxy..."

KONG_PROXY_SERVICE="$(
  kubectl get services \
    --namespace "${KONG_NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .spec.ports[*]}{.port}{" "}{end}{"\n"}{end}' |
  awk '$1 ~ /proxy/ && $0 ~ /(^| )80( |$)/ { print $1; exit }'
)"

if [[ -z "${KONG_PROXY_SERVICE}" ]]; then
  echo "Could not find Kong proxy Service." >&2
  exit 1
fi

echo "Kong proxy: ${KONG_PROXY_SERVICE}"

echo
echo "7. Starting Kong port-forward..."

kubectl port-forward \
  --namespace "${KONG_NAMESPACE}" \
  service/"${KONG_PROXY_SERVICE}" \
  "${LOCAL_PORT}:80" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

ROUTE_READY="false"

for ((attempt = 1; attempt <= 30; attempt++)); do
  STATUS="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 3 \
      "${PRICING_URL}" \
      2>/dev/null || true
  )"

  if [[ "${STATUS}" == "404" ]]; then
    ROUTE_READY="true"
    break
  fi

  sleep 1
done

if [[ "${ROUTE_READY}" != "true" ]]; then
  echo "Pricing route through Kong is not available." >&2
  cat "${PORT_FORWARD_LOG}" >&2
  exit 1
fi

echo "PASS: Pricing route is reachable."

echo
echo "8. Starting ${LOAD_WORKERS} load workers..."

for ((worker = 1; worker <= LOAD_WORKERS; worker++)); do
  (
    while true; do
      curl \
        --silent \
        --output /dev/null \
        --max-time 3 \
        "${PRICING_URL}" \
        || true
    done
  ) &

  LOAD_PIDS+=("$!")
done

echo "PASS: Load generation started."

echo
echo "9. Waiting for HPA scale-up..."

SCALE_UP_OBSERVED="false"
MAX_OBSERVED_REPLICAS=1

for ((attempt = 1; attempt <= SCALE_UP_TIMEOUT; attempt++)); do
  REPLICAS="$(
    kubectl get deployment \
      "${DEPLOYMENT}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.spec.replicas}'
  )"

  CURRENT_CPU="$(
    kubectl get hpa \
      "${HPA_NAME}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' \
      2>/dev/null || true
  )"

  echo "Replicas=${REPLICAS}, CPU=${CURRENT_CPU:-unknown}%"

  if [[ "${REPLICAS}" =~ ^[0-9]+$ ]] &&
     ((REPLICAS > MAX_OBSERVED_REPLICAS)); then

    MAX_OBSERVED_REPLICAS="${REPLICAS}"
  fi

  if [[ "${REPLICAS}" =~ ^[0-9]+$ ]] &&
     ((REPLICAS > 1)); then

    SCALE_UP_OBSERVED="true"
    break
  fi

  sleep 2
done

if [[ "${SCALE_UP_OBSERVED}" != "true" ]]; then
  echo "HPA did not scale Pricing above one replica." >&2
  echo >&2

  kubectl describe hpa \
    "${HPA_NAME}" \
    --namespace "${NAMESPACE}" \
    >&2

  echo >&2
  kubectl top pods \
    --namespace "${NAMESPACE}" \
    >&2 || true

  exit 1
fi

echo "PASS: HPA scaled Pricing to ${MAX_OBSERVED_REPLICAS} replicas."

echo
echo "10. Current HPA and Pods..."

kubectl get hpa \
  "${HPA_NAME}" \
  --namespace "${NAMESPACE}"

kubectl get pods \
  --namespace "${NAMESPACE}" \
  --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api'

echo
echo "11. Stopping load..."

for pid in "${LOAD_PIDS[@]}"; do
  kill "${pid}" >/dev/null 2>&1 || true
done

for pid in "${LOAD_PIDS[@]}"; do
  wait "${pid}" >/dev/null 2>&1 || true
done

LOAD_PIDS=()

echo "PASS: Load stopped."

echo
echo "12. Waiting for HPA scale-down..."

SCALE_DOWN_OBSERVED="false"

for ((attempt = 1; attempt <= SCALE_DOWN_TIMEOUT; attempt++)); do
  REPLICAS="$(
    kubectl get deployment \
      "${DEPLOYMENT}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.spec.replicas}'
  )"

  CURRENT_CPU="$(
    kubectl get hpa \
      "${HPA_NAME}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' \
      2>/dev/null || true
  )"

  echo "Replicas=${REPLICAS}, CPU=${CURRENT_CPU:-unknown}%"

  if [[ "${REPLICAS}" == "1" ]]; then
    SCALE_DOWN_OBSERVED="true"
    break
  fi

  sleep 2
done

if [[ "${SCALE_DOWN_OBSERVED}" != "true" ]]; then
  echo "HPA did not scale Pricing back to one replica." >&2

  kubectl describe hpa \
    "${HPA_NAME}" \
    --namespace "${NAMESPACE}" \
    >&2

  exit 1
fi

echo "PASS: HPA scaled Pricing back to one replica."

echo
echo "13. Final HPA status..."

kubectl get hpa \
  "${HPA_NAME}" \
  --namespace "${NAMESPACE}"

echo
echo "14. HPA conditions..."

kubectl describe hpa \
  "${HPA_NAME}" \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "HPA TEST PASSED."
echo "============================================================"