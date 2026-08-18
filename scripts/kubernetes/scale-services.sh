#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

CATALOG_REPLICAS="${CATALOG_REPLICAS:-2}"
PRICING_REPLICAS="${PRICING_REPLICAS:-3}"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_positive_integer() {
  local name="$1"
  local value="$2"

  if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    echo "${name} must be a non-negative integer." >&2
    exit 1
  fi
}

require_command minikube
require_command kubectl

require_positive_integer \
  "CATALOG_REPLICAS" \
  "${CATALOG_REPLICAS}"

require_positive_integer \
  "PRICING_REPLICAS" \
  "${PRICING_REPLICAS}"

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "Scaling application Deployments..."
echo
echo "Catalog replicas: ${CATALOG_REPLICAS}"
echo "Pricing replicas: ${PRICING_REPLICAS}"
echo

kubectl scale deployment \
  catalog-service \
  --replicas="${CATALOG_REPLICAS}" \
  --namespace "${NAMESPACE}"

kubectl scale deployment \
  pricing-service \
  --replicas="${PRICING_REPLICAS}" \
  --namespace "${NAMESPACE}"

echo
echo "Waiting for Catalog rollout..."

kubectl rollout status \
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout=180s

echo
echo "Waiting for Pricing rollout..."

kubectl rollout status \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout=180s

echo
echo "Scaled Deployments:"

kubectl get deployments \
  catalog-service \
  pricing-service \
  --namespace "${NAMESPACE}"

echo
echo "Application Pods:"

kubectl get pods \
  --namespace "${NAMESPACE}" \
  --selector='app.kubernetes.io/component=api' \
  -o wide

echo
echo "Scaling completed successfully."