# KubeQuest

Déploiement d'une application Laravel sur un cluster Kubernetes hébergé sur AWS.

## Architecture

```
INTERNET
    │
    ▼
┌─────────────────────┐
│   VM ingress        │  ← reçoit le trafic HTTP/HTTPS
│   nginx :80/:443    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────────────────────────┐
│              CLUSTER KUBERNETES                      │
│                                                      │
│  namespace: ingress-nginx  → nginx-ingress           │
│  namespace: kubernetes-dashboard → dashboard         │
│  namespace: monitoring     → Prometheus, Grafana,    │
│                              Loki, Promtail          │
│  namespace: app            → Laravel + PostgreSQL    │
│                                                      │
│  kube-1 (control plane + worker)                     │
│  kube-2 (worker)                                     │
└─────────────────────────────────────────────────────┘
```

## Prérequis

- AWS CLI configuré (`aws configure`)
- Terraform >= 1.5
- kubectl
- Helm >= 3
- Clé SSH : `~/.ssh/kube-quest` / `~/.ssh/kube-quest.pub`

---

## 1. Infrastructure AWS (Terraform)

### Créer les VMs

```bash
cd terraform
terraform init
terraform apply -var="key_name=kube-quest-key"
```

### Démarrer les VMs (après arrêt)

```bash
aws ec2 start-instances \
  --instance-ids $(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=kube-quest" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text) \
  --region eu-west-1
```

### Arrêter les VMs (pour économiser)

```bash
aws ec2 stop-instances \
  --instance-ids $(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=kube-quest" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text) \
  --region eu-west-1
```

### Voir les IPs des VMs

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=kube-quest" \
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,State:State.Name,IP:PublicIpAddress}" \
  --output table \
  --region eu-west-1
```

### Détruire toute l'infrastructure

```bash
terraform destroy -var="key_name=kube-quest-key"
```

---

## 2. Connexion SSH aux VMs

```bash
ssh -i ~/.ssh/kube-quest ubuntu@<IP_KUBE_1>
ssh -i ~/.ssh/kube-quest ubuntu@<IP_KUBE_2>
ssh -i ~/.ssh/kube-quest ubuntu@<IP_INGRESS>
ssh -i ~/.ssh/kube-quest ubuntu@<IP_MONITORING>
```

---

## 3. Installation du cluster Kubernetes

### Sur kube-1 — initialiser le control plane

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<IP_PRIVEE_KUBE_1> \
  --pod-network-cidr=192.168.0.0/16
```

### Sur kube-1 — configurer kubectl

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Sur kube-1 — installer le réseau Calico

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

### Sur kube-2 — rejoindre le cluster

```bash
sudo kubeadm join <IP_PRIVEE_KUBE_1>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### Sur kube-1 — installer le stockage local

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Vérifier le cluster

```bash
kubectl get nodes
```

---

## 4. Installation des outils (sur kube-1)

### Installer Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Ajouter les repos Helm

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

---

## 5. Déploiement des composants infra (sur kube-1)

### nginx-ingress

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
```

### Kubernetes Dashboard

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### Prometheus + Grafana

```bash
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.retention=7d
```

Accès Grafana : `http://<IP_KUBE_1>:NodePort` — login: `admin` / `admin123`

### Loki (logs)

```bash
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=false
```

---

## 6. Déploiement de l'application

### Copier le chart sur kube-1 (depuis WSL local)

```bash
scp -i ~/.ssh/kube-quest -r "/mnt/c/Developpement app/dev/Projet cloud/kube-quest/helm/sample-app" ubuntu@<IP_KUBE_1>:~/
```

### Installer l'application (sur kube-1)

```bash
helm upgrade --install sample-app ~/sample-app \
  --namespace app \
  --create-namespace
```

### Lancer les migrations Laravel

```bash
kubectl exec -it <POD_NAME> -n app -- php artisan migrate --force
```

### Vérifier les pods

```bash
kubectl get pods -n app
kubectl get pods -n monitoring
kubectl get pods -n ingress-nginx
kubectl get pods -n kubernetes-dashboard
```

---

## 7. Commandes utiles kubectl

```bash
# Voir tous les pods de tous les namespaces
kubectl get pods -A

# Voir les logs d'un pod
kubectl logs <POD_NAME> -n <NAMESPACE>

# Entrer dans un pod
kubectl exec -it <POD_NAME> -n <NAMESPACE> -- /bin/bash

# Voir les détails d'un pod (utile pour déboguer)
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Scaler un déploiement
kubectl scale deployment sample-app --replicas=3 -n app

# Voir l'historique Helm
helm history sample-app -n app

# Rollback Helm
helm rollback sample-app -n app
```

---

## 8. CI/CD — GitHub Actions

L'image Docker est buildée et poussée automatiquement sur `ghcr.io/badra31/kube-quest-app:latest` à chaque push sur `main`.

Workflow : `.github/workflows/build.yml`
