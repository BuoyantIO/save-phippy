#!/usr/bin/env bash
# init-single.sh — bootstrap a single-cluster save-phippy deployment.
#
# Assumes KUBECONFIG points at a fresh, empty cluster.  Runs all the steps
# needed to go from nothing to a fully functioning station:
#
#   1. Bootstrap admin TLS certificates (CA + intermediates + user cert)
#   2. Install the cluster stack: gateway-api CRDs, Linkerd, Emissary
#   3. Deploy the station Helm chart (no external panopticon)
#   4. Sign and install the station TLS certificate using the Emissary IP
#
# Environment variables (all optional; override computed defaults):
#   TAG        – image tag to deploy (no leading 'v')
#   CERTDIR    – path to the certs/ directory   (default: ./certs)
#   CHART      - chart to deploy
#   TEAM_NAME  - team name for station (defaults to $USER or team)

TAG=${TAG:-0.8.0}
CERTDIR=${CERTDIR:-$(pwd)/certs}
CHART=${CHART:-oci://ghcr.io/buoyantio/save-phippy-station}
_USER=$(printf '%s' "${USER}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')
TEAM_NAME=${TEAM_NAME:-${_USER:-team}}

for cmd in spadmin kubectl linkerd helm; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "$cmd not found. Please install it and make sure it is on your \$PATH." >&2
        exit 1
    fi
done

if ! kubectl get ns > /dev/null 2>&1; then
    echo "kubectl is not configured correctly. Please check your KUBECONFIG." >&2
    exit 1
fi

echo "Initializing single-cluster save-phippy deployment with tag ${TAG} ..."

set -e

# ---------------------------------------------------------------------------
# Step 1: Bootstrap admin TLS certificates
# ---------------------------------------------------------------------------
# Use "localhost" as a placeholder SAN for the panopticon certificate; the
# panopticon service is not deployed in single-cluster mode.
ADMIN_USER=${ADMIN_ID:-${_USER:-admin}}

echo "==> Bootstrapping admin TLS certificates in $CERTDIR ..."
spadmin cert bootstrap --cert-dir "$CERTDIR" localhost

echo "==> Generating CSR and signing certificate for admin user \"$ADMIN_USER\" ..."
spadmin cert csr --out-dir "$CERTDIR" "$ADMIN_USER"
spadmin cert sign \
    --cert-dir "$CERTDIR" \
    --out "$CERTDIR/$ADMIN_USER.crt" \
    "$CERTDIR/$ADMIN_USER.csr"

# ---------------------------------------------------------------------------
# Step 2: Install the cluster stack
# ---------------------------------------------------------------------------
set -ux

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
# Step 3: Deploy the station Helm chart
# ---------------------------------------------------------------------------
cluster_name=$(kubectl config current-context | sed -e 's/^k3d-//')

kubectl create ns station || true
kubectl annotate ns station linkerd.io/inject=enabled --overwrite

clientCA=$(mktemp)
trap "rm -f $clientCA" EXIT

# Combine root CA and users intermediate CA so that admin user certs are trusted.
cat "$CERTDIR/ca.crt" "$CERTDIR/users.crt" > "$clientCA"

helm upgrade -i station -n station \
    $CHART --version $TAG \
    --set "defaultImageTag=$TAG" \
    --set "clusterName=$cluster_name" \
    --set "teamName=$TEAM_NAME" \
    --set-file adminClientCA.crt="$clientCA"

kubectl rollout status -n emissary deploy
kubectl rollout status -n station deploy

# ---------------------------------------------------------------------------
# Step 4: Sign and install the station TLS certificate
# ---------------------------------------------------------------------------
# This mirrors what "admin cluster add" does for cert management, but without
# registering the cluster with caperd.  The Emissary IP is auto-detected from
# the cluster and used as a SAN in the canal-controller certificate.

spadmin cluster sign-cert --cert-dir "$CERTDIR"
