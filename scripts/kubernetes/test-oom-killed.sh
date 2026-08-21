#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

TEST_POD="${TEST_POD:-oom-memory-test}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"

cleanup() {
  local original_exit_code=$?

  set +e

  kubectl delete pod \
    "${TEST_POD}" \
    --namespace "${NAMESPACE}" \
    --ignore-not-found \
    --wait=false \
    >/dev/null 2>&1 || true

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

echo "============================================================"
echo "Kubernetes OOMKilled test"
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
echo "2. Removing previous OOM test Pod..."

kubectl delete pod \
  "${TEST_POD}" \
  --namespace "${NAMESPACE}" \
  --ignore-not-found \
  >/dev/null

echo "Done."

echo
echo "3. Creating memory stress Pod..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${TEST_POD}
    app.kubernetes.io/component: failure-test
    app.kubernetes.io/part-of: micros-02-two-services-over-http
spec:
  restartPolicy: Always
  containers:
    - name: memory-stress
      image: polinux/stress
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          memory: 50Mi
          cpu: 10m
        limits:
          memory: 100Mi
          cpu: 500m
      command:
        - stress
      args:
        - --vm
        - "1"
        - --vm-bytes
        - 250M
        - --vm-hang
        - "1"
EOF

echo "PASS: Test Pod created."

echo
echo "4. Waiting for Pod scheduling..."

kubectl wait \
  --for=condition=PodScheduled \
  pod/"${TEST_POD}" \
  --namespace "${NAMESPACE}" \
  --timeout=60s

echo "PASS: Pod was scheduled."

echo
echo "5. Waiting for OOMKilled..."

OOM_OBSERVED="false"
OOM_EXIT_CODE=""

for ((attempt = 1; attempt <= WAIT_TIMEOUT; attempt++)); do
  LAST_REASON="$(
    kubectl get pod \
      "${TEST_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' \
      2>/dev/null || true
  )"

  LAST_EXIT_CODE="$(
    kubectl get pod \
      "${TEST_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' \
      2>/dev/null || true
  )"

  CURRENT_REASON="$(
    kubectl get pod \
      "${TEST_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' \
      2>/dev/null || true
  )"

  CURRENT_EXIT_CODE="$(
    kubectl get pod \
      "${TEST_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' \
      2>/dev/null || true
  )"

  WAITING_REASON="$(
    kubectl get pod \
      "${TEST_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' \
      2>/dev/null || true
  )"

  if [[ "${LAST_REASON}" == "OOMKilled" ]]; then
    OOM_OBSERVED="true"
    OOM_EXIT_CODE="${LAST_EXIT_CODE}"
    break
  fi

  if [[ "${CURRENT_REASON}" == "OOMKilled" ]]; then
    OOM_OBSERVED="true"
    OOM_EXIT_CODE="${CURRENT_EXIT_CODE}"
    break
  fi

  if [[ "${WAITING_REASON}" == "ImagePullBackOff" ||
        "${WAITING_REASON}" == "ErrImagePull" ]]; then

    echo "Could not pull the stress image." >&2

    kubectl describe pod \
      "${TEST_POD}" \
      --namespace "${NAMESPACE}" \
      >&2

    exit 1
  fi

  sleep 1
done

if [[ "${OOM_OBSERVED}" != "true" ]]; then
  echo "OOMKilled was not observed within ${WAIT_TIMEOUT} seconds." >&2
  echo >&2

  kubectl describe pod \
    "${TEST_POD}" \
    --namespace "${NAMESPACE}" \
    >&2

  exit 1
fi

echo "PASS: OOMKilled was observed."

echo
echo "6. Checking exit code..."

echo "Exit code: ${OOM_EXIT_CODE}"

if [[ "${OOM_EXIT_CODE}" != "137" ]]; then
  echo "Expected exit code 137 after OOMKilled." >&2
  echo "Actual: ${OOM_EXIT_CODE}" >&2
  exit 1
fi

echo "PASS: OOMKilled exit code is 137."

echo
echo "7. Waiting for kubelet restart..."

RESTART_COUNT="0"

for ((attempt = 1; attempt <= 30; attempt++)); do
  RESTART_COUNT="$(
    kubectl get pod \
      "${TEST_POD}" \
      --namespace "${NAMESPACE}" \
      -o jsonpath='{.status.containerStatuses[0].restartCount}' \
      2>/dev/null || true
  )"

  if [[ "${RESTART_COUNT}" =~ ^[0-9]+$ ]] &&
     ((RESTART_COUNT > 0)); then

    break
  fi

  sleep 1
done

if ! [[ "${RESTART_COUNT}" =~ ^[0-9]+$ ]] ||
   ((RESTART_COUNT < 1)); then

  echo "Container was not restarted after OOMKilled." >&2
  exit 1
fi

echo "Restart count: ${RESTART_COUNT}"
echo "PASS: kubelet restarted the failed container."

echo
echo "8. Container status..."

kubectl get pod \
  "${TEST_POD}" \
  --namespace "${NAMESPACE}" \
  -o jsonpath='Current waiting reason: {.status.containerStatuses[0].state.waiting.reason}{"\n"}Last terminated reason: {.status.containerStatuses[0].lastState.terminated.reason}{"\n"}Last exit code: {.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}Restart count: {.status.containerStatuses[0].restartCount}{"\n"}'

echo
echo "9. Resource configuration..."

kubectl get pod \
  "${TEST_POD}" \
  --namespace "${NAMESPACE}" \
  -o jsonpath='Memory request: {.spec.containers[0].resources.requests.memory}{"\n"}Memory limit:   {.spec.containers[0].resources.limits.memory}{"\n"}QoS class:      {.status.qosClass}{"\n"}'

echo
echo "10. Pod summary..."

kubectl get pod \
  "${TEST_POD}" \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "OOMKILLED TEST PASSED."
echo "============================================================"