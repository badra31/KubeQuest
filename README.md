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
  --set grafana.adminPassword=<mot-de-passe-a-choisir> \
  --set prometheus.prometheusSpec.retention=7d
```

Accès Grafana : `http://<IP_KUBE_1>:NodePort` — login: `admin` / le mot de passe choisi ci-dessus (ne pas utiliser de valeur faible comme "admin123", et ne jamais la committer dans ce fichier)

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

À chaque push sur `main` : les tests PHPUnit sont exécutés, puis l'image Docker est buildée et poussée sur `ghcr.io/badra31/kube-quest-app:<sha-du-commit>` (le build est bloqué si les tests échouent).

Workflow : `.github/workflows/build.yml`

---

## 9. Sécurité — gestion des secrets

### Fourniture des secrets au déploiement

`APP_KEY` (clé de chiffrement Laravel) et le mot de passe PostgreSQL/MySQL **ne sont pas** dans les fichiers versionnés (`values.yaml`, `docker-compose.yaml`). Ils doivent être fournis séparément :

- **Helm** : copier `helm/sample-app/values-secret.example.yaml` en `helm/sample-app/values-secret.yaml` (non versionné), puis :
  ```bash
  helm upgrade --install sample-app . -f values.yaml -f values-secret.yaml --set image.tag=<sha-du-commit>
  ```
- **Docker Compose** : copier `docker-compose.override.example.yml` en `docker-compose.override.yml` (non versionné) — fusionné automatiquement par `docker compose up`.

Générer une nouvelle `APP_KEY` : `php artisan key:generate --show`.

### Incident connu : secrets versionnés dans l'historique Git (résolu)

Dans les tout premiers commits du projet, un mot de passe de base de données et une clé d'application (`APP_KEY`) Laravel avaient été versionnés **en clair** dans `helm/sample-app/values.yaml` et `docker-compose.yaml`. Le dépôt étant public, l'incident a été traité en trois temps :

1. **Détection** : repérée lors d'un audit de sécurité du dépôt, avant un push.
2. **Retrait des fichiers versionnés** : les valeurs ont été retirées des fichiers suivis par Git et remplacées par des placeholders vides, fournis désormais uniquement via des fichiers non versionnés (voir "Fourniture des secrets au déploiement" ci-dessus).
3. **Rotation des secrets** : une nouvelle `APP_KEY` et de nouveaux mots de passe ont été générés — les anciennes valeurs ne sont plus utilisées nulle part, y compris en local.
4. **Purge de l'historique Git** : l'historique complet du dépôt a été réécrit avec BFG Repo-Cleaner pour retirer les anciennes valeurs de tous les commits passés, suivi d'un `push --force`. Toute personne ayant cloné le dépôt avant cette purge doit re-cloner entièrement (un `git pull` échoue sur un historique réécrit).

---

## 10. Sauvegarde et restauration PostgreSQL

### Sauvegarde automatique

Un `CronJob` (`helm/sample-app/templates/backup-cronjob.yaml`) exécute `pg_dump` tous les jours à 2h du matin (configurable via `backup.schedule` dans `values.yaml`) et écrit le dump sur un volume dédié (`backup.storageSize`, 1Gi par défaut). Les dumps de plus de `backup.retentionDays` jours (7 par défaut) sont automatiquement supprimés.

**Limite connue, à assumer à l'oral** : le volume de backup utilise le même `StorageClass` `local-path` que le reste du cluster — il reste lié au nœud physique sur lequel il a été créé. Ça protège contre une erreur applicative (migration ratée, `DROP TABLE` accidentel), **pas** contre la perte de la VM elle-même. Une vraie stratégie de production copierait ces dumps vers S3, ce qui nécessiterait un bucket + un rôle IAM non provisionnés actuellement.

### Déclencher une sauvegarde manuellement

```bash
kubectl create job --from=cronjob/sample-app-backup manual-backup-$(date +%s) -n app
kubectl logs -n app job/manual-backup-<suffixe> -f
```

### Lister les sauvegardes disponibles

```bash
kubectl exec -it -n app deploy/sample-app -- sh -c "ls -la /backup" 2>/dev/null || \
kubectl run -n app --rm -it backup-browser --image=busybox --overrides='{"spec":{"containers":[{"name":"backup-browser","image":"busybox","command":["ls","-la","/backup"],"volumeMounts":[{"name":"backup","mountPath":"/backup"}]}],"volumes":[{"name":"backup","persistentVolumeClaim":{"claimName":"sample-app-backup"}}]}}'
```

### Procédure de restauration (testée avec Docker en local, à rejouer sur le cluster)

La commande `pg_restore` ci-dessous a été validée en local (PostgreSQL 18, conteneur Docker) : donnée créée → `pg_dump` → suppression totale de la table → `pg_restore --clean --if-exists` → donnée bien récupérée. Sur le cluster réel :

```bash
# 1. Copier un dump depuis le volume de backup vers le pod PostgreSQL
kubectl cp -n app <pod-avec-acces-au-volume-backup>:/backup/backup-XXXXXXXX-XXXXXX.dump ./backup.dump
kubectl cp -n app ./backup.dump sample-app-postgresql-0:/tmp/backup.dump

# 2. Restaurer (--clean --if-exists : supprime les objets existants avant de les recréer,
#    évite les conflits si les tables sont déjà présentes)
kubectl exec -it -n app sample-app-postgresql-0 -- \
  pg_restore -U app_user -d app_database --clean --if-exists /tmp/backup.dump

# 3. Vérifier que les données sont bien revenues
kubectl exec -it -n app sample-app-postgresql-0 -- \
  psql -U app_user -d app_database -c "SELECT * FROM counters;"
```
