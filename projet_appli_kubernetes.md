---
title: Projet déploiement applicatif dans Kubernetes
date: 2024 / 2025
---

## Installation du Cluster

:::exo
1. Mettre en place un petit cluster Kubernetes (1 control plane, 2 à 3 workers). **On ne demande pas de déployer un vrai cluster de production !**
2. En cas d'installation _on-premise_, installer un _Load Balancer_ `MetalLB` via _Helm_.
3. Installer un `IngressController`, par exemple `traefik` ou `ingress-nginx` via _Helm_.
:::

:::link
- Pour plus d'information sur le déploiement d'un cluster Kubernetes, voir le projet dédié : <https://www.avenel.pro/cours/docker/projet_install_kubernetes>
- Voir aussi la page <https://www.avenel.pro/cours/docker/kubernetes-cheatsheet> pour l'installation des dépendances.
:::

### Installation des StorageClass

En s'aidant de la [cheatsheet Kubernetes](/cours/docker/kubernetes-cheatsheet), installer :

- Le [NFS CSI driver for Kubernetes](https://github.com/kubernetes-csi/csi-driver-nfs) pour créer automatiquement des `PersistentVolume` depuis un serveur _NFS_
- Le [local-path-provisionner de Rancher](https://github.com/rancher/local-path-provisioner) pour créer automatiquement des `PersistentVolume` basés sur `hostPath` (répertoires locaux aux _Node_ : perte du _Node_ = perte de la donnée !).

:::tip
Pourquoi avoir besoin d'une `StorageClass` générant des `PV` locaux ?

Beaucoup d'opérateurs créent des `StatefulSets` adaptées à la production : ceux-ci instancient des `PersistentVolumeClaim` pour référencer des `PV`, ce qui permet de générer dynamiquement des volumes depuis du storage (en principe distribué). Le `local-path-provisionner` permet de simuler cet usage en utilisant du storage local (et donc **peu adapté à la production !**)
:::

:::tip
Pour installer un serveur NFS simple on pourra utiliser une VM Ubuntu :

```sh
#!/usr/bin/env bash

# Installation et configuration d'un serveur NFS (dans une VM)
sudo apt install -y nfs-server
sudo mkdir -p /data
sudo /bin/sh -c 'echo "/data *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'
sudo systemctl restart nfs-kernel-server
## check
sudo exportfs
# /data           <world>
```
:::

Vérifier la bonne installation des `StorageClass` :

```console
$ kubectl get storageclasses.storage.k8s.io
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  26h
nfs-csi                nfs.csi.k8s.io          Delete          Immediate              true                   8m29s
```

## Déploiement de l'application

Une fois le cluster installé, nous allons y déployer une application réalisée par vos soins. Cette application doit être multi-composants (frontend, backend, …) et utiliser une base de données.
On recommande l'utilisation de fichiers de manifeste `yml` pour créer les ressources Kubernetes.

:::exo
1. Créer des images Docker pour votre application puis _pusher_ ces images sur un dépôt public (docker hub, ghcr.io, etc) ou privé.
2. Mettre en place une base de données **répliquée** en utilisant un `Operator` déployé par _Helm_, par exemple `mariadb-galera` pour _MariaDB_ / _MySQL_, et [Zalando Postgres Operator](https://github.com/zalando/postgres-operator) pour _Postgresql_
3. Déployer votre application dans le cluster **avec réplication**. : `Deployment`, `Service`, `ConfigMaps` et `Secrets`.
4. Exposer votre application à l'extérieur via un ingress (`traefik` ou `ingress-nginx`) ou un `LoadBalancer` dédié à l'application.
5. Réfléchir à la *Scalabilité* et la **tolérance aux pannes** :
  - Mise à jour du `Deployment` de votre application
  - Autoscaling avec `Horizontal Pod Autoscaler`
  - Limitation de ressources
  - Droits du cluster
6. Ajouter un certificat TLS (autosigné s'il n'est pas possible de le générer via _Let's Encrypt_) grâce à `certmanager` déployé via `Helm`
:::

:::tip
On testera la partie H/A du déploiement applicatif :

- Tester la suppression d'un conteneur / Pod
- Tester la déconnexion d'un _worker node_
- Vérifier la réconciliation des ressources
- Vérifier le _scaling_ automatique en cas de pic de charge : 
:::

## Supervision

Le monitoring d'un cluster `Kubernetes` avec `Prometheus` pour la collecte des métriques et `Grafana` pour leur visualisation est une solution courante pour collecter, stocker et visualiser les métriques du cluster, des pods et des applications. Nous allons mettre en place cette infrastructure de monitoring.

:::exo
- Mettre en place la supervision du cluster via `kube-prometheus-stack` (_Prometheus_ + _Grafana_) déployé via _Helm_ 
- Exposer l'accès à _Grafana_ à l'extérieur du cluster via un _ingress_ : `ingress-nginx`
:::

:::link
Se référer au TP sur Prometheus et Grafana : <https://www.avenel.pro/cours/docker/tp_prometheus_grafana_k8s>
:::

## Bonus

Quelques bonus après avoir réalisé les parties précédentes :

:::exo
1. Créer une chart _Helm_ spécifique à votre application pour déployer toute la stack automatiquement.
2. Configurer l'`Ingress` pour permettre un modèle de déploiement de type _A/B testing_.
3. Utiliser `Flagger` pour des modèles de déploiement plus complexes.
4. Ajouter des politiques de sécurité grâce à `Kyverno`.
:::

