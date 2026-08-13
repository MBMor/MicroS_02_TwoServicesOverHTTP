#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
TIMEOUT="${TIMEOUT:-180s}"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_command minikube
require_command kubectl

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "Waiting for database Pods..."

kubectl wait \
  --for=condition=Ready \
  pod/catalog-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"

kubectl wait \
  --for=condition=Ready \
  pod/pricing-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"

echo
echo "Waiting for migration Jobs..."

for job_name in \
  pricing-database-migration \
  catalog-database-migration
do
  if kubectl get job \
    "${job_name}" \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then

    kubectl wait \
      --for=condition=Complete \
      job/"${job_name}" \
      --namespace "${NAMESPACE}" \
      --timeout="${TIMEOUT}"
  fi
done

echo
echo "Waiting for application Deployments..."

kubectl rollout status \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"

kubectl rollout status \
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"

echo
echo "Waiting for application availability..."

kubectl wait \
  --for=condition=Available \
  deployment/pricing-service \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"

kubectl wait \
  --for=condition=Available \
  deployment/catalog-service \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"

echo
echo "All Kubernetes workloads are ready."