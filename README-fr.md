# Visual TOM — Chart Helm Kubernetes
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)&nbsp;
[![en](https://img.shields.io/badge/lang-en-red.svg)](README.md)

Ce dépôt fournit un chart Helm pour déployer **Visual TOM (Absyss)** et ses produits associés sur Kubernetes :

- **VTOM** — Ordonnanceur (core)
- **ITC** — Visual TOM User Portal
- **ITM** — Visual IT Messenger
- **MFT** — Visual TOM Managed File Transfer

Cibles validées :

| Environnement | Statut |
|---|---|
| Azure AKS | ✅ Validé |
| GCP GKE (Autopilot) | ✅ Validé |
| AWS EKS | ⚠️ Implémenté, non testé en production |
| On-premise / Minikube | ✅ Testé localement |

# Disclaimer

Ce chart Helm est fourni par Absyss SAS comme un **déploiement de référence** de Visual TOM sur Kubernetes. Il est conçu comme un **point de départ** qui doit être adapté par chaque client à son infrastructure, à ses exigences de sécurité et à ses contraintes opérationnelles (topologie réseau, gestion des secrets, classes de stockage, contrôleur Ingress, politiques RBAC, etc.).

Le chart est distribué **tel quel**, sans garantie d'aucune sorte. Absyss SAS ne peut être tenu responsable des dommages résultant de son utilisation ou des adaptations effectuées par le client.

Les contrats de support Visual TOM standard ne couvrent pas le chart Helm lui-même ni les adaptations Kubernetes côté client. Des jours de consulting peuvent être demandés pour accompagner le déploiement, la personnalisation ou la résolution de problèmes.

# Prérequis

## Tous les environnements
- **Visual TOM** ≥ 7.3.2c (versions inférieures non testées avec ce chart)
- **Kubernetes** ≥ 1.28
- **Helm** ≥ 3.8 (requis pour l'installation depuis le registry OCI)
- **PostgreSQL 17** accessible depuis le cluster (VNet, VPC ou réseau local)
- Un **contrôleur Ingress** installé — **Traefik** est utilisé par défaut, nginx est également supporté
- **cert-manager** installé avec un `ClusterIssuer` configuré si vous utilisez Let's Encrypt (option TLS par défaut). L'installation et la configuration de cert-manager sont à la charge du client — le chart se contente de créer les ressources `Certificate`. Si vous fournissez vos propres certificats TLS (`tls.provider: secret`), cert-manager n'est pas nécessaire
- **ExternalDNS** (optionnel) — pour la gestion automatique des enregistrements DNS du service LoadBalancer. Sans ExternalDNS, les enregistrements DNS doivent être créés manuellement. Voir `vtom.serverService.hostname` dans les values
- Une **licence VTOM** valide et un accès à un registry d'images

> **Accès réseau privé / VPN :** les ressources type WireGuard, Private Endpoint, Cloud SQL Auth Proxy, etc. ne font **pas** partie de ce chart. Elles sont à provisionner en amont via votre IaC (Terraform, Bicep, etc.).

## Prérequis cloud-spécifiques

### Azure (AKS)
- ACR (Azure Container Registry) avec les images VTOM/ITC/ITM/MFT chargées
- Azure Key Vault avec les secrets créés (voir section Azure ci-dessous)
- User-Assigned Managed Identity avec accès Key Vault (`Key Vault Secrets User`)
- External Secrets Operator installé dans le cluster

### AWS (EKS)
- ECR ou autre registry avec les images chargées
- AWS Secrets Manager avec les secrets créés
- IAM Role avec accès Secrets Manager, associé au ServiceAccount via IRSA
- External Secrets Operator installé dans le cluster

### GCP (GKE)
- Artifact Registry ou GCR avec les images chargées
- GCP Secret Manager avec les secrets créés
- GCP Service Account avec accès Secret Manager, lié via Workload Identity
- External Secrets Operator installé dans le cluster
- Cloud SQL Auth Proxy activé dans les valeurs (préconfiguré dans `values-gcp.yaml`)

### On-premise
- Registry Docker local ou images chargées manuellement (`docker load`)
- PostgreSQL accessible depuis les pods
- Secrets Kubernetes créés manuellement (voir section on-premise ci-dessous)

# Produits

Le chart déploie 4 produits Visual TOM, chacun activable indépendamment via son toggle `<produit>.enabled`. Tous se partagent les paramètres globaux (registry, namespace, base de données, exposition réseau, NetworkPolicy).

## VTOM — Ordonnanceur

Le cœur de Visual TOM. Trois composants déployés en pods distincts, partageant la même image.

| Composant | Rôle | Service | PVC | Mémoire (limite) |
|---|---|---|---|---|
| `vtom-server` | Moteur d'ordonnancement | LoadBalancer (5 ports natifs VTOM) | 5 Gi | 1 Gi |
| `vtom-apiserver` | API REST + interface web | ClusterIP + Ingress HTTPS | 2 Gi | 1.5 Gi |
| `vtom-agent` | Exécution des jobs Kubernetes | (aucun) | 10 Gi | 256 Mi |

**Paramètres typiques :**
- `vtom.image.tag` — version VTOM (ex. `7.3.2c`)
- `vtom.ingress.host` — FQDN apiserver, ex. `vtom.mycompany.com`
- `vtom.serverService.hostname` — FQDN client VTOM Desktop (géré par ExternalDNS)
- `vtom.serverService.loadBalancerIP` — IP statique pour survivre aux reprovisions du LB
- `vtom.timezone` — fuseau horaire partagé (défaut `Europe/Paris`)
- `vtom.{server,apiserver,agent}Resources` — CPU/mémoire par composant
- `vtom.{server,apiserver,agent}Pvc.size` — tailles de stockage

**Licence :** `vtom.license.secretName` (défaut `vtom-license-secret`) — partagée avec ITC et ITM par défaut.

**Base :** DB nommée `vtom`, secret `vtom-db-secret` (clés `TOM_SGBD_USER` + `TOM_SGBD_PASSWORD` — mot de passe **chiffré format VTOM**, cf. [Format des secrets](#format-des-secrets)).

**Désactiver :** `vtom.enabled: false` (utile si vous déployez uniquement ITC/ITM/MFT contre un serveur VTOM externe).

## ITC — Visual TOM User Portal

Portail utilisateur web pour piloter VTOM (visualisation, supervision, drag & drop).

| Composant | Rôle | Service | PVC | Mémoire (limite) |
|---|---|---|---|---|
| `itc` | Portail web utilisateur | ClusterIP + Ingress HTTPS | 2 Gi | 1 Gi |

**Paramètres typiques :**
- `itc.image.tag` — version ITC (**requise** si `itc.enabled=true`)
- `itc.ingress.host` — FQDN ITC, ex. `vitc.mycompany.com`
- `itc.resources`, `itc.pvc.size`

**Licence :** par défaut réutilise la licence VTOM (`itc.license.secretName: vtom-license-secret`).

**Base :** DB nommée `ITCockpits`, secret `itc-db-secret` (clés `ITDB_USER` + `ITDB_PASSWORD` — mot de passe **en clair**).

**Désactiver :** `itc.enabled: false`.

## ITM — Visual IT Messenger

Service de messagerie / notification (envoi de courriels, alertes intégrées au workflow VTOM).

| Composant | Rôle | Service | PVC | Mémoire (limite) |
|---|---|---|---|---|
| `itm` | Messenger | ClusterIP + Ingress HTTPS | 2 Gi | 1 Gi |

**Paramètres typiques :**
- `itm.image.tag` — version ITM (**requise** si `itm.enabled=true`)
- `itm.ingress.host` — FQDN ITM, ex. `vitm.mycompany.com`
- `itm.resources`, `itm.pvc.size`

**Licence :** par défaut réutilise la licence VTOM (`itm.license.secretName: vtom-license-secret`).

**Base :** DB nommée `ITMessenger`, secret `itm-db-secret` (clés `ITDB_USER` + `ITDB_PASSWORD` — mot de passe **en clair**).

**Désactiver :** `itm.enabled: false`.

## MFT — Visual TOM Managed File Transfer

Transferts de fichiers managés : serveur SFTP entrant + connecteurs sortants vers backends externes (NFS, S3, Azure Blob, FTP, SFTP). **Pas de base de données ni de licence séparée.**

| Composant | Rôle | Services | PVC | Mémoire (limite) |
|---|---|---|---|---|
| `vtom-mft` | Portail HTTPS + serveur SFTP | `mft` (ClusterIP) + `mft-sftp` (LoadBalancer) + Ingress HTTPS | 1 Gi | 1 Gi |

**Ports exposés :**
- `30034` — portail HTTPS (TLS auto-signé côté pod)
- `30022` — SFTP (accès clients externes via LoadBalancer)

**Paramètres typiques :**
- `mft.image.tag` — version MFT (**requise** si `mft.enabled=true`)
- `mft.ingress.host` — FQDN portail web, ex. `mft.mycompany.com`
- `mft.sftpService.hostname` — FQDN SFTP (géré par ExternalDNS)
- `mft.sftpService.loadBalancerIP` — IP statique du LB SFTP
- `mft.sftpService.loadBalancerSourceRanges` — **toujours renseigner en production** pour restreindre l'accès SFTP par IP
- `mft.externalEgress` — règles NetworkPolicy de sortie vers les backends de stockage (NFS, S3, FTP, SFTP)
- `mft.pvcSeed.enabled` — init container qui prépare la structure du PVC au premier démarrage

**Désactiver :** `mft.enabled: false`.

# Installation

## Depuis le registry public OCI (recommandé)

Le chart est publié en tant qu'artefact OCI sur GitHub Container Registry. Aucune authentification requise.

```bash
helm install visual-tom oci://ghcr.io/absysslab/visual-tom \
  --version 0.1.0 \
  -f values-azure.yaml \
  -f values-monentreprise.yaml \
  --namespace vtom --create-namespace
```

Remplacer `values-azure.yaml` par `values-aws.yaml`, `values-gcp.yaml` ou `values-onpremise.yaml` selon votre cible.

## Depuis les sources

```bash
git clone https://github.com/AbsyssLab/vtom-helm.git
cd vtom-helm

helm install visual-tom ./charts/visual-tom \
  -f ./charts/visual-tom/values-azure.yaml \
  -f values-monentreprise.yaml \
  --namespace vtom --create-namespace
```

# Configuration

## Superposition des fichiers de valeurs

Helm fusionne les fichiers de valeurs dans l'ordre indiqué sur la ligne de commande. Chaque fichier suivant écrase les valeurs du précédent :

```
values.yaml                  (defaults internes, chargé automatiquement)
    +
values-<cloud>.yaml          (remplace les defaults par les valeurs cloud-spécifiques)
    +
values-monentreprise.yaml    (remplace par VOS valeurs spécifiques)
    =
configuration finale déployée
```

## Étapes

1. **Copier** `values-client-template.yaml` → `values-monentreprise.yaml`
2. **Remplir** toutes les lignes marquées `# TODO`
3. **Ne pas modifier** `values.yaml` ni les fichiers `values-<cloud>.yaml`

## Exposition réseau

Par défaut, **tout est privé en production**. Le chart impose un Load Balancer interne pour `vtom.serverService` (VTOM Desktop) et `mft.sftpService` (SFTP) via des annotations spécifiques à chaque cloud, déjà configurées dans les fichiers `values-<cloud>.yaml`.

| Composant | Défaut | Override (public, tests) | Configuré dans |
|---|---|---|---|
| PostgreSQL | Endpoint privé (Private Endpoint, Private IP, VPC peering) | FQDN public | `database.host` — ce chart |
| vtom-server (VTOM Desktop) | LB interne — **imposé par le chart** | LB public | `vtom.serverService.annotations` — ce chart |
| MFT SFTP | LB interne — **imposé par le chart** | LB public | `mft.sftpService.annotations` — ce chart |
| Interfaces web (Ingress) | LB interne — **recommandé côté client** | LB public | Paramètres du contrôleur Ingress — **hors du chart** |

**Annotations LB interne par cloud** (déjà configurées dans `values-<cloud>.yaml`) :

| Cloud | Annotations |
|---|---|
| Azure | `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` |
| AWS | `aws-load-balancer-scheme: "internal"` (+ `aws-load-balancer-type: "external"`, `nlb-target-type: "ip"`) |
| GCP | `networking.gke.io/load-balancer-type: "Internal"` |
| On-premise | aucune (pas de LB cloud) |

**Exposer publiquement (tests uniquement)** — surcharger les annotations dans `values-monentreprise.yaml` :
```yaml
vtom:
  serverService:
    annotations: {}                          # Désactive le LB interne
    loadBalancerSourceRanges:
      - "203.0.113.0/24"                     # Restreindre aux IPs autorisées
```

**Restreindre l'accès au LB interne par IP** (production) :
```yaml
vtom:
  serverService:
    loadBalancerSourceRanges:
      - "10.0.0.0/8"                         # Réseau interne (VNet/VPC + VPN clients)
```

## Format des secrets

Les conventions suivantes s'appliquent à **toutes les infrastructures** (Azure Key Vault, AWS Secrets Manager, GCP Secret Manager, secrets Kubernetes natifs) :

| Produit | Utilisateur DB | Mot de passe DB |
|---|---|---|
| **VTOM** | Texte brut | **Chiffré format VTOM** (bcrypt Absyss) — utiliser l'outil de chiffrement fourni par Absyss |
| **ITC** | Texte brut | **En clair** (ITC ne supporte pas le chiffrement VTOM) |
| **ITM** | Texte brut | **En clair** (ITM ne supporte pas le chiffrement VTOM) |

> **Important :** ne **jamais** stocker le mot de passe VTOM en clair. Le format attendu est le hash bcrypt généré par l'outil Absyss. À l'inverse, les mots de passe ITC et ITM doivent rester en clair — toute tentative de chiffrement entraînera un échec de connexion.

## Configuration par environnement

### Azure (AKS)

**Valeurs obligatoires :**

| Paramètre | Description | Exemple |
|---|---|---|
| `global.imageRegistry` | Nom de l'ACR | `monacr.azurecr.io` |
| `vtom.image.tag` | Version VTOM | `7.3.2c` |
| `itc.image.tag` | Version ITC | `7.3.2c` |
| `itm.image.tag` | Version ITM | `7.3.2c` |
| `vtom.ingress.host` | Domaine VTOM | `vtom.monentreprise.com` |
| `itc.ingress.host` | Domaine ITC | `vitc.monentreprise.com` |
| `itm.ingress.host` | Domaine ITM | `vitm.monentreprise.com` |
| `database.host` | FQDN PostgreSQL | `vtom-pg.postgres.database.azure.com` |
| `secrets.azure.keyVaultUrl` | URL du Key Vault | `https://mon-kv.vault.azure.net` |
| `secrets.azure.tenantId` | ID du tenant Azure AD | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `serviceAccount.azure.clientId` | Client ID de la Managed Identity | `yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy` |

**Secrets à créer dans Azure Key Vault :**

| Nom du secret | Contenu | Format |
|---|---|---|
| `vtom-db-user` | Utilisateur PostgreSQL pour VTOM | Texte brut |
| `vtom-db-password` | Mot de passe VTOM pour PostgreSQL | **Chiffré format VTOM** (bcrypt Absyss) |
| `vtom-license-register` | Contenu du fichier `license.register` | Texte brut |
| `itc-db-user` | Utilisateur PostgreSQL pour ITC | Texte brut |
| `itc-db-password` | Mot de passe ITC pour PostgreSQL | **En clair** |
| `itm-db-user` | Utilisateur PostgreSQL pour ITM | Texte brut |
| `itm-db-password` | Mot de passe ITM pour PostgreSQL | **En clair** |

> **PostgreSQL — privé vs public :** sur Azure, utilisez de préférence un **Private Endpoint** sur le serveur PostgreSQL flexible (FQDN `<server>.private.postgres.database.azure.com`). Le FQDN public Azure (`<server>.postgres.database.azure.com`) ne doit être utilisé qu'en test, avec firewall PostgreSQL restreint à votre VNet.

### AWS (EKS)

**Valeurs obligatoires :**

| Paramètre | Description | Exemple |
|---|---|---|
| `global.imageRegistry` | Registry ECR | `123456789.dkr.ecr.eu-west-1.amazonaws.com` |
| `vtom.image.tag` | Version VTOM | `7.3.2c` |
| `itc.image.tag` | Version ITC | `7.3.2c` |
| `itm.image.tag` | Version ITM | `7.3.2c` |
| `vtom.ingress.host` | Domaine VTOM | `vtom.monentreprise.com` |
| `itc.ingress.host` | Domaine ITC | `vitc.monentreprise.com` |
| `itm.ingress.host` | Domaine ITM | `vitm.monentreprise.com` |
| `database.host` | Endpoint RDS | `vtom.xxxx.eu-west-1.rds.amazonaws.com` |
| `secrets.aws.region` | Région AWS | `eu-west-1` |
| `serviceAccount.aws.roleArn` | ARN du rôle IAM | `arn:aws:iam::123456789012:role/vtom-role` |

**Secrets à créer dans AWS Secrets Manager :**

| Nom du secret | Contenu | Format |
|---|---|---|
| `vtom/db-user` | Utilisateur PostgreSQL pour VTOM | Texte brut |
| `vtom/db-password` | Mot de passe VTOM | **Chiffré format VTOM** |
| `vtom/license-register` | Fichier `license.register` | Texte brut |
| `vtom/itc-db-user` | Utilisateur PostgreSQL pour ITC | Texte brut |
| `vtom/itc-db-password` | Mot de passe ITC | **En clair** |
| `vtom/itm-db-user` | Utilisateur PostgreSQL pour ITM | Texte brut |
| `vtom/itm-db-password` | Mot de passe ITM | **En clair** |

### GCP (GKE)

**Valeurs obligatoires :**

| Paramètre | Description | Exemple |
|---|---|---|
| `global.imageRegistry` | Artifact Registry | `europe-west1-docker.pkg.dev/mon-projet/vtom` |
| `vtom.image.tag` | Version VTOM | `7.3.2c` |
| `itc.image.tag` | Version ITC | `7.3.2c` |
| `itm.image.tag` | Version ITM | `7.3.2c` |
| `vtom.ingress.host` | Domaine VTOM | `vtom.monentreprise.com` |
| `itc.ingress.host` | Domaine ITC | `vitc.monentreprise.com` |
| `itm.ingress.host` | Domaine ITM | `vitm.monentreprise.com` |
| `dbProxy.cloudsqlProxy.instanceConnectionName` | Instance Cloud SQL | `mon-projet:europe-west1:vtom-postgres` |
| `secrets.gcp.projectId` | ID du projet GCP | `mon-projet-gcp` |
| `serviceAccount.gcp.serviceAccount` | GSA liée au KSA | `vtom@mon-projet.iam.gserviceaccount.com` |

**Secrets à créer dans GCP Secret Manager :**

| Nom du secret | Contenu | Format |
|---|---|---|
| `vtom-db-user` | Utilisateur PostgreSQL pour VTOM | Texte brut |
| `vtom-db-password` | Mot de passe VTOM | **Chiffré format VTOM** |
| `vtom-license-register` | Fichier `license.register` | Texte brut |
| `itc-db-user` | Utilisateur PostgreSQL pour ITC | Texte brut |
| `itc-db-password` | Mot de passe ITC | **En clair** |
| `itm-db-user` | Utilisateur PostgreSQL pour ITM | Texte brut |
| `itm-db-password` | Mot de passe ITM | **En clair** |

### On-premise / RKE2 / Minikube

**Valeurs obligatoires :**

| Paramètre | Description | Exemple |
|---|---|---|
| `global.imageRegistry` | Registry local | `registry.monentreprise.com` |
| `vtom.image.tag` | Version VTOM | `7.3.2c` |
| `itc.image.tag` | Version ITC | `7.3.2c` |
| `itm.image.tag` | Version ITM | `7.3.2c` |
| `vtom.ingress.host` | Domaine VTOM | `vtom.monentreprise.local` |
| `itc.ingress.host` | Domaine ITC | `vitc.monentreprise.local` |
| `itm.ingress.host` | Domaine ITM | `vitm.monentreprise.local` |
| `database.host` | Hostname/IP PostgreSQL | `192.168.1.50` |

**Secrets Kubernetes à créer manuellement avant le déploiement :**

```bash
kubectl create namespace vtom

# Utilisateur + mot de passe VTOM (mot de passe CHIFFRÉ au format VTOM — bcrypt Absyss)
kubectl create secret generic vtom-db-secret \
  --from-literal=TOM_SGBD_USER='<utilisateur-postgresql>' \
  --from-literal=TOM_SGBD_PASSWORD='<mot-de-passe-chiffre-vtom>' \
  -n vtom

# Licence VTOM/ITC/ITM (fichier fourni par Absyss)
kubectl create secret generic vtom-license-secret \
  --from-file=license.register=/chemin/vers/license.register \
  -n vtom

# Utilisateur + mot de passe ITC — EN CLAIR
kubectl create secret generic itc-db-secret \
  --from-literal=ITDB_USER='<utilisateur-postgresql>' \
  --from-literal=ITDB_PASSWORD='<mot-de-passe-en-clair>' \
  -n vtom

# Utilisateur + mot de passe ITM — EN CLAIR
kubectl create secret generic itm-db-secret \
  --from-literal=ITDB_USER='<utilisateur-postgresql>' \
  --from-literal=ITDB_PASSWORD='<mot-de-passe-en-clair>' \
  -n vtom
```

## NetworkPolicy — Health checks Load Balancer

Pour que les Load Balancers cloud puissent vérifier la santé des pods (probes), les CIDRs d'origine des probes doivent être explicitement autorisés dans la NetworkPolicy. Configurez `networkPolicy.lbHealthCheckCidrs` selon votre cloud :

| Cloud | Valeur recommandée |
|---|---|
| Azure | `["168.63.129.16/32"]` |
| AWS | CIDR du VPC (ex. `["172.31.0.0/16"]`) — ne **pas** utiliser `["0.0.0.0/0"]` en production |
| GCP | `["130.211.0.0/22", "35.191.0.0/16"]` (Internal LB utilise les deux ranges) |
| On-premise | `[]` (pas de probe cloud) |

Les fichiers `values-<cloud>.yaml` fournissent déjà la bonne valeur par défaut.

# Architecture

![Architecture VTOM sur Kubernetes](architecture.png)

# Mise à jour

```bash
# Via OCI
helm upgrade visual-tom oci://ghcr.io/absysslab/visual-tom \
  --version 0.1.1 \
  -f values-azure.yaml \
  -f values-monentreprise.yaml \
  --namespace vtom

# Depuis les sources
helm upgrade visual-tom ./charts/visual-tom \
  -f ./charts/visual-tom/values-azure.yaml \
  -f values-monentreprise.yaml \
  --namespace vtom
```

# Désinstallation

```bash
helm uninstall visual-tom -n vtom
```

Par défaut, **les PersistentVolumeClaims (PVC) et les PersistentVolumes (PV) sous-jacents sont conservés** (`reclaimPolicy: Retain`). Cela protège vos données (clés de chiffrement, logs, journaux, configuration) contre une suppression accidentelle.

> ⚠️ **AVERTISSEMENT — Perte de données irréversible**
>
> Les commandes ci-dessous suppriment définitivement **toutes les données VTOM, ITC, ITM et MFT**. Sur Azure / AWS / GCP, le disque cloud sous-jacent est également supprimé. **Aucune restauration n'est possible sans sauvegarde préalable**.
>
> N'exécuter qu'après avoir :
> - Effectué un dump complet de PostgreSQL
> - Sauvegardé les fichiers de configuration et journaux des PVC
> - Confirmé que ces données ne sont plus nécessaires

```bash
# 1. Supprimer les PVC (libère les PV qui passent en état "Released")
kubectl delete pvc --all -n vtom

# 2. Supprimer les PV libérés (perte définitive des disques sous-jacents)
kubectl get pv | grep "vtom/" | awk '{print $1}' | xargs -r kubectl delete pv

# 3. (Optionnel) Supprimer le namespace
kubectl delete namespace vtom
```

# Vérification du déploiement

```bash
kubectl get pods -n vtom
kubectl get ingress -n vtom
kubectl get svc -n vtom
helm status visual-tom -n vtom
```

# Résolution de problèmes

**Les pods restent en `Pending` :**
```bash
kubectl describe pod <nom-du-pod> -n vtom
# Vérifier les events — souvent un problème de PVC ou de ressources insuffisantes
```

**Les pods restent en `Init:0/1` ou `Init:Error` :**
```bash
kubectl logs <nom-du-pod> -n vtom -c wait-for-db
# Le proxy DB ne démarre pas ou la DB est inaccessible
```

**Les secrets ESO ne se synchronisent pas :**
```bash
kubectl get externalsecret -n vtom
kubectl describe externalsecret vtom-db-secret -n vtom
# Vérifier les permissions de la Managed Identity / IAM Role / GSA sur le coffre de secrets
```

**Le certificat TLS n'est pas émis :**
```bash
kubectl get certificate -n vtom
kubectl describe certificate vtom-tls-cert -n vtom
# Vérifier que le ClusterIssuer est prêt et que le domaine est accessible depuis internet
```

**Le Load Balancer reste `<pending>` ou les probes échouent :**
```bash
kubectl describe svc vtom-server -n vtom
# Côté NetworkPolicy : vérifier networkPolicy.lbHealthCheckCidrs (cf. section dédiée)
# Côté cloud : vérifier annotations et quotas LB
```

# Licence

Ce projet est sous licence Apache 2.0. Voir le fichier [LICENSE](LICENSE) pour plus de détails.
