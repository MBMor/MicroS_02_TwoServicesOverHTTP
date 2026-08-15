#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
LOCAL_PORT="${LOCAL_PORT:-5102}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-30}"

SERVICE_NAME="pricing-service"
BASE_URL="http://127.0.0.1:${LOCAL_PORT}"

PORT_FORWARD_PID=""
PORT_FORWARD_LOG=""

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]] &&
     kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${PORT_FORWARD_LOG}" &&
        -f "${PORT_FORWARD_LOG}" ]]; then
    rm -f "${PORT_FORWARD_LOG}"
  fi
}

trap cleanup EXIT INT TERM

require_command minikube
require_command kubectl
require_command curl
require_command mktemp

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  echo "Run ./scripts/kubernetes/start-cluster.sh first." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

if ! kubectl get deployment \
  "${SERVICE_NAME}" \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then
  echo "Deployment '${SERVICE_NAME}' does not exist." >&2
  echo "Run ./scripts/kubernetes/deploy-pricing-service.sh first." >&2
  exit 1
fi

echo "Waiting for Pricing Service Deployment availability..."

kubectl wait \
  --for=condition=Available \
  deployment/"${SERVICE_NAME}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo
echo "Pricing Service resources:"

kubectl get \
  deployment,replicaset,pod,service \
  --namespace "${NAMESPACE}" \
  --selector='app.kubernetes.io/name=pricing-service' \
  -o wide

echo
echo "Pricing Service EndpointSlices:"

kubectl get endpointslices \
  --namespace "${NAMESPACE}" \
  --selector="kubernetes.io/service-name=${SERVICE_NAME}"

PORT_FORWARD_LOG="$(mktemp)"

echo
echo "Starting port-forward on local port ${LOCAL_PORT}..."

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  service/"${SERVICE_NAME}" \
  "${LOCAL_PORT}:80" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

for ((attempt = 1; attempt <= WAIT_TIMEOUT_SECONDS; attempt++)); do
  if ! kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
    echo "Port-forward terminated unexpectedly." >&2
    cat "${PORT_FORWARD_LOG}" >&2
    exit 1
  fi

  if curl \
    --silent \
    --fail \
    --max-time 2 \
    "${BASE_URL}/health/live" \
    >/dev/null; then
    break
  fi

  if ((attempt == WAIT_TIMEOUT_SECONDS)); then
    echo "Pricing Service did not become reachable." >&2
    cat "${PORT_FORWARD_LOG}" >&2
    exit 1
  fi

  sleep 1
done

echo
echo "Checking liveness endpoint..."

curl \
  --fail \
  --silent \
  --show-error \
  "${BASE_URL}/health/live"

echo
echo
echo "Checking readiness endpoint..."

curl \
  --fail \
  --silent \
  --show-error \
  "${BASE_URL}/health/ready"

echo
echo
echo "Pricing Service verification completed successfully."