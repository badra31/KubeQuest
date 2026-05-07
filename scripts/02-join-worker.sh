#!/bin/bash
# Run this on kube-2 — joins the node as a Kubernetes worker.
# Usage: ./02-join-worker.sh "<full kubeadm join command from control plane>"
set -e

JOIN_CMD="${1:?Usage: $0 '<kubeadm join command>'}"

echo "==> Joining cluster as worker node ..."
sudo $JOIN_CMD

echo "==> Worker joined. Check on kube-1: kubectl get nodes"
