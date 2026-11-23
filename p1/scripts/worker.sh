#!/bin/sh
set -eu

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"
TOKEN_FILE="/vagrant/node-token"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl ca-certificates

# Detect the interface associated with the private IP
PRIVATE_IFACE="$(ip -o -4 addr show | awk -v ip="$WORKER_IP" '$4 ~ "^"ip"/" {print $2; exit}')"

if [ -z "$PRIVATE_IFACE" ]; then
  echo "ERROR: Interface for ${WORKER_IP} not found."
  ip -br address
  exit 1
fi

# Wait for the token shared by the server
echo "Waiting for node token at ${TOKEN_FILE}..."
for i in $(seq 1 60); do
  [ -s "$TOKEN_FILE" ] && break
  sleep 5
done

if [ ! -s "$TOKEN_FILE" ]; then
  echo "ERROR: node token not found at ${TOKEN_FILE}."
  exit 1
fi

K3S_TOKEN="$(cat "$TOKEN_FILE")"

# Wait for the K3s API server
echo "Waiting for K3s server at ${SERVER_IP}:6443..."
READY=0
for i in $(seq 1 60); do
  if curl -ksf --connect-timeout 2 "https://${SERVER_IP}:6443/ping" >/dev/null; then
    READY=1
    break
  fi
  sleep 5
done

if [ "$READY" -ne 1 ]; then
  echo "ERROR: K3s server is not reachable."
  exit 1
fi

# Install K3s in agent mode
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="v1.36.5+k3s1" \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="agent --node-ip ${WORKER_IP} --flannel-iface ${PRIVATE_IFACE}" \
  sh -

# Wait for the agent service
for i in $(seq 1 60); do
  systemctl is-active --quiet k3s-agent && break
  sleep 5
done

if ! systemctl is-active --quiet k3s-agent; then
  echo "ERROR: K3s agent did not start."
  systemctl status k3s-agent --no-pager || true
  exit 1
fi

echo "K3s worker installation complete."
systemctl status k3s-agent --no-pager