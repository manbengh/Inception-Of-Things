#!/bin/sh
set -eu

SERVER_IP="192.168.56.110"
CONFS_DIR="/home/vagrant/confs"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl ca-certificates

# Detect the interface associated with the private IP
PRIVATE_IFACE="$(ip -o -4 addr show | awk -v ip="$SERVER_IP" '$4 ~ "^"ip"/" {print $2; exit}')"

if [ -z "$PRIVATE_IFACE" ]; then
  echo "ERROR: Interface for ${SERVER_IP} not found."
  ip -br address
  exit 1
fi

# Install K3s in server mode (Traefik is the default ingress controller)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.5+k3s1" INSTALL_K3S_EXEC="server \
  --node-ip ${SERVER_IP} \
  --advertise-address ${SERVER_IP} \
  --flannel-iface ${PRIVATE_IFACE} \
  --write-kubeconfig-mode 644" sh -


# Wait for the API server, then for the node to be Ready
# Wait for the node to register, then to be Ready
for i in $(seq 1 60); do
  [ -n "$(k3s kubectl get nodes --no-headers 2>/dev/null)" ] && break
  sleep 5
done

k3s kubectl wait --for=condition=Ready node --all --timeout=300s

# Deploy the 3 applications and the Ingress
k3s kubectl apply -f "${CONFS_DIR}/apps.yaml"
k3s kubectl apply -f "${CONFS_DIR}/ingress.yaml"

# Wait for the applications to be available
k3s kubectl wait --for=condition=Available deployment --all -n default --timeout=300s

echo "K3s server and applications are ready."
k3s kubectl get all,ingress -n default