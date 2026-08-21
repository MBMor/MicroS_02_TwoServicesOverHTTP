#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

PROBE_NAMESPACE="${PROBE_NAMESPACE:-default}"
PROBE_NAME="${PROBE_NAME:-network-policy-probe}"

KONG_NAMESPACE="${KONG_NAMESPACE:-kong}"
KONG_LOCAL_PORT="${KONG_LOCAL_PORT:-8088}"

PORT_FORWARD_PID=""

cleanup() {
  local original_exit_code=$?

  set +e

  kubectl delete pod \
    "${PROBE_NAME}" \
    --namespace "${PROBE_NAMESPACE}" \
    --ignore-not-found \
    --wait=false \
    >/dev/null 2>&1 || true

  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
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
require_command awk
require_command curl
require_command mktemp

echo "============================================================"
echo "Kubernetes NetworkPolicy test"
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
echo "2. Checking NetworkPolicies..."

POLICY_COUNT="$(
  kubectl get networkpolicies \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/component=network-policy' \
    --no-headers \
    2>/dev/null |
  wc -l |
  tr -d ' '
)"

if ! [[ "${POLICY_COUNT}" =~ ^[0-9]+$ ]] ||
   ((POLICY_COUNT < 8)); then

  echo "Expected at least 8 NetworkPolicy objects." >&2
  echo "Found: ${POLICY_COUNT}" >&2

  kubectl get networkpolicies \
    --namespace "${NAMESPACE}" \
    >&2

  exit 1
fi

echo "PASS: ${POLICY_COUNT} NetworkPolicies found."

echo
echo "3. Finding application Pods..."

CATALOG_POD="$(
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/name=catalog-service,app.kubernetes.io/component=api' \
    -o jsonpath='{.items[0].metadata.name}'
)"

PRICING_POD="$(
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api' \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${CATALOG_POD}" ||
      -z "${PRICING_POD}" ]]; then

  echo "Could not find Catalog or Pricing Pod." >&2
  exit 1
fi

echo "Catalog: ${CATALOG_POD}"
echo "Pricing: ${PRICING_POD}"

echo
echo "4. Testing Catalog -> Pricing..."

CATALOG_TO_PRICING_STATUS="$(
  MSYS_NO_PATHCONV=1 kubectl exec \
    --namespace "${NAMESPACE}" \
    "${CATALOG_POD}" \
    -- \
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 5 \
      http://pricing-service/health/live
)"

if [[ "${CATALOG_TO_PRICING_STATUS}" != "200" ]]; then
  echo "Catalog could not reach Pricing." >&2
  echo "HTTP: ${CATALOG_TO_PRICING_STATUS}" >&2
  exit 1
fi

echo "PASS: Catalog -> Pricing returned HTTP 200."

echo
echo "5. Testing Catalog -> Catalog DB through readiness..."

CATALOG_READY_STATUS="$(
  MSYS_NO_PATHCONV=1 kubectl exec \
    --namespace "${NAMESPACE}" \
    "${CATALOG_POD}" \
    -- \
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      http://127.0.0.1:8080/health/ready
)"

if [[ "${CATALOG_READY_STATUS}" != "200" ]]; then
  echo "Catalog readiness failed." >&2
  exit 1
fi

echo "PASS: Catalog database connectivity is available."

echo
echo "6. Testing Pricing -> Pricing DB through readiness..."

PRICING_READY_STATUS="$(
  MSYS_NO_PATHCONV=1 kubectl exec \
    --namespace "${NAMESPACE}" \
    "${PRICING_POD}" \
    -- \
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      http://127.0.0.1:8080/health/ready
)"

if [[ "${PRICING_READY_STATUS}" != "200" ]]; then
  echo "Pricing readiness failed." >&2
  exit 1
fi

echo "PASS: Pricing database connectivity is available."

echo
echo "7. Finding Kong proxy..."

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

PORT_FORWARD_LOG="$(mktemp)"

kubectl port-forward \
  --namespace "${KONG_NAMESPACE}" \
  service/"${KONG_PROXY_SERVICE}" \
  "${KONG_LOCAL_PORT}:80" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

echo
echo "8. Testing Kong -> Catalog..."

KONG_CATALOG_STATUS=""

for ((attempt = 1; attempt <= 30; attempt++)); do
  KONG_CATALOG_STATUS="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 3 \
      "http://127.0.0.1:${KONG_LOCAL_PORT}/api/v1/catalog-products" \
      2>/dev/null || true
  )"

  if [[ "${KONG_CATALOG_STATUS}" == "200" ]]; then
    break
  fi

  sleep 1
done

if [[ "${KONG_CATALOG_STATUS}" != "200" ]]; then
  echo "Kong could not reach Catalog through Ingress." >&2
  cat "${PORT_FORWARD_LOG}" >&2
  exit 1
fi

echo "PASS: Kong -> Catalog is allowed."

echo
echo "9. Testing Kong -> Pricing..."

KONG_PRICING_STATUS="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 5 \
    "http://127.0.0.1:${KONG_LOCAL_PORT}/api/v1/prices/00000000-0000-0000-0000-000000000001"
)"

if [[ "${KONG_PRICING_STATUS}" != "404" ]]; then
  echo "Expected Pricing HTTP 404 through Kong." >&2
  echo "Actual: ${KONG_PRICING_STATUS}" >&2
  exit 1
fi

echo "PASS: Kong -> Pricing is allowed."

echo
echo "10. Creating unauthorized external-namespace probe..."

PROBE_IMAGE="$(
  kubectl get deployment \
    catalog-service \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
)"

kubectl delete pod \
  "${PROBE_NAME}" \
  --namespace "${PROBE_NAMESPACE}" \
  --ignore-not-found \
  >/dev/null

kubectl run \
  "${PROBE_NAME}" \
  --namespace "${PROBE_NAMESPACE}" \
  --image="${PROBE_IMAGE}" \
  --image-pull-policy=IfNotPresent \
  --restart=Never \
  --command \
  -- \
  sh -ec 'sleep 300'

kubectl wait \
  --for=condition=Ready \
  pod/"${PROBE_NAME}" \
  --namespace "${PROBE_NAMESPACE}" \
  --timeout=60s

echo "PASS: Unauthorized probe is running."

echo
echo "11. Verifying unauthorized probe cannot reach Catalog..."

if kubectl exec \
  --namespace "${PROBE_NAMESPACE}" \
  "${PROBE_NAME}" \
  -- \
  curl \
    --connect-timeout 3 \
    --max-time 5 \
    --fail \
    --silent \
    --output /dev/null \
    "http://catalog-service.${NAMESPACE}.svc.cluster.local/health/live"; then

  echo "Unauthorized probe unexpectedly reached Catalog." >&2
  exit 1
fi

echo "PASS: Unauthorized Catalog access is blocked."

echo
echo "12. Verifying unauthorized probe cannot reach Pricing..."

if kubectl exec \
  --namespace "${PROBE_NAMESPACE}" \
  "${PROBE_NAME}" \
  -- \
  curl \
    --connect-timeout 3 \
    --max-time 5 \
    --fail \
    --silent \
    --output /dev/null \
    "http://pricing-service.${NAMESPACE}.svc.cluster.local/health/live"; then

  echo "Unauthorized probe unexpectedly reached Pricing." >&2
  exit 1
fi

echo "PASS: Unauthorized Pricing access is blocked."

echo
echo "13. Current NetworkPolicies..."

kubectl get networkpolicies \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "NETWORK POLICY TEST PASSED."
echo "============================================================"