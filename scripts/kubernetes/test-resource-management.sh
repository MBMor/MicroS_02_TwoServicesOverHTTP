#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

assert_resource() {
  local kind="$1"
  local name="$2"
  local container="$3"
  local resource_path="$4"
  local expected="$5"

  local actual

  actual="$(
    kubectl get "${kind}" \
      "${name}" \
      --namespace "${NAMESPACE}" \
      -o "jsonpath={.spec.template.spec.containers[?(@.name==\"${container}\")].resources.${resource_path}}"
  )"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "Resource validation failed." >&2
    echo "Workload: ${kind}/${name}" >&2
    echo "Container: ${container}" >&2
    echo "Resource: ${resource_path}" >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${actual:-<empty>}" >&2
    exit 1
  fi
}

assert_qos() {
  local selector="$1"
  local expected="$2"

  local pods

  pods="$(
    kubectl get pods \
      --namespace "${NAMESPACE}" \
      --selector="${selector}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.qosClass}{"\n"}{end}'
  )"

  if [[ -z "${pods}" ]]; then
    echo "No Pods found for selector '${selector}'." >&2
    exit 1
  fi

  while read -r pod qos; do
    [[ -z "${pod}" ]] && continue

    echo "${pod}: ${qos}"

    if [[ "${qos}" != "${expected}" ]]; then
      echo "Expected QoS '${expected}' for Pod '${pod}', got '${qos}'." >&2
      exit 1
    fi
  done <<< "${pods}"
}

require_command minikube
require_command kubectl

echo "============================================================"
echo "Kubernetes resource management test"
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
echo "2. Validating Catalog API resources..."

assert_resource \
  deployment \
  catalog-service \
  catalog-service \
  requests.cpu \
  100m

assert_resource \
  deployment \
  catalog-service \
  catalog-service \
  requests.memory \
  128Mi

assert_resource \
  deployment \
  catalog-service \
  catalog-service \
  limits.cpu \
  500m

assert_resource \
  deployment \
  catalog-service \
  catalog-service \
  limits.memory \
  512Mi

echo "PASS: Catalog API resources are correct."

echo
echo "3. Validating Pricing API resources..."

assert_resource \
  deployment \
  pricing-service \
  pricing-service \
  requests.cpu \
  100m

assert_resource \
  deployment \
  pricing-service \
  pricing-service \
  requests.memory \
  128Mi

assert_resource \
  deployment \
  pricing-service \
  pricing-service \
  limits.cpu \
  500m

assert_resource \
  deployment \
  pricing-service \
  pricing-service \
  limits.memory \
  512Mi

echo "PASS: Pricing API resources are correct."

echo
echo "4. Validating Catalog PostgreSQL resources..."

assert_resource \
  statefulset \
  catalog-service-db \
  postgres \
  requests.cpu \
  100m

assert_resource \
  statefulset \
  catalog-service-db \
  postgres \
  requests.memory \
  256Mi

assert_resource \
  statefulset \
  catalog-service-db \
  postgres \
  limits.cpu \
  1

assert_resource \
  statefulset \
  catalog-service-db \
  postgres \
  limits.memory \
  1Gi

echo "PASS: Catalog database resources are correct."

echo
echo "5. Validating Pricing PostgreSQL resources..."

assert_resource \
  statefulset \
  pricing-service-db \
  postgres \
  requests.cpu \
  100m

assert_resource \
  statefulset \
  pricing-service-db \
  postgres \
  requests.memory \
  256Mi

assert_resource \
  statefulset \
  pricing-service-db \
  postgres \
  limits.cpu \
  1

assert_resource \
  statefulset \
  pricing-service-db \
  postgres \
  limits.memory \
  1Gi

echo "PASS: Pricing database resources are correct."

echo
echo "6. Validating migration resources..."

assert_resource \
  job \
  catalog-database-migration \
  migration \
  requests.cpu \
  100m

assert_resource \
  job \
  catalog-database-migration \
  migration \
  requests.memory \
  128Mi

assert_resource \
  job \
  catalog-database-migration \
  migration \
  limits.cpu \
  500m

assert_resource \
  job \
  catalog-database-migration \
  migration \
  limits.memory \
  512Mi

assert_resource \
  job \
  pricing-database-migration \
  migration \
  requests.cpu \
  100m

assert_resource \
  job \
  pricing-database-migration \
  migration \
  requests.memory \
  128Mi

assert_resource \
  job \
  pricing-database-migration \
  migration \
  limits.cpu \
  500m

assert_resource \
  job \
  pricing-database-migration \
  migration \
  limits.memory \
  512Mi

echo "PASS: Migration resources are correct."

echo
echo "7. Checking application QoS..."

assert_qos \
  'app.kubernetes.io/component=api' \
  Burstable

echo "PASS: API Pods use Burstable QoS."

echo
echo "8. Checking database QoS..."

assert_qos \
  'app.kubernetes.io/component=database' \
  Burstable

echo "PASS: Database Pods use Burstable QoS."

echo
echo "9. Checking migration QoS..."

assert_qos \
  'app.kubernetes.io/component=migration' \
  Burstable

echo "PASS: Migration Pods use Burstable QoS."

echo
echo "10. Node capacity..."

kubectl get node \
  "${PROFILE_NAME}" \
  -o custom-columns='NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,ALLOCATABLE_CPU:.status.allocatable.cpu,ALLOCATABLE_MEMORY:.status.allocatable.memory'

echo
echo "11. Runtime resource summary..."

kubectl get pods \
  --namespace "${NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,QOS:.status.qosClass'

echo
echo "============================================================"
echo "RESOURCE MANAGEMENT TEST PASSED."
echo "============================================================"