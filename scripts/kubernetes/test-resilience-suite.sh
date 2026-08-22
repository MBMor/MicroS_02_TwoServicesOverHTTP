#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

CATALOG_DEPLOYMENT="${CATALOG_DEPLOYMENT:-catalog-service}"
PRICING_DEPLOYMENT="${PRICING_DEPLOYMENT:-pricing-service}"

HPA_NAME="${HPA_NAME:-pricing-service}"

UPDATE_IMAGE="${UPDATE_IMAGE:-micros-02/pricing-service:1.0.1}"
UPDATE_IMAGE_VERSION="${UPDATE_IMAGE_VERSION:-1.0.1}"

PREPARE_UPDATE_IMAGE="${PREPARE_UPDATE_IMAGE:-true}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

OUTPUT_ROOT="${OUTPUT_ROOT:-${REPOSITORY_ROOT}/artifacts/kubernetes-resilience-runs}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
RUN_DIRECTORY="${OUTPUT_ROOT}/${TIMESTAMP}"
LOG_DIRECTORY="${RUN_DIRECTORY}/logs"

SUMMARY_FILE="${RUN_DIRECTORY}/SUMMARY.txt"

HPA_MANIFEST="${REPOSITORY_ROOT}/deploy/kubernetes/base/autoscaling/pricing-service-hpa.yaml"

DIAGNOSTICS_COLLECTOR="${SCRIPT_DIRECTORY}/collect-diagnostics.sh"

SMOKE_TEST="${SCRIPT_DIRECTORY}/smoke-test.sh"
INGRESS_TEST="${SCRIPT_DIRECTORY}/test-ingress.sh"
NETWORK_POLICY_TEST="${SCRIPT_DIRECTORY}/test-network-policies.sh"
RESOURCE_TEST="${SCRIPT_DIRECTORY}/test-resource-management.sh"

BUILD_AND_LOAD_IMAGES="${SCRIPT_DIRECTORY}/build-and-load-images.sh"

OUTAGE_TIMEOUT="${OUTAGE_TIMEOUT:-60}"

HPA_WAS_PRESENT="false"
ENVIRONMENT_RESTORED="false"

ORIGINAL_CATALOG_REPLICAS=""
ORIGINAL_PRICING_REPLICAS=""

SCENARIO_NUMBER=0

export PROFILE_NAME
export NAMESPACE
export UPDATE_IMAGE

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_file() {
  local file_path="$1"

  if [[ ! -f "${file_path}" ]]; then
    echo "Required file was not found:" >&2
    echo "  ${file_path}" >&2
    exit 1
  fi
}

slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    tr -cs 'a-z0-9' '-' |
    sed 's/^-//; s/-$//'
}

record_summary() {
  printf '%s\n' "$1" >> "${SUMMARY_FILE}"
}

collect_failure_diagnostics() {
  local failed_step="$1"

  echo
  echo "Collecting diagnostics after failure: ${failed_step}"

  record_summary ""
  record_summary "FAILURE DIAGNOSTICS"
  record_summary "-------------------"
  record_summary "Failed step: ${failed_step}"

  if [[ ! -f "${DIAGNOSTICS_COLLECTOR}" ]]; then
    echo "Diagnostics collector was not found." >&2
    record_summary "Diagnostics collector not found."
    return
  fi

  mkdir -p "${RUN_DIRECTORY}/diagnostics"

  set +e

  OUTPUT_ROOT="${RUN_DIRECTORY}/diagnostics" \
    bash "${DIAGNOSTICS_COLLECTOR}"

  local diagnostics_exit_code=$?

  set -e

  record_summary \
    "Diagnostics collector exit code: ${diagnostics_exit_code}"
}

run_logged() {
  local label="$1"
  shift

  local slug
  local log_file
  local start_time
  local end_time
  local duration
  local exit_code

  slug="$(slugify "${label}")"
  log_file="${LOG_DIRECTORY}/${slug}.log"

  echo
  echo "============================================================"
  echo "${label}"
  echo "============================================================"

  start_time="$(date +%s)"

  set +e

  "$@" 2>&1 |
    tee "${log_file}"

  exit_code="${PIPESTATUS[0]}"

  set -e

  end_time="$(date +%s)"
  duration="$((end_time - start_time))"

  if [[ "${exit_code}" == "0" ]]; then
    record_summary \
      "PASS | ${label} | ${duration}s"

    return 0
  fi

  record_summary \
    "FAIL | ${label} | exit=${exit_code} | ${duration}s"

  echo
  echo "FAILED: ${label}" >&2
  echo "Log: ${log_file}" >&2

  collect_failure_diagnostics "${label}"

  return "${exit_code}"
}

restore_environment() {
  if [[ "${ENVIRONMENT_RESTORED}" == "true" ]]; then
    return
  fi

  echo
  echo "============================================================"
  echo "Restoring original runtime state"
  echo "============================================================"

  set +e

  if [[ -n "${ORIGINAL_CATALOG_REPLICAS}" ]]; then
    kubectl scale deployment \
      "${CATALOG_DEPLOYMENT}" \
      --replicas="${ORIGINAL_CATALOG_REPLICAS}" \
      --namespace "${NAMESPACE}"
  fi

  if [[ -n "${ORIGINAL_PRICING_REPLICAS}" ]]; then
    kubectl scale deployment \
      "${PRICING_DEPLOYMENT}" \
      --replicas="${ORIGINAL_PRICING_REPLICAS}" \
      --namespace "${NAMESPACE}"
  fi

  kubectl rollout status \
    deployment/"${CATALOG_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    --timeout=120s \
    || true

  kubectl rollout status \
    deployment/"${PRICING_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    --timeout=120s \
    || true

  if [[ "${HPA_WAS_PRESENT}" == "true" ]]; then
    if [[ -f "${HPA_MANIFEST}" ]]; then
      kubectl apply \
        -f "${HPA_MANIFEST}" \
        || true
    else
      echo "HPA manifest was not found:" >&2
      echo "  ${HPA_MANIFEST}" >&2
    fi
  fi

  set -e

  ENVIRONMENT_RESTORED="true"
}

cleanup() {
  local original_exit_code=$?

  set +e

  restore_environment

  set -e

  exit "${original_exit_code}"
}

trap cleanup EXIT INT TERM

run_scenario() {
  local name="$1"
  local script="$2"

  SCENARIO_NUMBER="$((SCENARIO_NUMBER + 1))"

  local prefix
  prefix="$(printf '%02d' "${SCENARIO_NUMBER}")"

  require_file "${script}"

  if ! run_logged \
    "${prefix} - ${name}" \
    bash "${script}"; then

    exit 1
  fi

  if ! run_logged \
    "${prefix} - ${name} - recovery smoke" \
    bash "${SMOKE_TEST}"; then

    exit 1
  fi
}

require_command minikube
require_command kubectl
require_command grep
require_command sed
require_command tr
require_command tee
require_command date
require_command mkdir

require_file "${SMOKE_TEST}"
require_file "${INGRESS_TEST}"
require_file "${NETWORK_POLICY_TEST}"
require_file "${RESOURCE_TEST}"
require_file "${DIAGNOSTICS_COLLECTOR}"

mkdir -p \
  "${RUN_DIRECTORY}" \
  "${LOG_DIRECTORY}"

cat > "${SUMMARY_FILE}" <<EOF
KUBERNETES RESILIENCE SUITE
===========================

Started:   $(date --iso-8601=seconds)
Profile:   ${PROFILE_NAME}
Namespace: ${NAMESPACE}

RESULTS
-------
EOF

echo "============================================================"
echo "Kubernetes resilience test suite"
echo "============================================================"
echo
echo "Profile:   ${PROFILE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Output:    ${RUN_DIRECTORY}"

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
echo "2. Capturing original runtime state..."

ORIGINAL_CATALOG_REPLICAS="$(
  kubectl get deployment \
    "${CATALOG_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

ORIGINAL_PRICING_REPLICAS="$(
  kubectl get deployment \
    "${PRICING_DEPLOYMENT}" \
    --namespace "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

echo "Catalog replicas: ${ORIGINAL_CATALOG_REPLICAS}"
echo "Pricing replicas: ${ORIGINAL_PRICING_REPLICAS}"

if kubectl get hpa \
  "${HPA_NAME}" \
  --namespace "${NAMESPACE}" \
  >/dev/null 2>&1; then

  HPA_WAS_PRESENT="true"
  echo "HPA: present"
else
  echo "HPA: not present"
fi

echo
echo "3. Temporarily disabling HPA..."

if [[ "${HPA_WAS_PRESENT}" == "true" ]]; then
  kubectl delete hpa \
    "${HPA_NAME}" \
    --namespace "${NAMESPACE}"

  echo "PASS: HPA temporarily disabled."
else
  echo "HPA was not present. Nothing to disable."
fi

echo
echo "4. Establishing deterministic baseline..."

kubectl scale deployment \
  "${CATALOG_DEPLOYMENT}" \
  --replicas=1 \
  --namespace "${NAMESPACE}"

kubectl scale deployment \
  "${PRICING_DEPLOYMENT}" \
  --replicas=1 \
  --namespace "${NAMESPACE}"

kubectl rollout status \
  deployment/"${CATALOG_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=120s

kubectl rollout status \
  deployment/"${PRICING_DEPLOYMENT}" \
  --namespace "${NAMESPACE}" \
  --timeout=120s

kubectl wait \
  --for=condition=Ready \
  pod/catalog-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout=120s

kubectl wait \
  --for=condition=Ready \
  pod/pricing-service-db-0 \
  --namespace "${NAMESPACE}" \
  --timeout=120s

echo "PASS: Baseline is healthy."

echo
echo "5. Ensuring rollout candidate image exists..."

if minikube image ls \
  --profile "${PROFILE_NAME}" |
  grep -Fq "${UPDATE_IMAGE}"; then

  echo "PASS: ${UPDATE_IMAGE} is already loaded."
else
  if [[ "${PREPARE_UPDATE_IMAGE}" != "true" ]]; then
    echo "Required rollout image is missing:" >&2
    echo "  ${UPDATE_IMAGE}" >&2
    echo >&2
    echo "Load it with:" >&2
    echo "  IMAGE_VERSION=${UPDATE_IMAGE_VERSION} \\" >&2
    echo "    ./scripts/kubernetes/build-and-load-images.sh" >&2
    exit 1
  fi

  require_file "${BUILD_AND_LOAD_IMAGES}"

  echo "Image is missing. Building and loading version ${UPDATE_IMAGE_VERSION}..."

  IMAGE_VERSION="${UPDATE_IMAGE_VERSION}" \
    bash "${BUILD_AND_LOAD_IMAGES}"

  if ! minikube image ls \
    --profile "${PROFILE_NAME}" |
    grep -Fq "${UPDATE_IMAGE}"; then

    echo "Rollout candidate image is still missing after build/load." >&2
    exit 1
  fi

  echo "PASS: Rollout candidate image is available."
fi

echo
echo "6. Running platform preflight gates..."

if ! run_logged \
  "Preflight - smoke test" \
  bash "${SMOKE_TEST}"; then

  exit 1
fi

if ! run_logged \
  "Preflight - Ingress" \
  bash "${INGRESS_TEST}"; then

  exit 1
fi

if ! run_logged \
  "Preflight - NetworkPolicy" \
  bash "${NETWORK_POLICY_TEST}"; then

  exit 1
fi

if ! run_logged \
  "Preflight - resource management" \
  bash "${RESOURCE_TEST}"; then

  exit 1
fi

echo
echo "7. Starting resilience scenarios..."

run_scenario \
  "Pod self-healing" \
  "${SCRIPT_DIRECTORY}/test-self-healing.sh"

run_scenario \
  "Pricing outage fallback" \
  "${SCRIPT_DIRECTORY}/test-pricing-outage.sh"

run_scenario \
  "ImagePullBackOff" \
  "${SCRIPT_DIRECTORY}/test-image-pull-backoff.sh"

run_scenario \
  "Missing Secret" \
  "${SCRIPT_DIRECTORY}/test-missing-secret.sh"

run_scenario \
  "Wrong Service selector" \
  "${SCRIPT_DIRECTORY}/test-wrong-service-selector.sh"

run_scenario \
  "Failed readiness" \
  "${SCRIPT_DIRECTORY}/test-failed-readiness.sh"

run_scenario \
  "CrashLoopBackOff" \
  "${SCRIPT_DIRECTORY}/test-crash-loop-backoff.sh"

run_scenario \
  "Rolling update" \
  "${SCRIPT_DIRECTORY}/test-rolling-update.sh"

run_scenario \
  "Failed rollout and rollback" \
  "${SCRIPT_DIRECTORY}/test-failed-rollout-rollback.sh"

run_scenario \
  "Database persistence" \
  "${SCRIPT_DIRECTORY}/test-database-persistence.sh"

run_scenario \
  "Database readiness outage" \
  "${SCRIPT_DIRECTORY}/test-database-readiness-outage.sh"

run_scenario \
  "OOMKilled" \
  "${SCRIPT_DIRECTORY}/test-oom-killed.sh"

echo
echo "8. Restoring original runtime state..."

restore_environment

echo "PASS: Original runtime state restored."

echo
echo "9. Running final smoke test..."

if ! run_logged \
  "Final smoke test" \
  bash "${SMOKE_TEST}"; then

  exit 1
fi

if [[ "${HPA_WAS_PRESENT}" == "true" ]]; then
  echo
  echo "10. Verifying HPA restoration..."

  if ! kubectl get hpa \
    "${HPA_NAME}" \
    --namespace "${NAMESPACE}" \
    >/dev/null 2>&1; then

    echo "HPA was not restored." >&2

    collect_failure_diagnostics \
      "HPA restoration"

    exit 1
  fi

  kubectl get hpa \
    "${HPA_NAME}" \
    --namespace "${NAMESPACE}"

  echo "PASS: HPA restored."
fi

{
  echo
  echo "FINAL STATUS"
  echo "------------"
  echo "PASS"
  echo
  echo "Completed: $(date --iso-8601=seconds)"
} >> "${SUMMARY_FILE}"

echo
echo "============================================================"
echo "KUBERNETES RESILIENCE SUITE PASSED."
echo "============================================================"
echo
echo "Summary:"
echo "  ${SUMMARY_FILE}"
echo
echo "Logs:"
echo "  ${LOG_DIRECTORY}"