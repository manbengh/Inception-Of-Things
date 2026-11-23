#!/bin/sh
set -eu

SERVER_IP="192.168.56.110"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl ca-certificates

PRIVATE_IFACE="$(ip -o -4 addr show | awk -v ip="$SERVER_IP" '$4 ~ "^"ip"/" {print $2; exit}')"
[ -n "$PRIVATE_IFACE" ] || { echo "ERROR: interface for ${SERVER_IP} not found."; ip -br a; exit 1; }

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.5+k3s1" INSTALL_K3S_EXEC="server \
  --node-ip ${SERVER_IP} \
  --advertise-address ${SERVER_IP} \
  --flannel-iface ${PRIVATE_IFACE} \
  --disable traefik \
  --disable metrics-server \
  --write-kubeconfig-mode 644" sh -

# Attendre que le serveur soit prêt
for i in $(seq 1 60); do
  k3s kubectl get nodes >/dev/null 2>&1 && break
  sleep 5
done

# Partager le token avec le worker
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token