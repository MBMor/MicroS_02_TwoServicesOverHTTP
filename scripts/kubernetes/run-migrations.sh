#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
TIMEOUT="${TIMEOUT:-180s}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

MIGRATIONS_DIRECTORY="${REPOSITORY_ROOT}/deploy/kubernetes/base/migrations"

PRICING_JOB="pricing-database-migration"
CATALOG_JOB="catalog-database-migration"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Required command 'kubectl' was not found." >&2
  exit 1
fi

if ! command -v minikube >/dev/null 2>&1; then
  echo "Required command 'minikube' was not found." >&2
  exit 1
fi

if ! minikube status \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1; then
  echo "Minikube profile '${PROFILE_NAME}' is not running." >&2
  exit 1
fi

kubectl config use-context \
  "${PROFILE_NAME}" \
  >/dev/null

echo "Checking database Pods..."

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

echo
echo "Removing previous migration Jobs..."

kubectl delete job \
  "${PRICING_JOB}" \
  "${CATALOG_JOB}" \
  --namespace "${NAMESPACE}" \
  --ignore-not-found

echo
echo "Applying migration Jobs..."

kubectl apply \
  -f "${MIGRATIONS_DIRECTORY}"

echo
echo "Waiting for Pricing migration..."

if ! kubectl wait \
  --for=condition=Complete \
  job/"${PRICING_JOB}" \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"; then

  echo
  echo "Pricing migration failed or timed out." >&2

  kubectl logs \
    job/"${PRICING_JOB}" \
    --namespace "${NAMESPACE}" \
    >&2 || true

  exit 1
fi

echo
echo "Pricing migration log:"

kubectl logs \
  job/"${PRICING_JOB}" \
  --namespace "${NAMESPACE}"

echo
echo "Waiting for Catalog migration..."

if ! kubectl wait \
  --for=condition=Complete \
  job/"${CATALOG_JOB}" \
  --namespace "${NAMESPACE}" \
  --timeout="${TIMEOUT}"; then

  echo
  echo "Catalog migration failed or timed out." >&2

  kubectl logs \
    job/"${CATALOG_JOB}" \
    --namespace "${NAMESPACE}" \
    >&2 || true

  exit 1
fi

echo
echo "Catalog migration log:"

kubectl logs \
  job/"${CATALOG_JOB}" \
  --namespace "${NAMESPACE}"

echo
echo "Migration Jobs:"

kubectl get jobs \
  --namespace "${NAMESPACE}"

echo
echo "Database migrations completed successfully."