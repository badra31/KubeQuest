#!/bin/bash
# Run this on kube-1 ONLY — initialises the Kubernetes control plane.
# Usage: ./01-init-control-plane.sh <kube-1-private-ip>
set -e

CONTROL_PLANE_IP="${1:?Usage: $0 <control-plane-private-ip>}"
POD_CIDR="192.168.0.0/16"   # Calico default

echo "==> Initialising control plane on $CONTROL_PLANE_IP ..."
sudo kubeadm init \
  --apiserver-advertise-address="$CONTROL_PLANE_IP" \
  --pod-network-cidr="$POD_CIDR" \
  --control-plane-endpoint="$CONTROL_PLANE_IP" \
  --upload-certs

# Copy kubeconfig for ubuntu user
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo "==> Installing Calico CNI (network plugin) ..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

echo ""
echo "==> Control plane ready! Save the join command below for worker nodes:"
kubeadm token create --print-join-command
