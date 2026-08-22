#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

KONG_NAMESPACE="${KONG_NAMESPACE:-kong}"

LOG_TAIL_LINES="${LOG_TAIL_LINES:-1000}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

OUTPUT_ROOT="${OUTPUT_ROOT:-${REPOSITORY_ROOT}/artifacts/kubernetes-diagnostics}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

OUTPUT_DIRECTORY="${OUTPUT_ROOT}/${TIMESTAMP}"

CLUSTER_DIRECTORY="${OUTPUT_DIRECTORY}/cluster"
NAMESPACE_DIRECTORY="${OUTPUT_DIRECTORY}/namespace"
DESCRIBE_DIRECTORY="${OUTPUT_DIRECTORY}/describe"
LOG_DIRECTORY="${OUTPUT_DIRECTORY}/logs"
NETWORK_DIRECTORY="${OUTPUT_DIRECTORY}/networking"
SYSTEM_DIRECTORY="${OUTPUT_DIRECTORY}/system"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

print_command() {
  local argument

  printf '$'

  for argument in "$@"; do
    printf ' %q' "${argument}"
  done

  printf '\n'
}

collect_command() {
  local output_file="$1"
  shift

  {
    print_command "$@"
    echo
  } > "${output_file}"

  if "$@" >> "${output_file}" 2>&1; then
    return 0
  fi

  local exit_code=$?

  {
    echo
    echo "[diagnostics collector]"
    echo "Command exited with code ${exit_code}."
  } >> "${output_file}"

  return 0
}

collect_describes() {
  local namespace="$1"
  local resource_type="$2"
  local output_subdirectory="$3"

  local resource_name

  mkdir -p "${output_subdirectory}"

  while IFS= read -r resource_name; do
    [[ -z "${resource_name}" ]] && continue

    collect_command \
      "${output_subdirectory}/${resource_name}.txt" \
      kubectl describe \
      "${resource_type}" \
      "${resource_name}" \
      --namespace "${namespace}"
  done < <(
    kubectl get \
      "${resource_type}" \
      --namespace "${namespace}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
      2>/dev/null || true
  )
}

collect_pod_logs() {
  local namespace="$1"
  local destination="$2"

  local pod_name
  local container_name
  local restart_count
  local pod_directory

  mkdir -p "${destination}"

  while IFS= read -r pod_name; do
    [[ -z "${pod_name}" ]] && continue

    pod_directory="${destination}/${pod_name}"

    mkdir -p "${pod_directory}"

    collect_command \
      "${pod_directory}/pod.txt" \
      kubectl get pod \
      "${pod_name}" \
      --namespace "${namespace}" \
      -o wide

    collect_command \
      "${pod_directory}/describe.txt" \
      kubectl describe pod \
      "${pod_name}" \
      --namespace "${namespace}"

    for container_name in $(
      kubectl get pod \
        "${pod_name}" \
        --namespace "${namespace}" \
        -o jsonpath='{.spec.containers[*].name}' \
        2>/dev/null || true
    ); do

      collect_command \
        "${pod_directory}/${container_name}-current.log" \
        kubectl logs \
        "${pod_name}" \
        --namespace "${namespace}" \
        --container "${container_name}" \
        --tail="${LOG_TAIL_LINES}" \
        --timestamps

      restart_count="$(
        kubectl get pod \
          "${pod_name}" \
          --namespace "${namespace}" \
          -o "jsonpath={.status.containerStatuses[?(@.name==\"${container_name}\")].restartCount}" \
          2>/dev/null || true
      )"

      restart_count="${restart_count:-0}"

      if [[ "${restart_count}" =~ ^[0-9]+$ ]] &&
         ((restart_count > 0)); then

        collect_command \
          "${pod_directory}/${container_name}-previous.log" \
          kubectl logs \
          "${pod_name}" \
          --namespace "${namespace}" \
          --container "${container_name}" \
          --previous \
          --tail="${LOG_TAIL_LINES}" \
          --timestamps
      fi
    done

    for container_name in $(
      kubectl get pod \
        "${pod_name}" \
        --namespace "${namespace}" \
        -o jsonpath='{.spec.initContainers[*].name}' \
        2>/dev/null || true
    ); do

      collect_command \
        "${pod_directory}/init-${container_name}.log" \
        kubectl logs \
        "${pod_name}" \
        --namespace "${namespace}" \
        --container "${container_name}" \
        --tail="${LOG_TAIL_LINES}" \
        --timestamps
    done

  done < <(
    kubectl get pods \
      --namespace "${namespace}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
      2>/dev/null || true
  )
}

require_command minikube
require_command kubectl
require_command date
require_command mkdir

mkdir -p \
  "${CLUSTER_DIRECTORY}" \
  "${NAMESPACE_DIRECTORY}" \
  "${DESCRIBE_DIRECTORY}" \
  "${LOG_DIRECTORY}" \
  "${NETWORK_DIRECTORY}" \
  "${SYSTEM_DIRECTORY}"

echo "============================================================"
echo "Kubernetes diagnostics collector"
echo "============================================================"
echo
echo "Profile:   ${PROFILE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Output:    ${OUTPUT_DIRECTORY}"

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
echo "2. Writing collection metadata..."

{
  echo "Kubernetes diagnostics"
  echo "======================"
  echo
  echo "Collected: $(date --iso-8601=seconds)"
  echo "Profile:   ${PROFILE_NAME}"
  echo "Namespace: ${NAMESPACE}"
  echo "Context:   $(kubectl config current-context 2>/dev/null || true)"
  echo
  echo "Log tail lines per container: ${LOG_TAIL_LINES}"
  echo
  echo "Important:"
  echo "- Secret values are intentionally not collected."
  echo "- Application logs may still contain business or diagnostic data."
  echo "- Review this directory before sharing it externally."
} > "${OUTPUT_DIRECTORY}/README.txt"

echo "PASS: Metadata created."

echo
echo "3. Collecting cluster state..."

collect_command \
  "${CLUSTER_DIRECTORY}/minikube-status.txt" \
  minikube status \
  --profile "${PROFILE_NAME}"

collect_command \
  "${CLUSTER_DIRECTORY}/minikube-version.txt" \
  minikube version

collect_command \
  "${CLUSTER_DIRECTORY}/kubectl-version.txt" \
  kubectl version

collect_command \
  "${CLUSTER_DIRECTORY}/current-context.txt" \
  kubectl config current-context

collect_command \
  "${CLUSTER_DIRECTORY}/nodes.txt" \
  kubectl get nodes \
  -o wide

collect_command \
  "${CLUSTER_DIRECTORY}/nodes-describe.txt" \
  kubectl describe nodes

collect_command \
  "${CLUSTER_DIRECTORY}/api-services.txt" \
  kubectl get apiservices \
  -o wide

collect_command \
  "${CLUSTER_DIRECTORY}/ingress-classes.txt" \
  kubectl get ingressclasses \
  -o wide

collect_command \
  "${CLUSTER_DIRECTORY}/namespaces.txt" \
  kubectl get namespaces \
  --show-labels

echo "PASS: Cluster state collected."

echo
echo "4. Collecting namespace overview..."

collect_command \
  "${NAMESPACE_DIRECTORY}/all.txt" \
  kubectl get all \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NAMESPACE_DIRECTORY}/pods.txt" \
  kubectl get pods \
  --namespace "${NAMESPACE}" \
  -o wide \
  --show-labels

collect_command \
  "${NAMESPACE_DIRECTORY}/deployments.txt" \
  kubectl get deployments \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NAMESPACE_DIRECTORY}/replicasets.txt" \
  kubectl get replicasets \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NAMESPACE_DIRECTORY}/statefulsets.txt" \
  kubectl get statefulsets \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NAMESPACE_DIRECTORY}/jobs.txt" \
  kubectl get jobs \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NAMESPACE_DIRECTORY}/services.txt" \
  kubectl get services \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NAMESPACE_DIRECTORY}/pvc.txt" \
  kubectl get pvc \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NAMESPACE_DIRECTORY}/configmaps.txt" \
  kubectl get configmaps \
  --namespace "${NAMESPACE}"

collect_command \
  "${NAMESPACE_DIRECTORY}/secrets-metadata-only.txt" \
  kubectl get secrets \
  --namespace "${NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp'

echo "PASS: Namespace overview collected."

echo
echo "5. Collecting Kubernetes events..."

collect_command \
  "${NAMESPACE_DIRECTORY}/events.txt" \
  kubectl get events \
  --namespace "${NAMESPACE}" \
  --sort-by=.metadata.creationTimestamp

collect_command \
  "${NAMESPACE_DIRECTORY}/warning-events.txt" \
  kubectl events \
  --namespace "${NAMESPACE}" \
  --types=Warning

echo "PASS: Events collected."

echo
echo "6. Collecting networking state..."

collect_command \
  "${NETWORK_DIRECTORY}/services.txt" \
  kubectl get services \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NETWORK_DIRECTORY}/endpoint-slices.txt" \
  kubectl get endpointslices \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NETWORK_DIRECTORY}/ingress.txt" \
  kubectl get ingress \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NETWORK_DIRECTORY}/network-policies.txt" \
  kubectl get networkpolicies \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NETWORK_DIRECTORY}/hpa.txt" \
  kubectl get hpa \
  --namespace "${NAMESPACE}" \
  -o wide

collect_command \
  "${NETWORK_DIRECTORY}/pod-metrics.txt" \
  kubectl top pods \
  --namespace "${NAMESPACE}"

collect_command \
  "${NETWORK_DIRECTORY}/node-metrics.txt" \
  kubectl top nodes

echo "PASS: Networking and metrics collected."

echo
echo "7. Collecting detailed resource descriptions..."

collect_describes \
  "${NAMESPACE}" \
  deployments \
  "${DESCRIBE_DIRECTORY}/deployments"

collect_describes \
  "${NAMESPACE}" \
  replicasets \
  "${DESCRIBE_DIRECTORY}/replicasets"

collect_describes \
  "${NAMESPACE}" \
  statefulsets \
  "${DESCRIBE_DIRECTORY}/statefulsets"

collect_describes \
  "${NAMESPACE}" \
  jobs \
  "${DESCRIBE_DIRECTORY}/jobs"

collect_describes \
  "${NAMESPACE}" \
  services \
  "${DESCRIBE_DIRECTORY}/services"

collect_describes \
  "${NAMESPACE}" \
  ingress \
  "${DESCRIBE_DIRECTORY}/ingress"

collect_describes \
  "${NAMESPACE}" \
  networkpolicies \
  "${DESCRIBE_DIRECTORY}/network-policies"

collect_describes \
  "${NAMESPACE}" \
  hpa \
  "${DESCRIBE_DIRECTORY}/hpa"

collect_describes \
  "${NAMESPACE}" \
  pvc \
  "${DESCRIBE_DIRECTORY}/pvc"

echo "PASS: Resource descriptions collected."

echo
echo "8. Collecting application Pod logs..."

collect_pod_logs \
  "${NAMESPACE}" \
  "${LOG_DIRECTORY}/${NAMESPACE}"

echo "PASS: Application logs collected."

echo
echo "9. Collecting Kong state..."

if kubectl get namespace \
  "${KONG_NAMESPACE}" \
  >/dev/null 2>&1; then

  collect_command \
    "${SYSTEM_DIRECTORY}/kong-resources.txt" \
    kubectl get all \
    --namespace "${KONG_NAMESPACE}" \
    -o wide

  collect_command \
    "${SYSTEM_DIRECTORY}/kong-events.txt" \
    kubectl get events \
    --namespace "${KONG_NAMESPACE}" \
    --sort-by=.metadata.creationTimestamp

  collect_command \
    "${SYSTEM_DIRECTORY}/kong-controller-deployment.txt" \
    kubectl describe deployment \
    ingress-kong \
    --namespace "${KONG_NAMESPACE}"

  collect_command \
    "${SYSTEM_DIRECTORY}/kong-cluster-role.txt" \
    kubectl describe clusterrole \
    kong-ingress

  collect_pod_logs \
    "${KONG_NAMESPACE}" \
    "${LOG_DIRECTORY}/${KONG_NAMESPACE}"
else
  echo "Namespace '${KONG_NAMESPACE}' does not exist." \
    > "${SYSTEM_DIRECTORY}/kong-not-installed.txt"
fi

echo "PASS: Kong diagnostics collected."

echo
echo "10. Collecting Calico state..."

collect_command \
  "${SYSTEM_DIRECTORY}/calico-pods.txt" \
  kubectl get pods \
  --namespace kube-system \
  -o wide \
  --selector='k8s-app=calico-node'

collect_command \
  "${SYSTEM_DIRECTORY}/calico-node-daemonset.txt" \
  kubectl describe daemonset \
  calico-node \
  --namespace kube-system

collect_command \
  "${SYSTEM_DIRECTORY}/calico-controller.txt" \
  kubectl describe deployment \
  calico-kube-controllers \
  --namespace kube-system

collect_command \
  "${SYSTEM_DIRECTORY}/calico-node-logs.txt" \
  kubectl logs \
  --namespace kube-system \
  --selector='k8s-app=calico-node' \
  --all-containers=true \
  --tail="${LOG_TAIL_LINES}" \
  --timestamps \
  --prefix=true

collect_command \
  "${SYSTEM_DIRECTORY}/calico-controller-logs.txt" \
  kubectl logs \
  --namespace kube-system \
  --selector='k8s-app=calico-kube-controllers' \
  --all-containers=true \
  --tail="${LOG_TAIL_LINES}" \
  --timestamps \
  --prefix=true

echo "PASS: Calico diagnostics collected."

echo
echo "11. Collecting Metrics Server state..."

collect_command \
  "${SYSTEM_DIRECTORY}/metrics-server-deployment.txt" \
  kubectl describe deployment \
  metrics-server \
  --namespace kube-system

collect_command \
  "${SYSTEM_DIRECTORY}/metrics-server-logs.txt" \
  kubectl logs \
  deployment/metrics-server \
  --namespace kube-system \
  --tail="${LOG_TAIL_LINES}" \
  --timestamps

collect_command \
  "${SYSTEM_DIRECTORY}/metrics-api-service.txt" \
  kubectl describe apiservice \
  v1beta1.metrics.k8s.io

echo "PASS: Metrics Server diagnostics collected."

echo
echo "12. Creating quick summary..."

{
  echo "KUBERNETES DIAGNOSTIC SUMMARY"
  echo "============================="
  echo
  echo "Collected:"
  date --iso-8601=seconds
  echo

  echo "Context:"
  kubectl config current-context 2>/dev/null || true
  echo

  echo "Pods:"
  kubectl get pods \
    --namespace "${NAMESPACE}" \
    -o wide \
    2>&1 || true
  echo

  echo "Deployments:"
  kubectl get deployments \
    --namespace "${NAMESPACE}" \
    2>&1 || true
  echo

  echo "StatefulSets:"
  kubectl get statefulsets \
    --namespace "${NAMESPACE}" \
    2>&1 || true
  echo

  echo "Jobs:"
  kubectl get jobs \
    --namespace "${NAMESPACE}" \
    2>&1 || true
  echo

  echo "Ingress:"
  kubectl get ingress \
    --namespace "${NAMESPACE}" \
    2>&1 || true
  echo

  echo "NetworkPolicies:"
  kubectl get networkpolicies \
    --namespace "${NAMESPACE}" \
    2>&1 || true
  echo

  echo "HPA:"
  kubectl get hpa \
    --namespace "${NAMESPACE}" \
    2>&1 || true
  echo

  echo "Recent warning events:"
  kubectl events \
    --namespace "${NAMESPACE}" \
    --types=Warning \
    2>&1 || true

} > "${OUTPUT_DIRECTORY}/SUMMARY.txt"

echo "PASS: Summary created."

echo
echo "============================================================"
echo "DIAGNOSTICS COLLECTION COMPLETED."
echo "============================================================"
echo
echo "Output:"
echo "  ${OUTPUT_DIRECTORY}"
echo
echo "Start with:"
echo "  ${OUTPUT_DIRECTORY}/SUMMARY.txt"
echo
echo "Important:"
echo "  Review logs before sharing the diagnostics externally."