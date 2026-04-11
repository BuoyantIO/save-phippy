#!/usr/bin/env bash
#
# sp-panopticon.sh – set up a cluster and deploy the panopticon onto
# it in one step.
#
# Usage: sp-panopticon.sh [--dev] [--k3d <cluster-name>] [--civo <cluster-name>]
#
# Environment variables (all optional; override computed defaults):
#   TAG        – image tag to deploy
#   CERTDIR    – path to the certs/ directory
#   CHART      - chart to deploy

TAG=${TAG:-0.5.0}
CERTDIR=${CERTDIR:-$(pwd)/certs}
CHART=${CHART:-oci://ghcr.io/buoyantio/save-phippy-panopticon}

set -euo pipefail

CA_CERT=${CA_CERT:-${CERTDIR}/ca.crt}
PANOPTICON_CERT=${PANOPTICON_CERT:-${CERTDIR}/panopticon.crt}
PANOPTICON_KEY=${PANOPTICON_KEY:-${CERTDIR}/panopticon.key}
TEAMS_CERT=${TEAMS_CERT:-${CERTDIR}/teams.crt}
TEAMS_KEY=${TEAMS_KEY:-${CERTDIR}/teams.key}
USERS_CERT=${USERS_CERT:-${CERTDIR}/users.crt}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: $(basename "$0") [--dev] [--k3d <cluster-name>] [--civo <cluster-name>]" >&2
  exit 1
}

dev_mode=false
provider=
cluster_name=

while [ $# -gt 0 ]; do
  case "$1" in
    --dev)
      dev_mode=true
      shift
      ;;
    --k3d|--civo)
      if [ -n "$provider" ]; then
        usage
      fi
      provider="$1"
      shift
      if [ -z "${1:-}" ]; then
        usage
      fi
      cluster_name="$1"
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [ "$dev_mode" = true ] && [ "$provider" = "--civo" ]; then
  echo "--dev is only supported with k3d or an already-prepared local cluster." >&2
  exit 1
fi

for cmd in spadmin kubectl linkerd helm; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "$cmd not found. Please install it and make sure it is on your \$PATH." >&2
    exit 1
  fi
done

if [ -z "${TAG:-}" ]; then
  echo "TAG environment variable is not set. Please set it to the desired image tag." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: cluster setup
# ---------------------------------------------------------------------------
if [ "$provider" = "--k3d" ]; then
  k3d cluster delete "$cluster_name" || true
  k3d cluster create "$cluster_name" \
    --network canalcaper \
    --no-lb --k3s-arg --disable=traefik@server:0
  k3d kubeconfig get "$cluster_name" > "$HOME/.kube/${cluster_name}.yaml"
  export KUBECONFIG=$HOME/.kube/${cluster_name}.yaml
elif [ "$provider" = "--civo" ]; then
  civo kubernetes delete "$cluster_name" || true
  civo kubernetes create "$cluster_name" --wait --nodes 1 --size g4s.kube.medium --region LON1
  civo kubernetes config "$cluster_name" > "$HOME/.kube/${cluster_name}.yaml"
  export KUBECONFIG=$HOME/.kube/${cluster_name}.yaml
fi

set -x

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd viz install | kubectl apply -f -
linkerd check

kubectl create ns emissary
kubectl annotate ns emissary linkerd.io/inject=enabled
helm install emissary-crds -n emissary \
  oci://ghcr.io/emissary-ingress/emissary-crds-chart --version 4.0.1
helm install emissary -n emissary \
  oci://ghcr.io/emissary-ingress/emissary-ingress --version 4.0.1 \
  --set replicaCount=1 \
  --set module.enabled=false

kubectl rollout status -n emissary deploy

# ---------------------------------------------------------------------------
# Step 2: cert setup
# ---------------------------------------------------------------------------

IP=$(kubectl get svc -n emissary emissary \
             -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

spadmin cert bootstrap --cert-dir "$CERTDIR" "$IP"

# ---------------------------------------------------------------------------
# Step 3: panopticon setup
# ---------------------------------------------------------------------------
kubectl create ns panopticon || true
kubectl annotate ns panopticon linkerd.io/inject=enabled

clientCA=$(mktemp)
trap "rm -f $clientCA" EXIT

cat "$TEAMS_CERT" "$USERS_CERT" > "$clientCA"

helm_args=(
  upgrade -i panopticon -n panopticon \
  $CHART --version $TAG \
  --set defaultImageTag="$TAG"
  --set-file panopticon.crt="$PANOPTICON_CERT"
  --set-file panopticon.key="$PANOPTICON_KEY"
  --set-file teams.crt="$TEAMS_CERT"
  --set-file teams.key="$TEAMS_KEY"
  --set-file ca.crt="$CA_CERT"
  --set-file clientCA.crt=$clientCA
)
if [ "$dev_mode" = true ]; then
  helm_args+=( --set image.pullPolicy=Never )
fi
helm "${helm_args[@]}"

kubectl rollout status -n emissary deploy
kubectl rollout status -n panopticon deploy
