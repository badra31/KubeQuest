#!/bin/bash
# Run this on kube-1 — installs Helm, kubens, kubectx and bash completions.
set -e

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm completion bash > /etc/bash_completion.d/helm
echo "Helm $(helm version --short) installed"

# kubectx + kubens
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens  /usr/local/bin/kubens

# kubectl bash completion
kubectl completion bash > /etc/bash_completion.d/kubectl
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# Add Helm repos used in this project
helm repo add ingress-nginx   https://kubernetes.github.io/ingress-nginx
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana          https://grafana.github.io/helm-charts
helm repo add bitnami          https://charts.bitnami.com/bitnami
helm repo update

echo ""
echo "==> All tools installed. Re-login or run: source ~/.bashrc"
