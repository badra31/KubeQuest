# Changelog

Format librement inspiré de [Keep a Changelog](https://keepachangelog.com/),
adapté par thème plutôt que par version — ce projet n'a pas encore de
releases versionnées (pas de tags Git). Chaque entrée référence le hash de
commit court et sa date.

## [Unreleased]

### Sécurité

- Fourniture des secrets (`APP_KEY`, mot de passe PostgreSQL/MySQL) via des
  fichiers non versionnés (`values-secret.yaml`, `docker-compose.override.yml`)
  au lieu de valeurs en clair dans les fichiers suivis par Git (`2de948e`, 2026-08-16)
- Documentation de l'incident et de sa remédiation (`d9e29cd`, 2026-08-16 ;
  réécrite sans valeurs littérales dans `291a763`, 2026-08-17)
- Historique Git complet purgé (BFG Repo-Cleaner) pour retirer les anciennes
  valeurs de secrets de tous les commits passés, suivi d'un `push --force`
  (2026-08-17, opération de réécriture d'historique, non rattachée à un
  commit unique par nature)
- Restriction de la configuration CORS à l'origine de l'application au lieu
  de `*` sur origines/méthodes/headers (`922d436`, 2026-08-16)
- Activation de Dependabot sur composer, npm, github-actions et docker
  (`27f1409`, 2026-08-16)
- Remplacement du `ClusterRoleBinding` `cluster-admin` du dashboard
  Kubernetes par le rôle intégré `view` (lecture seule, exclut nativement
  les Secrets et objets RBAC) (`b42edec`, 2026-08-16)
- `ServiceAccount` dédié pour le pod applicatif, sans Role/RoleBinding
  attribué et `automountServiceAccountToken: false` (`9ac3aae`, 2026-08-16)
- Ajout de `NetworkPolicy` (deny-all par défaut + exceptions explicites
  app→PostgreSQL, ingress→app) (`420def1`, 2026-08-16)
- Durcissement du `securityContext` des pods (non-root, filesystem en
  lecture seule, `allowPrivilegeEscalation: false`, capabilities Linux
  réduites au strict nécessaire) (`29711e5`, 2026-08-16)
- Retrait du mot de passe Grafana en clair (`admin123`) du README
  (`c20f409`, 2026-08-17)
- Remplacement du tag d'image Docker `latest` par le SHA du commit, pour la
  traçabilité et un rollback Helm fiable (`c201903`, 2026-08-16)

### Sauvegarde PostgreSQL

- Ajout d'un `CronJob` `pg_dump` planifié, d'un volume de sauvegarde dédié
  et de la procédure de restauration (validée en local avant écriture du
  manifeste) (`b185dca`, 2026-08-17)

### Cluster / Helm

- Mise en place initiale du projet : application Laravel + orchestration
  locale Docker Compose (`5c3bea2`, 2026-05-07)
- Ajout du chart Helm de l'application et du workflow CI GitHub Actions
  (`21f4816`, 2026-05-15)
- Exécution des migrations Laravel via un `initContainer` et probes
  configurables (`0294e99`, 2026-05-26)
- Activation des probes liveness/readiness (`b946dc1`, 2026-05-27)
- Ajout du `HorizontalPodAutoscaler` (autoscaling CPU) (`ab7dcc8`, 2026-05-28)
- Ajustement du HPA (3 replicas max) et ajout de `timeoutSeconds`/
  `failureThreshold` sur les probes (`324d428`, 2026-08-16)

### Infrastructure Terraform

- Montée en version des nœuds Kubernetes vers `t3.small`, activation
  d'IMDSv2 et AMI dynamique (`627cb6e`, 2026-05-15)

### CI/CD

- Mise en place du workflow GitHub Actions (build + push de l'image),
  avec permissions explicites et versions d'actions à jour (`21f4816`,
  `9e0bcab`, 2026-05-15)
- Ajout d'un job de tests PHPUnit exécuté avant le build, bloquant le push
  d'image en cas d'échec (`d1b485b`, 2026-08-16)

### Documentation & conformité

- Ajout du fichier `LICENSE` (MIT) (`d1b485b`, 2026-08-16)
