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

POLICY_DIRECTORY="${REPOSITORY_ROOT}/deploy/kubernetes/base/network-policies"

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
echo "Kubernetes NetworkPolicy setup"
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
echo "2. Checking Calico..."

if ! kubectl get daemonset \
  calico-node \
  --namespace kube-system \
  >/dev/null 2>&1; then

  echo "Calico daemonset was not found." >&2
  echo "NetworkPolicy enforcement cannot be assumed." >&2
  exit 1
fi

kubectl rollout status \
  daemonset/calico-node \
  --namespace kube-system \
  --timeout=120s

echo "PASS: Calico is available."

echo
echo "3. Checking CoreDNS selector..."

DNS_PODS="$(
  kubectl get pods \
    --namespace kube-system \
    --selector='k8s-app=kube-dns' \
    --no-headers \
    2>/dev/null || true
)"

if [[ -z "${DNS_PODS}" ]]; then
  echo "No CoreDNS Pods matching 'k8s-app=kube-dns' were found." >&2
  echo >&2
  kubectl get pods \
    --namespace kube-system \
    --show-labels \
    >&2
  exit 1
fi

echo "PASS: CoreDNS selector is valid."

echo
echo "4. Checking Kong namespace..."

if ! kubectl get namespace \
  kong \
  >/dev/null 2>&1; then

  echo "Namespace 'kong' was not found." >&2
  echo "Complete Kubernetes Ingress step first." >&2
  exit 1
fi

echo "PASS: Kong namespace exists."

echo
echo "5. Checking NetworkPolicy manifests..."

if [[ ! -d "${POLICY_DIRECTORY}" ]]; then
  echo "NetworkPolicy directory was not found:" >&2
  echo "${POLICY_DIRECTORY}" >&2
  exit 1
fi

echo "PASS: NetworkPolicy manifests exist."

echo
echo "6. Applying NetworkPolicies..."

kubectl apply \
  -f "${POLICY_DIRECTORY}"

echo
echo "7. Waiting for policy propagation..."

sleep 5

echo
echo "8. Waiting for Catalog readiness..."

kubectl wait \
  --for=condition=Ready \
  pod \
  --selector='app.kubernetes.io/name=catalog-service,app.kubernetes.io/component=api' \
  --namespace "${NAMESPACE}" \
  --timeout=120s

echo "PASS: Catalog is Ready."

echo
echo "9. Waiting for Pricing readiness..."

kubectl wait \
  --for=condition=Ready \
  pod \
  --selector='app.kubernetes.io/name=pricing-service,app.kubernetes.io/component=api' \
  --namespace "${NAMESPACE}" \
  --timeout=120s

echo "PASS: Pricing is Ready."

echo
echo "10. Applied NetworkPolicies..."

kubectl get networkpolicies \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "NETWORK POLICY SETUP COMPLETED."
echo "============================================================"