#!/usr/bin/env bash
# sp-station.sh – set up a cluster and deploy a station onto it in one step.
# Combines the functionality of setup-cluster.sh and setup-station.sh.
#
# Usage: sp-station.sh [--dev] [--k3d <cluster-name>] [--civo <cluster-name>]
#                      [--cluster <name>]
#
# Environment variables (all optional; override computed defaults):
#   TAG        – image tag to deploy
#   CERTDIR    – path to the certs/ directory   (default: ./certs)
#   CHART      - chart to deploy

TAG=${TAG:-0.6.0}
CERTDIR=${CERTDIR:-$(pwd)/certs}
CHART=${CHART:-oci://ghcr.io/buoyantio/save-phippy-station}

set -euo pipefail

CA_CERT=${CA_CERT:-${CERTDIR}/ca.crt}
USERS_CERT=${USERS_CERT:-${CERTDIR}/users.crt}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: $(basename "$0") [--dev] [--k3d <cluster-name>] [--civo <cluster-name>] [--cluster <name>]" >&2
  exit 1
}

dev_mode=false
provider=
cluster_name=
explicit_cluster_name=

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
    --cluster)
      shift
      if [ -z "${1:-}" ]; then
        echo "Error: --cluster option requires an argument." >&2
        usage
      fi
      explicit_cluster_name="$1"
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

for cmd in spadmin kubectl linkerd helm yq; do
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
    --config "$HOME/bin/k3d-pull-through.yaml" \
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
# Step 2: station setup
# ---------------------------------------------------------------------------

# Resolve the cluster name for station: explicit --cluster wins, then the name
# given to --k3d/--civo, then fall back to the current kubectl context.
if [ -n "$explicit_cluster_name" ]; then
  station_cluster_name="$explicit_cluster_name"
elif [ -n "$cluster_name" ]; then
  station_cluster_name="$cluster_name"
else
  station_cluster_name=$(kubectl config current-context | sed -e 's/^k3d-//')
fi

echo "dev_mode: $dev_mode"
echo "cluster_name: $station_cluster_name"

kubectl create ns station || true
kubectl annotate ns station linkerd.io/inject=enabled --overwrite

clientCA=$(mktemp)
trap "rm -f $clientCA" EXIT

cat "$CA_CERT" "$USERS_CERT" > "$clientCA"

helm_args=(
  upgrade -i station -n station \
  $CHART --version $TAG \
  --set "defaultImageTag=$TAG"
  --set "clusterName=$station_cluster_name"
  --set-file adminClientCA.crt="$clientCA"
)
if [ "$dev_mode" = true ]; then
  helm_args+=( -f "${CHARTDIR}/station/values-dev.yaml" )
fi
helm "${helm_args[@]}"

kubectl rollout status -n emissary deploy
kubectl rollout status -n station deploy

# ---------------------------------------------------------------------------
# Fix k3d API server IP and register the cluster with admin
# ---------------------------------------------------------------------------
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
export CTX=$(kubectl config current-context)

export CLUSTER_NAME=$(yq eval '.contexts[] | select(.name == env(CTX)) | .context.cluster' $KUBECONFIG)

if [ -z "$CLUSTER_NAME" ]; then
    echo "Failed to extract cluster name from kubeconfig"
    exit 1
fi

CLUSTER_IP=$(yq eval '.clusters[] | select(.name == env(CLUSTER_NAME)) | .cluster.server' $KUBECONFIG \
               | cut -d: -f2 | tr -d /)

if [ -z "$CLUSTER_IP" ]; then
    echo "Failed to extract cluster IP from kubeconfig"
    exit 1
fi

echo "Current cluster:       $CLUSTER_NAME"
echo "Current API server IP: $CLUSTER_IP"

if [ "$CLUSTER_IP" == "0.0.0.0" ]; then
     if [ $(echo "$CLUSTER_NAME" | grep -c "^k3d-") -eq 0 ]; then
          echo "Forwarded API server detected, but not k3d?" >&2
          exit 1
     fi

     CLUSTER_IP=$(docker inspect ${CLUSTER_NAME}-server-0 \
                      | jq -r '.[0].NetworkSettings.Networks[].IPAddress')
     APISERVER_URL="https://${CLUSTER_IP}:6443"
     echo "Forcing forwarded API server to $APISERVER_URL"
     kubectl config set clusters.${CLUSTER_NAME}.server $APISERVER_URL
fi

spadmin cluster add
