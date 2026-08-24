#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"

HELM_RELEASE="${HELM_RELEASE:-micros-02-test}"
HELM_NAMESPACE="${HELM_NAMESPACE:-micros-02-helm-test}"

CATALOG_LOCAL_PORT="${CATALOG_LOCAL_PORT:-5301}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"

CATALOG_URL="http://127.0.0.1:${CATALOG_LOCAL_PORT}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

CHART_DIRECTORY="${REPOSITORY_ROOT}/deploy/helm/micros-02"

PORT_FORWARD_PID=""
TEMP_DIRECTORY=""
TEST_PRODUCT_ID=""

TEST_SKU="HELM-SMOKE-$(date +%s)-${RANDOM}"

NAMESPACE_CREATED="false"
RELEASE_INSTALLED="false"

cleanup() {
  local original_exit_code=$?

  set +e

  echo
  echo "============================================================"
  echo "Cleanup"
  echo "============================================================"

  if [[ -n "${TEST_PRODUCT_ID}" ]] &&
     [[ -n "${PORT_FORWARD_PID}" ]] &&
     kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then

    echo "Deleting temporary Catalog product..."

    curl \
      --silent \
      --output /dev/null \
      --request DELETE \
      "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}" \
      || true
  fi

  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    echo "Stopping Catalog port-forward..."

    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi

  if [[ "${RELEASE_INSTALLED}" == "true" ]]; then
    echo "Uninstalling Helm release..."

    helm uninstall \
      "${HELM_RELEASE}" \
      --namespace "${HELM_NAMESPACE}" \
      >/dev/null 2>&1 || true
  fi

  if [[ "${NAMESPACE_CREATED}" == "true" ]]; then
    echo "Deleting test namespace..."

    kubectl delete namespace \
      "${HELM_NAMESPACE}" \
      --wait=false \
      >/dev/null 2>&1 || true
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

wait_for_http() {
  local name="$1"
  local url="$2"

  for ((attempt = 1; attempt <= 60; attempt++)); do
    if curl \
      --silent \
      --fail \
      --max-time 3 \
      "${url}" \
      >/dev/null 2>&1; then

      echo "PASS: ${name} is reachable."
      return 0
    fi

    sleep 1
  done

  echo "${name} did not become reachable:" >&2
  echo "  ${url}" >&2

  return 1
}

require_command minikube
require_command kubectl
require_command helm
require_command curl
require_command grep
require_command sed
require_command mktemp

if [[ ! -d "${CHART_DIRECTORY}" ]]; then
  echo "Helm chart directory was not found:" >&2
  echo "  ${CHART_DIRECTORY}" >&2
  exit 1
fi

TEMP_DIRECTORY="$(mktemp -d)"

PORT_FORWARD_LOG="${TEMP_DIRECTORY}/catalog-port-forward.log"
CREATE_RESPONSE="${TEMP_DIRECTORY}/create-response.json"
PRODUCT_RESPONSE="${TEMP_DIRECTORY}/product-response.json"

echo "============================================================"
echo "Helm release lifecycle smoke test"
echo "============================================================"

echo
echo "Profile:   ${PROFILE_NAME}"
echo "Release:   ${HELM_RELEASE}"
echo "Namespace: ${HELM_NAMESPACE}"

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
echo "2. Checking required application images..."

for image in \
  "micros-02/catalog-service:1.0.0" \
  "micros-02/pricing-service:1.0.0" \
  "micros-02/ef-migrations:1.0.0"; do

  if ! minikube image ls \
    --profile "${PROFILE_NAME}" |
    grep -Fq "${image}"; then

    echo "Required image is missing from Minikube:" >&2
    echo "  ${image}" >&2
    echo >&2
    echo "Run:" >&2
    echo "  IMAGE_VERSION=1.0.0 ./scripts/kubernetes/build-and-load-images.sh" >&2
    exit 1
  fi

  echo "PASS: ${image}"
done

echo
echo "3. Running Helm lint..."

helm lint \
  "${CHART_DIRECTORY}"

echo "PASS: Helm chart lint passed."

echo
echo "4. Rendering Helm chart..."

helm template \
  "${HELM_RELEASE}" \
  "${CHART_DIRECTORY}" \
  --namespace "${HELM_NAMESPACE}" \
  > "${TEMP_DIRECTORY}/rendered.yaml"

if [[ ! -s "${TEMP_DIRECTORY}/rendered.yaml" ]]; then
  echo "Rendered Helm manifest is empty." >&2
  exit 1
fi

echo "PASS: Helm chart rendered successfully."

echo
echo "5. Ensuring clean test environment..."

if helm status \
  "${HELM_RELEASE}" \
  --namespace "${HELM_NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "Helm release '${HELM_RELEASE}' already exists." >&2
  echo "Remove the previous test environment before rerunning." >&2
  exit 1
fi

if kubectl get namespace \
  "${HELM_NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "Test namespace '${HELM_NAMESPACE}' already exists." >&2
  echo "Remove it before rerunning the Helm lifecycle test." >&2
  exit 1
fi

echo "PASS: Test environment is clean."

echo
echo "6. Creating isolated namespace..."

kubectl create namespace \
  "${HELM_NAMESPACE}"

NAMESPACE_CREATED="true"

echo "PASS: Namespace created."

echo
echo "7. Creating disposable database Secrets..."

kubectl create secret generic catalog-database-secret \
  --namespace "${HELM_NAMESPACE}" \
  --from-literal=postgres-database=catalog_service \
  --from-literal=postgres-username=catalog_user \
  --from-literal=postgres-password=catalog_helm_test_password

kubectl create secret generic pricing-database-secret \
  --namespace "${HELM_NAMESPACE}" \
  --from-literal=postgres-database=pricing_service \
  --from-literal=postgres-username=pricing_user \
  --from-literal=postgres-password=pricing_helm_test_password

echo "PASS: Database Secrets created."

echo
echo "8. Installing Helm release..."

helm install \
  "${HELM_RELEASE}" \
  "${CHART_DIRECTORY}" \
  --namespace "${HELM_NAMESPACE}" \
  --wait \
  --timeout 5m

RELEASE_INSTALLED="true"

echo "PASS: Helm release installed."

echo
echo "9. Verifying release revision 1..."

REVISION="$(
  helm list \
    --namespace "${HELM_NAMESPACE}" \
    --filter "^${HELM_RELEASE}$" \
    --output json |
  grep -oE '"revision":"?[0-9]+' |
  grep -oE '[0-9]+' |
  head -n 1
)"

if [[ "${REVISION}" != "1" ]]; then
  echo "Expected Helm revision 1 after install." >&2
  echo "Actual: ${REVISION:-unknown}" >&2
  exit 1
fi

echo "PASS: Helm revision is 1."

echo
echo "10. Verifying Helm release status..."

STATUS="$(
  helm status \
    "${HELM_RELEASE}" \
    --namespace "${HELM_NAMESPACE}" \
    --output json |
  grep -oE '"status":"[^"]+"' |
  head -n 1 |
  sed -E 's/.*"status":"([^"]+)".*/\1/'
)"

if [[ "${STATUS}" != "deployed" ]]; then
  echo "Expected Helm release status 'deployed'." >&2
  echo "Actual: ${STATUS:-unknown}" >&2
  exit 1
fi

echo "PASS: Helm release is deployed."

echo
echo "11. Verifying PostgreSQL Pods..."

kubectl wait \
  --for=condition=Ready \
  pod/"${HELM_RELEASE}"-catalog-service-db-0 \
  --namespace "${HELM_NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

kubectl wait \
  --for=condition=Ready \
  pod/"${HELM_RELEASE}"-pricing-service-db-0 \
  --namespace "${HELM_NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: PostgreSQL Pods are Ready."

echo
echo "12. Verifying API Deployments..."

kubectl rollout status \
  deployment/"${HELM_RELEASE}"-catalog-service \
  --namespace "${HELM_NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

kubectl rollout status \
  deployment/"${HELM_RELEASE}"-pricing-service \
  --namespace "${HELM_NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

echo "PASS: API Deployments are available."

echo
echo "13. Verifying migration hooks..."

HOOKS="$(
  helm get hooks \
    "${HELM_RELEASE}" \
    --namespace "${HELM_NAMESPACE}"
)"

if ! grep -q \
  "${HELM_RELEASE}-catalog-database-migration" \
  <<< "${HOOKS}"; then

  echo "Catalog migration hook was not found." >&2
  exit 1
fi

if ! grep -q \
  "${HELM_RELEASE}-pricing-database-migration" \
  <<< "${HOOKS}"; then

  echo "Pricing migration hook was not found." >&2
  exit 1
fi

echo "PASS: Migration hooks are part of the release."

echo
echo "14. Verifying successful hook cleanup..."

JOB_COUNT="$(
  kubectl get jobs \
    --namespace "${HELM_NAMESPACE}" \
    --selector='app.kubernetes.io/component=migration' \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null |
  grep -c . || true
)"

if [[ "${JOB_COUNT}" != "0" ]]; then
  echo "Expected successful migration Jobs to be deleted." >&2

  kubectl get jobs \
    --namespace "${HELM_NAMESPACE}" \
    >&2

  exit 1
fi

echo "PASS: Successful migration Jobs were cleaned up."

echo
echo "15. Starting Catalog port-forward..."

kubectl port-forward \
  --namespace "${HELM_NAMESPACE}" \
  service/"${HELM_RELEASE}"-catalog-service \
  "${CATALOG_LOCAL_PORT}:80" \
  >"${PORT_FORWARD_LOG}" 2>&1 &

PORT_FORWARD_PID="$!"

if ! wait_for_http \
  "Catalog Service" \
  "${CATALOG_URL}/health/live"; then

  cat "${PORT_FORWARD_LOG}" >&2
  exit 1
fi

echo
echo "16. Checking Catalog readiness..."

READY_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/health/ready"
)"

if [[ "${READY_STATUS}" != "200" ]]; then
  echo "Expected Catalog readiness HTTP 200." >&2
  echo "Actual: ${READY_STATUS}" >&2
  exit 1
fi

echo "PASS: Catalog is Ready."

echo
echo "17. Running business smoke test..."

CREATE_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${CREATE_RESPONSE}" \
    --write-out '%{http_code}' \
    --request POST \
    --header 'Content-Type: application/json' \
    --data "{
      \"name\": \"Helm release smoke product\",
      \"description\": \"Temporary Helm lifecycle smoke product\",
      \"sku\": \"${TEST_SKU}\"
    }" \
    "${CATALOG_URL}/api/v1/catalog-products"
)"

if [[ "${CREATE_STATUS}" != "201" ]]; then
  echo "Expected Catalog create HTTP 201." >&2
  echo "Actual: ${CREATE_STATUS}" >&2
  cat "${CREATE_RESPONSE}" >&2
  exit 1
fi

TEST_PRODUCT_ID="$(
  grep -oE \
    '"id"[[:space:]]*:[[:space:]]*"[^"]+"' \
    "${CREATE_RESPONSE}" |
  head -n 1 |
  sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/'
)"

if [[ -z "${TEST_PRODUCT_ID}" ]]; then
  echo "Could not extract Catalog product ID." >&2
  cat "${CREATE_RESPONSE}" >&2
  exit 1
fi

PRODUCT_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRODUCT_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${PRODUCT_STATUS}" != "200" ]]; then
  echo "Expected Catalog lookup HTTP 200." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

if ! grep -Eq \
  '"priceStatus"[[:space:]]*:[[:space:]]*"NotSet"' \
  "${PRODUCT_RESPONSE}"; then

  echo "Expected priceStatus 'NotSet'." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Catalog -> Pricing communication works."

echo
echo "18. Upgrading release..."

helm upgrade \
  "${HELM_RELEASE}" \
  "${CHART_DIRECTORY}" \
  --namespace "${HELM_NAMESPACE}" \
  --set catalog.replicaCount=2 \
  --wait \
  --timeout 5m

echo "PASS: Helm upgrade completed."

echo
echo "19. Verifying revision 2..."

REVISION="$(
  helm list \
    --namespace "${HELM_NAMESPACE}" \
    --filter "^${HELM_RELEASE}$" \
    --output json |
  grep -oE '"revision":"?[0-9]+' |
  grep -oE '[0-9]+' |
  head -n 1
)"

if [[ "${REVISION}" != "2" ]]; then
  echo "Expected Helm revision 2 after upgrade." >&2
  echo "Actual: ${REVISION:-unknown}" >&2
  exit 1
fi

echo "PASS: Helm revision is 2."

echo
echo "20. Verifying Catalog scale-up..."

kubectl rollout status \
  deployment/"${HELM_RELEASE}"-catalog-service \
  --namespace "${HELM_NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

CATALOG_REPLICAS="$(
  kubectl get deployment \
    "${HELM_RELEASE}"-catalog-service \
    --namespace "${HELM_NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

if [[ "${CATALOG_REPLICAS}" != "2" ]]; then
  echo "Expected Catalog replica count 2 after upgrade." >&2
  echo "Actual: ${CATALOG_REPLICAS}" >&2
  exit 1
fi

echo "PASS: Catalog scaled to two replicas."

echo
echo "21. Rolling back to revision 1..."

helm rollback \
  "${HELM_RELEASE}" \
  1 \
  --namespace "${HELM_NAMESPACE}" \
  --wait \
  --timeout 5m

echo "PASS: Helm rollback completed."

echo
echo "22. Verifying revision 3..."

REVISION="$(
  helm list \
    --namespace "${HELM_NAMESPACE}" \
    --filter "^${HELM_RELEASE}$" \
    --output json |
  grep -oE '"revision":"?[0-9]+' |
  grep -oE '[0-9]+' |
  head -n 1
)"

if [[ "${REVISION}" != "3" ]]; then
  echo "Expected Helm revision 3 after rollback." >&2
  echo "Actual: ${REVISION:-unknown}" >&2
  exit 1
fi

echo "PASS: Rollback created revision 3."

echo
echo "23. Verifying Catalog rollback..."

kubectl rollout status \
  deployment/"${HELM_RELEASE}"-catalog-service \
  --namespace "${HELM_NAMESPACE}" \
  --timeout="${WAIT_TIMEOUT}s"

CATALOG_REPLICAS="$(
  kubectl get deployment \
    "${HELM_RELEASE}"-catalog-service \
    --namespace "${HELM_NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

if [[ "${CATALOG_REPLICAS}" != "1" ]]; then
  echo "Expected Catalog replica count 1 after rollback." >&2
  echo "Actual: ${CATALOG_REPLICAS}" >&2
  exit 1
fi

echo "PASS: Catalog returned to one replica."

echo
echo "24. Verifying business behavior after rollback..."

ROLLBACK_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "${PRODUCT_RESPONSE}" \
    --write-out '%{http_code}' \
    "${CATALOG_URL}/api/v1/catalog-products/${TEST_PRODUCT_ID}"
)"

if [[ "${ROLLBACK_STATUS}" != "200" ]]; then
  echo "Catalog request failed after rollback." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

if ! grep -Eq \
  '"priceStatus"[[:space:]]*:[[:space:]]*"NotSet"' \
  "${PRODUCT_RESPONSE}"; then

  echo "Expected priceStatus 'NotSet' after rollback." >&2
  cat "${PRODUCT_RESPONSE}" >&2
  exit 1
fi

echo "PASS: Application works after rollback."

echo
echo "25. Helm history..."

helm history \
  "${HELM_RELEASE}" \
  --namespace "${HELM_NAMESPACE}"

echo
echo "26. Capturing PVCs before uninstall..."

PVC_COUNT_BEFORE="$(
  kubectl get pvc \
    --namespace "${HELM_NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null |
  grep -c . || true
)"

if [[ "${PVC_COUNT_BEFORE}" -lt 2 ]]; then
  echo "Expected at least two database PVCs before uninstall." >&2

  kubectl get pvc \
    --namespace "${HELM_NAMESPACE}" \
    >&2

  exit 1
fi

echo "PVC count: ${PVC_COUNT_BEFORE}"
echo "PASS: Database PVCs exist."

echo
echo "27. Stopping Catalog port-forward before uninstall..."

if [[ -n "${PORT_FORWARD_PID}" ]]; then
  kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  PORT_FORWARD_PID=""
fi

echo "PASS: Port-forward stopped."

echo
echo "28. Uninstalling Helm release..."

helm uninstall \
  "${HELM_RELEASE}" \
  --namespace "${HELM_NAMESPACE}"

RELEASE_INSTALLED="false"

echo "PASS: Helm release uninstalled."

echo
echo "29. Verifying release removal..."

if helm status \
  "${HELM_RELEASE}" \
  --namespace "${HELM_NAMESPACE}" \
  >/dev/null 2>&1; then

  echo "Helm release still exists after uninstall." >&2
  exit 1
fi

echo "PASS: Helm release no longer exists."

echo
echo "30. Verifying workload cleanup..."

DEPLOYMENT_COUNT="$(
  kubectl get deployments \
    --namespace "${HELM_NAMESPACE}" \
    --selector="app.kubernetes.io/instance=${HELM_RELEASE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null |
  grep -c . || true
)"

STATEFULSET_COUNT="$(
  kubectl get statefulsets \
    --namespace "${HELM_NAMESPACE}" \
    --selector="app.kubernetes.io/instance=${HELM_RELEASE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null |
  grep -c . || true
)"

SERVICE_COUNT="$(
  kubectl get services \
    --namespace "${HELM_NAMESPACE}" \
    --selector="app.kubernetes.io/instance=${HELM_RELEASE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null |
  grep -c . || true
)"

if [[ "${DEPLOYMENT_COUNT}" != "0" ||
      "${STATEFULSET_COUNT}" != "0" ||
      "${SERVICE_COUNT}" != "0" ]]; then

  echo "Helm-managed workloads remain after uninstall." >&2

  kubectl get all \
    --namespace "${HELM_NAMESPACE}" \
    >&2

  exit 1
fi

echo "PASS: Helm-managed workloads were removed."

echo
echo "31. Verifying PVC retention..."

PVC_COUNT_AFTER="$(
  kubectl get pvc \
    --namespace "${HELM_NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null |
  grep -c . || true
)"

if [[ "${PVC_COUNT_AFTER}" -lt 2 ]]; then
  echo "Expected database PVCs to remain after Helm uninstall." >&2

  kubectl get pvc \
    --namespace "${HELM_NAMESPACE}" \
    >&2

  exit 1
fi

echo "PVC count after uninstall: ${PVC_COUNT_AFTER}"
echo "PASS: Database PVCs were retained."

echo
echo "32. Verifying external Secrets remain..."

for secret_name in \
  catalog-database-secret \
  pricing-database-secret; do

  if ! kubectl get secret \
    "${secret_name}" \
    --namespace "${HELM_NAMESPACE}" \
    >/dev/null 2>&1; then

    echo "External Secret '${secret_name}' was unexpectedly removed." >&2
    exit 1
  fi
done

echo "PASS: External database Secrets were retained."

echo
echo "33. Final namespace state..."

kubectl get pvc \
  --namespace "${HELM_NAMESPACE}"

kubectl get secrets \
  --namespace "${HELM_NAMESPACE}"

echo
echo "============================================================"
echo "HELM RELEASE LIFECYCLE TEST PASSED."
echo "============================================================"