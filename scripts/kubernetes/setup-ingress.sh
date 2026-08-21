#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE_NAME="${PROFILE_NAME:-micros-02-qa}"
NAMESPACE="${NAMESPACE:-micros-02-qa}"

KONG_NAMESPACE="${KONG_NAMESPACE:-kong}"
KONG_DEPLOYMENT="${KONG_DEPLOYMENT:-ingress-kong}"
KONG_CLUSTER_ROLE="${KONG_CLUSTER_ROLE:-kong-ingress}"
KONG_SERVICE_ACCOUNT="${KONG_SERVICE_ACCOUNT:-kong-serviceaccount}"

INGRESS_CLASS="${INGRESS_CLASS:-kong}"

# Minikube v1.38.1 Kong addon currently deploys KIC 3.5.3,
# but its addon manifests are missing part of the CRDs/RBAC/configuration
# expected by that controller version.
KIC_VERSION="${KIC_VERSION:-v3.5.3}"
KIC_CRD_SOURCE="https://github.com/Kong/kubernetes-ingress-controller/config/crd/?ref=${KIC_VERSION}"

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

REPOSITORY_ROOT="$(
  cd -- "${SCRIPT_DIRECTORY}/../.." >/dev/null 2>&1
  pwd
)"

INGRESS_MANIFEST="${REPOSITORY_ROOT}/deploy/kubernetes/base/ingress/api-ingress.yaml"

KONG_SERVICE_ACCOUNT_SUBJECT="system:serviceaccount:${KONG_NAMESPACE}:${KONG_SERVICE_ACCOUNT}"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found in PATH." >&2
    exit 1
  fi
}

can_service_account_list() {
  local resource="$1"

  [[ "$(
    kubectl auth can-i \
      --as="${KONG_SERVICE_ACCOUNT_SUBJECT}" \
      list \
      "${resource}" \
      --all-namespaces \
      2>/dev/null || true
  )" == "yes" ]]
}

echo "============================================================"
echo "Kong Ingress setup"
echo "============================================================"

require_command minikube
require_command kubectl
require_command awk
require_command grep

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
echo "2. Checking Kong addon availability..."

ADDONS="$(
  minikube addons list \
    --profile "${PROFILE_NAME}"
)"

if ! printf '%s\n' "${ADDONS}" |
  grep -qi 'kong'; then

  echo "Kong addon is not available in this Minikube installation." >&2
  echo >&2
  minikube version >&2
  exit 1
fi

echo "PASS: Kong addon is available."

echo
echo "3. Disabling legacy ingress addon if enabled..."

minikube addons disable ingress \
  --profile "${PROFILE_NAME}" \
  >/dev/null 2>&1 || true

echo "Done."

echo
echo "4. Enabling Kong addon..."

minikube addons enable kong \
  --profile "${PROFILE_NAME}"

echo
echo "5. Waiting for Kong namespace..."

for ((attempt = 1; attempt <= 60; attempt++)); do
  if kubectl get namespace \
    "${KONG_NAMESPACE}" \
    >/dev/null 2>&1; then

    break
  fi

  if ((attempt == 60)); then
    echo "Namespace '${KONG_NAMESPACE}' was not created." >&2
    exit 1
  fi

  sleep 1
done

echo "PASS: Kong namespace exists."

echo
echo "6. Waiting for Kong controller Deployment..."

for ((attempt = 1; attempt <= 60; attempt++)); do
  if kubectl get deployment \
    "${KONG_DEPLOYMENT}" \
    --namespace "${KONG_NAMESPACE}" \
    >/dev/null 2>&1; then

    break
  fi

  if ((attempt == 60)); then
    echo "Deployment '${KONG_DEPLOYMENT}' was not created." >&2
    exit 1
  fi

  sleep 1
done

echo "PASS: Kong controller Deployment exists."

echo
echo "7. Installing KIC ${KIC_VERSION} CRDs..."

kubectl kustomize \
  "${KIC_CRD_SOURCE}" |
kubectl apply -f -

echo "PASS: KIC CRDs are installed."

echo
echo "8. Checking Kong ClusterRole..."

if ! kubectl get clusterrole \
  "${KONG_CLUSTER_ROLE}" \
  >/dev/null 2>&1; then

  echo "ClusterRole '${KONG_CLUSTER_ROLE}' was not found." >&2
  exit 1
fi

echo "PASS: Kong ClusterRole exists."

echo
echo "9. Ensuring CRD discovery RBAC..."

if can_service_account_list \
  "customresourcedefinitions.apiextensions.k8s.io"; then

  echo "PASS: CRD permissions already exist."
else
  kubectl patch clusterrole \
    "${KONG_CLUSTER_ROLE}" \
    --type='json' \
    -p='[
      {
        "op": "add",
        "path": "/rules/-",
        "value": {
          "apiGroups": ["apiextensions.k8s.io"],
          "resources": ["customresourcedefinitions"],
          "verbs": ["get", "list", "watch"]
        }
      }
    ]'

  echo "PASS: CRD permissions added."
fi

echo
echo "10. Ensuring ConfigMap RBAC..."

if can_service_account_list "configmaps"; then
  echo "PASS: ConfigMap permissions already exist."
else
  kubectl patch clusterrole \
    "${KONG_CLUSTER_ROLE}" \
    --type='json' \
    -p='[
      {
        "op": "add",
        "path": "/rules/-",
        "value": {
          "apiGroups": [""],
          "resources": ["configmaps"],
          "verbs": ["get", "list", "watch"]
        }
      }
    ]'

  echo "PASS: ConfigMap permissions added."
fi

echo
echo "11. Ensuring Kong CRD RBAC..."

KONG_CRD_RESOURCES=(
  kongconsumergroups
  kongcustomentities
  kongupstreampolicies
  kongvaults
  konglicenses
)

KONG_CRD_RBAC_REQUIRED="false"

for resource in "${KONG_CRD_RESOURCES[@]}"; do
  if ! can_service_account_list \
    "${resource}.configuration.konghq.com"; then

    KONG_CRD_RBAC_REQUIRED="true"
    break
  fi
done

if [[ "${KONG_CRD_RBAC_REQUIRED}" == "true" ]]; then
  kubectl patch clusterrole \
    "${KONG_CLUSTER_ROLE}" \
    --type='json' \
    -p='[
      {
        "op": "add",
        "path": "/rules/-",
        "value": {
          "apiGroups": ["configuration.konghq.com"],
          "resources": [
            "kongconsumergroups",
            "kongcustomentities",
            "kongupstreampolicies",
            "kongvaults",
            "konglicenses"
          ],
          "verbs": ["get", "list", "watch"]
        }
      }
    ]'

  echo "PASS: Kong CRD permissions added."
else
  echo "PASS: Kong CRD permissions already exist."
fi

echo
echo "12. Configuring Kong Admin API Service port discovery..."

kubectl set env \
  deployment/"${KONG_DEPLOYMENT}" \
  --namespace "${KONG_NAMESPACE}" \
  CONTROLLER_KONG_ADMIN_SVC_PORT_NAMES=admin

echo "PASS: Kong Admin API port name configured."

echo
echo "13. Restarting Kong Ingress Controller..."

kubectl rollout restart \
  deployment/"${KONG_DEPLOYMENT}" \
  --namespace "${KONG_NAMESPACE}"

echo
echo "14. Waiting for Kong Ingress Controller..."

kubectl rollout status \
  deployment/"${KONG_DEPLOYMENT}" \
  --namespace "${KONG_NAMESPACE}" \
  --timeout=180s

echo "PASS: Kong Ingress Controller is available."

echo
echo "15. Waiting for all Kong Deployments..."

kubectl wait \
  --for=condition=Available \
  deployment \
  --all \
  --namespace "${KONG_NAMESPACE}" \
  --timeout=180s

echo "PASS: All Kong Deployments are available."

echo
echo "16. Checking IngressClass..."

if ! kubectl get ingressclass \
  "${INGRESS_CLASS}" \
  >/dev/null 2>&1; then

  echo "IngressClass '${INGRESS_CLASS}' was not found." >&2
  echo >&2
  kubectl get ingressclass >&2
  exit 1
fi

kubectl get ingressclass \
  "${INGRESS_CLASS}"

echo "PASS: IngressClass '${INGRESS_CLASS}' exists."

echo
echo "17. Finding Kong proxy Service..."

KONG_PROXY_SERVICE="$(
  kubectl get services \
    --namespace "${KONG_NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .spec.ports[*]}{.port}{" "}{end}{"\n"}{end}' |
  awk '$1 ~ /proxy/ && $0 ~ /(^| )80( |$)/ { print $1; exit }'
)"

if [[ -z "${KONG_PROXY_SERVICE}" ]]; then
  echo "Could not find a Kong proxy Service exposing port 80." >&2
  echo >&2

  kubectl get services \
    --namespace "${KONG_NAMESPACE}" \
    >&2

  exit 1
fi

echo "Kong proxy Service: ${KONG_PROXY_SERVICE}"

echo
echo "18. Checking Ingress manifest..."

if [[ ! -f "${INGRESS_MANIFEST}" ]]; then
  echo "Ingress manifest was not found:" >&2
  echo "${INGRESS_MANIFEST}" >&2
  exit 1
fi

echo "PASS: Ingress manifest exists."

echo
echo "19. Applying application Ingress..."

kubectl apply \
  -f "${INGRESS_MANIFEST}"

echo
echo "20. Ingress configuration..."

kubectl get ingress \
  --namespace "${NAMESPACE}"

echo
echo "============================================================"
echo "KONG INGRESS SETUP COMPLETED."
echo "============================================================"
echo
echo "Compatibility:"
echo "  Minikube profile: ${PROFILE_NAME}"
echo "  KIC CRDs:         ${KIC_VERSION}"
echo
echo "Proxy Service:"
echo "  ${KONG_PROXY_SERVICE}"
echo
echo "Manual access:"
echo "  kubectl port-forward \\"
echo "    --namespace ${KONG_NAMESPACE} \\"
echo "    service/${KONG_PROXY_SERVICE} \\"
echo "    8088:80"