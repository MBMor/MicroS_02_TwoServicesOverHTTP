#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

HPA_MANIFEST="${REPOSITORY_ROOT}/deploy/kubernetes/base/autoscaling/pricing-service-hpa.yaml"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_command minikube
require_command kubectl
require_command grep

echo "============================================================"
echo "Horizontal Pod Autoscaler setup"
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
echo "2. Checking metrics-server addon..."

if ! minikube addons list \
  --profile "${PROFILE_NAME}" |
  grep -qi 'metrics-server'; then

  echo "metrics-server addon is not available." >&2
  exit 1
fi

echo "PASS: metrics-server addon is available."

echo
echo "3. Enabling metrics-server..."

minikube addons enable metrics-server \
  --profile "${PROFILE_NAME}"

echo
echo "4. Waiting for Metrics Server..."

kubectl rollout status \
  deployment/metrics-server \
  --namespace kube-system \
  --timeout=180s

echo "PASS: Metrics Server is available."

echo
echo "5. Waiting for Metrics API..."

METRICS_API_READY="false"

for ((attempt = 1; attempt <= 120; attempt++)); do
  AVAILABLE="$(
    kubectl get apiservice \
      v1beta1.metrics.k8s.io \
      -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' \
      2>/dev/null || true
  )"

  if [[ "${AVAILABLE}" == "True" ]]; then
    METRICS_API_READY="true"
    break
  fi

  sleep 1
done

if [[ "${METRICS_API_READY}" != "true" ]]; then
  echo "Metrics API did not become available." >&2

  kubectl describe apiservice \
    v1beta1.metrics.k8s.io \
    >&2 || true

  exit 1
fi

echo "PASS: metrics.k8s.io API is available."

echo
echo "6. Waiting for Pod metrics..."

METRICS_READY="false"

for ((attempt = 1; attempt <= 120; attempt++)); do
  if kubectl top pods \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then

    METRICS_READY="true"
    break
  fi

  sleep 1
done

if [[ "${METRICS_READY}" != "true" ]]; then
  echo "Pod metrics did not become available." >&2
  exit 1
fi

echo "PASS: Pod metrics are available."

echo
echo "7. Checking Pricing CPU request..."

CPU_REQUEST="$(
  kubectl get deployment \
    pricing-service \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'
)"

echo "CPU request: ${CPU_REQUEST}"

if [[ -z "${CPU_REQUEST}" ]]; then
  echo "Pricing Service has no CPU request." >&2
  echo "CPU utilization HPA cannot work correctly." >&2
  exit 1
fi

echo "PASS: Pricing has a CPU request."

echo
echo "8. Applying HPA..."

if [[ ! -f "${HPA_MANIFEST}" ]]; then
  echo "HPA manifest was not found:" >&2
  echo "${HPA_MANIFEST}" >&2
  exit 1
fi

kubectl apply \
  -f "${HPA_MANIFEST}"

echo
echo "9. HPA status..."

kubectl get hpa \
  pricing-service \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "HPA SETUP COMPLETED."
echo "============================================================"