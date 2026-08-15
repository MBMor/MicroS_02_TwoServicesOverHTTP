#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"
CPUS="${CPUS:-4}"
MEMORY_MB="${MEMORY_MB:-6144}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

NAMESPACE_MANIFEST="${REPOSITORY_ROOT}/deploy/kubernetes/base/namespace.yaml"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

require_command docker
require_command minikube
require_command kubectl

if [[ ! -f "${NAMESPACE_MANIFEST}" ]]; then
  echo "Namespace manifest was not found:" >&2
  echo "${NAMESPACE_MANIFEST}" >&2
  exit 1
fi

echo "Checking Docker..."

docker_os_type="$(docker info --format '{{.OSType}}')"

if [[ "${docker_os_type}" != "linux" ]]; then
  echo "Docker must use Linux containers." >&2
  echo "Current container type: ${docker_os_type}" >&2
  exit 1
fi

echo "Starting Minikube profile '${PROFILE_NAME}'..."

minikube start \
  --profile="${PROFILE_NAME}" \
  --driver=docker \
  --container-runtime=containerd \
  --cni=calico \
  --cpus="${CPUS}" \
  --memory="${MEMORY_MB}"

echo "Selecting Kubernetes context '${PROFILE_NAME}'..."

kubectl config use-context "${PROFILE_NAME}"

echo "Waiting for the Kubernetes node..."

kubectl wait \
  --for=condition=Ready \
  node \
  --all \
  --timeout=240s

echo "Applying namespace manifest..."

kubectl apply -f "${NAMESPACE_MANIFEST}"

echo "Setting default namespace '${NAMESPACE}'..."

kubectl config set-context \
  --current \
  --namespace="${NAMESPACE}"

echo
echo "Cluster status:"

minikube status --profile "${PROFILE_NAME}"

echo
echo "Nodes:"

kubectl get nodes -o wide

echo
echo "Namespace:"

kubectl get namespace "${NAMESPACE}" --show-labels

echo
echo "Minikube cluster '${PROFILE_NAME}' is ready."