---
title: Cheatsheet Kubernetes®
---

# Cheatsheet Kubernetes

:::link
- Voir aussi : [kubectl de A à Z (Stéphane Robert)](https://blog.stephane-robert.info/docs/conteneurs/orchestrateurs/outils/kubectl/)
- Liens utiles : <https://kubernetes.io/docs/tasks/debug/debug-cluster/> et <https://kubernetes.io/docs/tasks/debug/debug-application/>
:::

## Administration

### Versions

#### API Server

```sh
# Renvoie la version d'une instance APIServer
kubectl version
```

:::warn
Un cluster H/A peut avoir des `APIServer` de versions différentes (résultat aléatoire) !
:::

#### Kubelet

```sh
kubectl get nodes -o wide
```

#### Control-plane dans un Pod

```sh
kubectl --namespace=kube-system get pods -o json \
        | jq -r '
          .items[]
          | [.spec.nodeName, .metadata.name]
            + 
            (.spec.containers[].image | split(":"))
          | @tsv
          ' \
        | column -t
```

### Administration etcd

#### Afficher le pod etcd

```sh
kubectl describe pod etcd-cluster-1-control-plane -n kube-system
[…]
# Recopier et passer les propriétés suivantes comme arguments aux commandes `etcdctl` :
--cert-file=/etc/kubernetes/pki/etcd/server.crt
--key-file=/etc/kubernetes/pki/etcd/server.key
--trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt

# administration du cluster etcd par le réseau : `etcdctl`
etcdctl --endpoints 172.18.0.4:2379,172.18.0.5:2379,172.18.0.6:2379 --cert-file=/etc/kubernetes/pki/etcd/server.crt --key-file=/etc/kubernetes/pki/etcd/server.key --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt …
# administration du noeud etcd local : `etcdutl`
```

#### Afficher les noeuds du cluster

```sh
etcdctl […] member list --write-out=table
+------------------+---------+--------------------------+-------------------------+-------------------------+
|        ID        | STATUS  |           NAME           |       PEER ADDRS        |      CLIENT ADDRS       |
+------------------+---------+--------------------------+-------------------------+-------------------------+
| 26aead55408e4ad0 | started | cluster-1-control-plane2 | https://172.18.0.5:2380 | https://172.18.0.5:2379 |
| 5320353a7d98bdee | started | cluster-1-control-plane  | https://172.18.0.4:2380 | https://172.18.0.4:2379 |
| 983acdc6eb33276f | started | cluster-1-control-plane3 | https://172.18.0.6:2380 | https://172.18.0.6:2379 |
+------------------+---------+--------------------------+-------------------------+-------------------------+

# Afficher le leader
etcdctl […] endpoint status --write-out=table
# Transférer le leader
etcdctl […] move-leader <leader ID>
```

#### Snapshot / restauration de l'état du cluster

```sh
etcdctl […] snapshot save /tmp/snapshot-etcd-1.db

# Vérification du snapshot
etcdutl --write-out=table snapshot status /tmp/snapshot-etcd-1.db

# Voir TP installation de Kubernetes pour la procédure de restauration 
```

#### Gestion clé/valeur etcd

```sh
etcdctl […] put cle valeur
etcdctl […] get cle [-w json] | base64 -d
etcdctl […] get --prefix cle_commencant_par… 
etcdctl […] del cle
etcdctl […] watch cle # scrute les changemens de `cle`
```

### Ajouter la completion de commandes dans le shell

```sh
# Pour Bash, à ajouter par exemple dans ~/.bashrc
source <(kubectl completion bash)
# Pour ZSH, à ajouter par exemple dans ~/.zshrc
source <(kubectl completion zsh)

# Idem pour kubectl, helm, k3s, kind, talosctl, minikube, … :
source <(helm completion zsh)
```

:::link
[Exemple de configuration des lignes de commandes : kubectl, helm, …](https://git.sr.ht/~toma/dotfiles/tree/main/item/.config/zsh/k8s.sh)
:::

### Lister les types de ressources supportées

```sh
kubectl api-resources -o wide
kubectl get crds # Custom Resource Definition
kubectl explain [--recursive] RESOURCE_NAME # documentation
```

### Vérifier la présence d'un composant k8s

```sh
kubectl get apiservices | grep metrics-server
```

### Sortir un noeud du cluster

```sh
# Retirer les pods et déconnecter le noeud pour maintenance
kubectl drain --ignore-daemonsets "<node-name>"
# Rendre le noeud de nouveau disponible
kubectl uncordon "<node-name>" 
```

:::warn
Attention aux pré-requis avant d'arrêter un _Node_ : `PodDisruptionBudget`, … (voir cours)
:::

## Généralités

### dry-run : simule la commande sans modification du cluster

```sh
kubectl … --dry-run
```

### Sorties `yaml` ou `json` et sélecteur `jsonpath`

```sh
kubectl -o yaml …
kubectl -o json …
kubectl -o jsonpath='{.items[0].metadata.name}' …
```

### Créer un template de fichier de ressource en Yaml

```sh
kubectl create … -o yaml > mon_fichier.yml
```

### Gérer le contexte

```sh
kubectl config get-contexts

kubectl config use-context …
```

Les contextes sont gérés dans le fichier `~/.kube/config`

### Accéder aux ressources à distance (débug uniquement)

#### kubectl proxy

Permet d'obtenir un proxy vers les ressources HTTP. Les Service / Pod peuvent être accédés depuis le proxy en utilisant une URL : `/api/v1/namespaces/<namespace>/services/<service>/proxy/<ma_requete>`

```sh
kubectl proxy # Démarre le Proxy
curl localhost:8001/api/v1/namespaces/default/services/web-svc/proxy/index.html # accède à http://web-svc/index.html
curl localhost:8001 # accès direct à l'API Server
curl http://localhost:8001/openapi/v2 # Accès à l'OpenAPI (SwaggerUI) de l'API Server Kubernetes
```

#### Port-Forward

Permet d'obtenir un proxy TCP : `kubectl port-forward service/<nom_du_service> <local_port>:<remote_port>`

```sh
kubectl port-forward svc/redis 10000:6379
```

### Monitoring

```sh
kubectl top nodes
kubectl top pods
```

### Créer une ressource (pod, service, ...)

```sh
kubectl apply -f monFichier.yml
```

### Lister les ressources créés (pod, service, storage, ...)

```sh
kubectl get deployments,svc,endpoints,pods,pv,pvc,nodes [--all-namespaces]
```

### Inspecter des ressources

```sh
kubectl describe deployment myapp1

kubectl describe po/mon-pod

kubectl describe svc myapp1-sv
```

### Nettoyer les Pod en échec

```sh
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

## Ressources

### Lister les conteneurs d'un pod (i.e. namespace==default)

```sh
kubectl describe po/mon-pod -n default
```

### Exposer un Pod (créer un service)

```sh
kubectl expose deployment/kubernetes-bootcamp --type="NodePort" --port 8080
```

### kubectl exec : exécuter une commande dans un pod déjà en activité

```sh
kubectl exec -it MON_POD -c MON_CONTENEUR -- MA_COMMANDE
```

### kubectl debug démarrer un nouveau conteneur dans un Pod pour du débug

```sh
kubectl debug mypod -it --image=busybox
kubectl debug mypod -it --image=paulbouwer/hello-kubernetes:1.8
```

:::link
Voir aussi : 

- La documentation : <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_debug/#examples>
- Une image Docker utile pour du debug : <https://github.com/jpetazzo/shpod>
- Une autre image utile : <https://github.com/kubernetes-up-and-running/kuard>
:::

### kubectl attach : s'attacher à la sortie du PID=1 (commande de lancement du conteneur)

```sh
kubectl attach MON_POD
```

### Gestion des labels

```sh
kubectl label MA_RESSOURCE MON_LABEL=MA_VALEUR
kubectl label MA_RESSOURCE MON_LABEL- # supprime le label
```

### Namespace

```sh
kubectl create namespace MON_NAMESPACE
kubectl get namespaces
kubectl config set-context minikube --namespace=MON_NAMESPACE [--cluster=…]
```

### ConfigMap

```sh
# Créer un ConfigMap depuis un fichier de conf existant
kubectl create configmap ma-conf --from-file=mon_fichier.conf

# Créer un ConfigMap depuis un fichier d'environnement (clé=valeur) existant
kubectl create configmap ma-conf-env --from-env-file=mon_fichier.env
```

### (Auto)scaling

```sh
# Voir fichier de déploiement

# Scaling manuel
kubectl scale deployment php-apache --replicas=3

# Scaling automatique
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10

kubectl get hpa
```

### Rollout

```sh
kubectl rollout status deployment my-app
kubectl rollout history deployment my-app [--revision=2]
kubectl rollout undo deployment my-app [--to-revision=2]
kubectl rollout pause/resume deployment my-app
kubectl rollout restart deployment my-app-deployment # recrée les pods
```

## Structure d'un fichier k8s

```yaml
apiVersion: v1 # Version de l'APIServer k8s
kind: … # Le type de ressource à gérer : Pod, Deployment, Service, …
metadata: # Métadatas de la ressource
  name: … # nom (interne) de la ressource à créer et/ou monitorer
  namespace: mon-namespace # Namespace spécial (optionnel - sinon default)
  labels: # ajout de labels (optionnel)
    ma-cle: ma-valeur 
  […]
spec: # Les spécifications de la ressource. Différent pour chaque type de ressource
  […]
```

## Pod

### Exemple minimal de fichier de description d'un Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: webapp # nom du Pod
spec:
  containers:
  - name: front-end # nom du conteneur
    image: nginx # image Docker
    ports:
    - containerPort: 80 # port dans le conteneur
```

### Exemple avancé de fichier de description d'un Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: webapp # nom du Pod
  labels:
    app: web # optionnel - pour utiliser un service
  namespace: mon-namespace # optionnel - dans un namespace dédié
spec:
  containers:
  - name: main-container # nom du conteneur
    image: nginx # image Docker
    imagePullPolicy: Always # re-pull la dernière version d'image à la (re)création du Pod
    command: ["printenv"] # The command to start the container
    args: ["HOSTNAME", "KUBERNETES_PORT"] # args for the command
    restartPolicy: Always # restart toujours si stoppé
    restartPolicy: OnFailure # restart seulement si erreur
    restartPolicy: Never
    env: # Variables d'environnement à injecter dans le conteneur
    - name: MA_VAR # variable $MA_VAR
      value: "42" # MA_VAR=42 ⚠️ une string (échapper nombres, …)
    - name: LOG_LEVEL # variable $LOG_LEVEL
      valueFrom: # récupération de la valeur de $LOG_LEVEL à injecter
        configMapKeyRef: #env de type ConfigMap (`ma-config-map-env` déjà créée avec `log_level=…`)
          name: ma-config-map-env # où récupérer la valeur ?
          key: log_level # la valeur de $LOG_LEVEL à injecter
    - name: MY_POD_NAMESPACE # récupération de valeurs de l'API
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace # https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/
    ports: # Ports à exposer
    - containerPort: 80 # port dans le conteneur
    resources:
      requests: # ressources minimum
        memory: 50Mi
        cpu: 0.2
      limits: # ressources maximum
        memory: 250Mi
        cpu: 0.5
    readinessProbe: # check du démarrage
      httpGet:
        path: /monitor/status
        port: 8080
        scheme: HTTPS
      initialDelaySeconds: 2
      periodSeconds: 1
    livenessProbe: # check pendant fonctionnement (healthcheck)
      httpGet:
        path: /monitor/status
        port: 8080
        scheme: HTTPS
      initialDelaySeconds: 20
      periodSeconds: 10
    securityContext:
      readOnlyRootFilesystem: true
    volumeMounts: # montage de volume
    - name: mon-volume # on monte une configuration de volume appelée 'mon-volume'
      mountPath: "/mon/montage/dans/le/conteneur" # point de montage à l'intérieur du conteneur
    - name: log-volume
      mountPath: "/log"
    - name: tmpfs-volume
      mountPath: "/tmp"
  - name: sidecar-container
    image: busybox
    command: ["sh", "-c", "tail -f /logs/app.log"]
    volumeMounts:
    - name: log-volume
      mountPath: "/log"
  initContainers:
  - name: wait-for-myservice
    image: busybox:1.28
    command: ['sh', '-c', "until nslookup myservice.$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace).svc.cluster.local; do echo waiting for myservice; sleep 2; done"]
  volumes:
  - name: mon-volume # le nom de la configuration de volume à utiliser
    configMap: #volume de type ConfigMap (`ma-config-map` déjà créée)
      name: ma-config-map # où récupérer la configuration ?
  - name: log-volume
    emptyDir: {}
  - name: tmpfs-volume
    emptyDir:
      medium: "Memory"
  affinity: # Affinité : Pod / Node
    nodeAffinity: # Affinité de Node
      # [1] affinité "hard" : requis sinon échec
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: environment
                operator: In
                values:
                  - production
      # ou [2] affinité "soft" : si possible sinon non respecté
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 1
          preference:
            matchExpressions:
              - key: environment
                operator: In
                values:
                  - production
    podAffinity: # Affinité de Pod (ou `podAntiAffinity`)
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              cle: valeur # label à matcher
          topologyKey: "kubernetes.io/hostname"
```

Pour un `podAffinity`, le champ `topologyKey` spécifie la "topologie" sur laquelle vous voulez appliquer l'affinité. Ici, `kubernetes.io/hostname` signifie que les pods doivent être planifiés sur le même nœud (identifié par le nom d'hôte). Autres exemples : `topology.kubernetes.io/zone` pour contraindre les pods à être répartis sur plusieurs zones de disponibilité (si le cluster est multi-zone, comme dans les environnements cloud) ou `topology.kubernetes.io/region` pour répartir les pods dans différentes régions géographiques (pour les clusters multi-régions).

:::link
Voir aussi : <https://blog.stephane-robert.info/docs/conteneurs/orchestrateurs/kubernetes/affinity-toleration-taint/>
:::

### Priorité, réquisition et limitation de ressources

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: test
    image: alpine
    priority: 0 # schédulé en dernier
    resources:
      requests: # ressources minimum
        memory: 50Mi
        cpu: 0.2
      limits: # ressources maximum
        memory: 250Mi
        cpu: 0.5
```

Pour récupérer la classe de QoS :

```sh
kubectl get pod <POD_NAME> -o jsonpath='{ .status.qosClass}{"\n"}'
```

#### Qualité de Service (QoS)

Les définition de `resources requests` et `resources limits` permettent de gérer de la QoS dans Kubernetes.

Il existe 3 classes de QoS :

- `Guaranteed` : tous les conteneurs du Pod doivent définir des `resource` `requests` (`memory`, `cpu`) et les mêmes valeurs en `limits`.
  - Ressources garanties en permanence pour le pod.
  - Prioritaires pour l'accès aux ressources et derniers à être évincés en cas de pression sur les ressources.
- sinon : `Burstable` : au moins 1 conteneur du Pod a une `resource request` ou `limit`
  - Garantie minimale de ressources définie par leurs demandes.
  - Peuvent utiliser plus de ressources que leur demande si elles sont disponibles sur le nœud.
  - Évincés après les pods `BestEffort` mais avant les pods `Guaranteed`.
- sinon : `BestEffort`: priorité la plus basse, ressources allouées en fonction de leur disponibilité.
  - Aucune garantie de ressources.
  - Premiers à être évincés.

##### Exemple de QoS Guaranteed

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: test
    image: alpine
    resources:
      requests: # ressources minimum
        memory: 250Mi
        cpu: 0.5
      limits: # ressources maximum
        memory: 250Mi
        cpu: 0.5
```

##### Exemple de QoS Burstable

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: test
    image: alpine
    resources:
      requests: # ressources minimum
        memory: 50Mi
      limits: # ressources maximum
        memory: 250Mi
```

##### Exemple de QoS BestEffort

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: test
    image: alpine
```

### Priorité, Tolerations et Terminaison d'un Pod

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: test
    image: alpine
    terminationGracePeriodSeconds: 60 # shutdown timeout before kill
    # Logs écrits à la destruction d'un Pod
    terminationMessagePath: /dev/termination-log # défaut
    terminationMessagePolicy: File # défaut
    terminationMessagePolicy: FallbackToLogsOnError # utilise les logs du Pod
    # Tolerations
    tolerations:
    - effect: NoExecute
      key: node.kubernetes.io/not-ready # Node : not ready
      key: node.kubernetes.io/unreachable # Node : unreachable
      operator: Exists
      tolerationSeconds: 300 # Le Pod peut rester 300s sur un Node "NotReady" ou "Unreachable"
```

Voir aussi :

- <https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/>
- <https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/>
- <https://kubernetes.io/docs/concepts/scheduling-eviction/>
- <https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/>
- <https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/>
- <https://medium.com/@prateek.malhotra004/demystifying-taint-and-toleration-in-kubernetes-controlling-the-pod-placement-with-precision-d4549c411c67>

## LimitRange & ResourceQuota

Des `LimitRange` peuvent gérer des limitations par défaut par `Namespace`, appliquées à la création d'un `Pod` (elles sont cumulatives) :

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: limitrange-example
spec:
  limits:
  - type: Container # seul type pour l'instant
    min:
      cpu: "100m"
    max:
      cpu: "2000m"
      memory: "1Gi"
    default:
      cpu: "500m"
      memory: "250Mi"
    defaultRequest:
      cpu: "500m"
```

Des `ResourceQuota` peuvent aussi limiter les ressources par défaut dans un `Namespace` (le plus strict s'applique) :

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota-requests-limits
spec:
  hard: # ~soft quota does not exist~
    requests.cpu: "10"
    requests.memory: 10Gi
    limits.cpu: "20"
    limits.memory: 20Gi
```

Un `ResourceQuota` peut aussi limiter le nombre d'objets pouvant être créés dans le Namespace :

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota-for-objects
spec:
  hard: # ~soft quota does not exist~
    pods: 100
    services: 10
    secrets: 10
    configmaps: 10
    persistentvolumeclaims: 20
    services.nodeports: 0
    services.loadbalancers: 0
    count/roles.rbac.authorization.k8s.io: 10
```

```sh
kubectl describe resourcequota my-resource-quota
```

## Stockage k8s

### Exemple de montage d'un volume hostPath

```yaml
apiVersion: v1
kind: Pod
[…]
spec:
  containers:
  - name: front-end # nom du conteneur
    image: nginx # image Docker
    volumeMounts: # montage de volume
    - name: mon-volume # on monte une configuration de volume appelée 'mon-volume'
      mountPath: "/mon/montage/dans/le/conteneur" # point de montage à l'intérieur du conteneur
  volumes:
  - name: mon-volume # le nom de la configuration de volume à utiliser
    hostPath:
      path: /data/nginx # Chemin sur le nœud hôte
      type: DirectoryOrCreate # Type de volume
```

Valeurs possible de `type` de `hostPath` : `DirectoryOrCreate`, `Directory`, `FileOrCreate`, `File`, `Socket`, `CharDevice`, `BlockDevice`

### Exemple de montage d'un volume Cloud AWS EBS

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-using-my-ebs-volume
spec:
  containers:
  - image: ...
    name: container-using-my-ebs-volume
    volumeMounts:
    - mountPath: /my-ebs
      name: my-ebs-volume
  volumes:
  - name: my-ebs-volume
    awsElasticBlockStore:
      volumeID: vol-049df61146c4d7901
      fsType: ext4
```

### Exemple de montage d'un volume NFS

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-using-my-nfs-volume
spec:
  containers:
  - image: ...
    name: container-using-my-nfs-volume
    volumeMounts:
    - mountPath: /my-nfs
      name: my-nfs-volume
  volumes:
  - name: my-nfs-volume
    nfs:
      server: 192.168.0.55
      path: "/exports/assets"
```

### Exemple de PersistantVolume

```yaml
apiVersion: v1
kind: PersistentVolume
spec:
  capacity:
    storage: 1Gi  # Capacité du volume
  accessModes:
    - ReadWriteOnce  # Seul un pod peut monter ce volume en lecture/écriture à la fois
  hostPath:
    path: "/mnt/data"  # Chemin sur le Node où les données seront stockées
```

### Exemple de PersistanceVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
spec:
  accessModes:
    - ReadWriteOnce  # Mode d'accès similaire à celui du PV
  resources:
    requests:
      storage: 500Mi  # La quantité de stockage demandée par ce PVC
```

### Exemple de StorageClass NFS

```sh
# Pré-requis : Installation du driver CSI pour NFS
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace nfs --create-namespace --version v4.10.0
```

```yml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io # Nom du CSI
parameters:
  server: 192.168.20.121 # Remplacer par l'adresse IP du serveur NFS
  share: /data
reclaimPolicy: Delete # Kubernetes supprime automatiquement le volume.
reclaimPolicy: Retain # Le volume doit être supprimé manuellement
volumeBindingMode: Immediate # volume créé dès la demande
volumeBindingMode: WaitForFirstConsumer # volume créé uniquement quand un Pod l'utilise
allowVolumeExpansion: true # agrandir le volume après création ?
mountOptions:
  - nfsvers=4.1
```

```yml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-deployment-nfs
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: nfs-csi # StorageClass NFS définie précédemment
```

### Exemple de StorageClass LocalPathProvisionner

Permet d'utiliser dynamiquement le storage local des _Node_ avec des `PVC` utilisant une `storageClassName: local-path`.

```sh
# Installation du provisionner dans le cluster
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Test d'utilisation
kubectl create -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/examples/pvc/pvc.yaml
kubectl create -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/examples/pod/pod.yaml
```

Pour changer le type de `Volume` (`local` vs `hostPath`) à utiliser :

- par `PVC` :

```yaml
annotations:
  volumeType: <local or hostPath>
```

- global à la `StorageClass` :

```yaml
annotations:
  defaultVolumeType: <local or hostPath>
```


### Changer de StorageClass par défaut

```console
$ kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true

$ kubectl get storageclasses
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  26h
```


### Debug du storage

Les erreurs liées aux volumes sont souvent enregistrées dans les événements Kubernetes :

```sh
kubectl get events --sort-by=.metadata.creationTimestamp
```

:::tip
Un `PV` en état `Released` ou `Failed` ne peut plus être réutilisé.
:::

:::tip
En cas d'erreur de montage d'un volume, tester directement le montage dans le _Pod_ :

```sh
mount -t nfs "<NFS_SERVER_ADDRESS>:<NFS_SHARE_PATH>" /mnt
```
:::

## Network k8s

### Exemple de fichier de ClusterIP

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-clusterip-service
  labels:
    app: my-app
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
    - port: 80          # Port interne exposé par le service
      targetPort: 8080   # Port interne sur lequel le conteneur écoute
```

:::tip
- Pour accéder au service : <http://my-clusterip-service> (même namespace) ou <http://my-clusterip-service.nom-du-namespace.svc.cluster.local>
- Pour récupérer la Virtual IP du service : `kubectl get svc httpenv -o go-template --template '{{ .spec.clusterIP }}'`
:::

### Exemple de fichier de NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-nodeport-service
  labels:
    app: my-app
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
    - port: 8080      # Port interne exposé par le service
      targetPort: 80  # Port sur lequel le conteneur écoute
      nodePort: 30007 # Port sur lequel le service sera accessible depuis l'extérieur du cluster (facultatif)
```

`nodePort` est facultatif : Kubernetes définiera un port aléatoire si cet attribut n'est pas renseigné. Assurez-vous que le port `NodePort` choisi est dans la plage autorisée par votre configuration Kubernetes (généralement entre 30000 et 32767).

### Exemple de fichier LoadBalancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-nodeport-service
  labels:
    app: my-app
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 8080      # Port interne exposé par le service
      targetPort: 80  # Port sur lequel le conteneur écoute
      nodePort: 30007 # Port sur lequel le service sera accessible depuis l'extérieur du cluster (facultatif)
```

#### MetalLB

Un `LoadBalancer` recquiert une implémentation de LB, souvent fournie par un provider Cloud. En l'absence de LB (bare-metal, …) on pourra installer `MetalLB` :

```sh
# Pré-requis : installation de MetalLB
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb
# Ou :
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.11/config/manifests/metallb-native.yaml
```

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool # Pool d'adresses utilisables par le LB
metadata:
  name: first-pool
  # namespace: metallb-system # ! Dans le même namespace que metallb !
spec:
  addresses:
    - 172.18.0.220-172.18.0.250 # définir des adresses utilisables
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement # advertissement du pool d'adresses en L2 (le plus simple)
metadata:
  name: example
  # namespace: metallb-system # ! Dans le même namespace que metallb !
spec:
  ipAddressPools:
    - first-pool
```

### Exemple de fichier ExternalName

```yaml
apiVersion: v1
kind: Service
metadata:
 name: my-external-name-service
spec:
 type: ExternalName
 externalName: google.com
```

```console
$ ping my-external-name-service
64 bytes from 216.58.205.206: seq=0 ttl=42 time=9.765 ms
```

### DNS spécifique

Par défaut, un Pod utilise le DNS de Kubernetes.

Pour une configuration plus poussée, voir : <https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/>

### Ingress

```sh
# Pré-requis : installation de l'Ingress Controller Nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx
# Ou directement :
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/cloud/deploy.yaml

# Pour Traefik :
helm install traefik traefik --namespace=traefik --create-namespace --repo https://traefik.github.io/charts
```

:::link
Voir aussi :

- <https://github.com/traefik/traefik-helm-chart/blob/master/EXAMPLES.md>
- <https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml>
- <https://kubernetes.github.io/ingress-nginx/deploy/#quick-start>
- [Ingress entre différentes namespace](https://tech.aabouzaid.com/2022/08/2-ways-to-route-ingress-traffic-across-namespaces.html)
- Exemples de déploiements Canary avec Ingress [Nginx](https://kubernetes.github.io/ingress-nginx/examples/canary/) ou [Traefik](https://2021-05-enix.container.training/2.yml.html#658)
:::

:::warn
Pour accéder à un `Ingress` d'un cluster local :

- Depuis un cluster `Docker` directement dans Linux, par l'adresse IP du _Node_
- Depuis un cluster `Docker` depuis _Docker Desktop_, en ajoutant un mapping de port puis en se connectant sur le mapping en `localhost`
- Dans le cas général : `kubectl port-forward 8888:80` vers l'ingress controller puis <http://localhost:8888>
:::

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
 name: api-ingress
 annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /

    # Load Balancing strategy
    # - "round_robin" (default)
    # - "least_connections" (équilibre charge)
    # - "ip_hash" (stick IP to Pod)
    nginx.ingress.kubernetes.io/load-balance: "round_robin"

    # Rate limit
    nginx.ingress.kubernetes.io/limit-rpm: "100"
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"

    # Si SSL, Issuer ou ClusterIssuer. Auto-configure le secret et le certificat
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # cert-manager.io/issuer: "letsencrypt-prod"

spec:
 ingressClassName: nginx
 tls: # seulement si TLS sur l'ingress
    - secretName: certif-test-cluster
      hosts:
        - test.cluster
 rules:
  # redirige http://api.example.com vers le service api-service
  - host: api.example.com
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: api-service
              port: 
                number: 8080
---
# Si TLS, secret associé (non nécessaire car auto-généré si cluster-issuer dans les annotation de l'Ingress)
apiVersion: v1
kind: Secret
metadata:
  name: example-tls
data:
  tls.crt: <base64 cert>
  tls.key: <base64 key>
type: kubernetes.io/tls
```


#### Traefik Ingress - canary

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rgb
  annotations:
    traefik.ingress.kubernetes.io/service-weights: |
      red: 50%
      green: 25%
      blue: 25%
spec:
  rules:
  - host: rgb.`A.B.C.D`.nip.io # remplacer A.B.C.D par l'IP du Node
    http:
      paths:
      - path: /
        backend:
          service:
            name: red
            port:
              number: 80
      - path: /
        backend:
          service:
            name: green
            port:
              number: 80
      - path: /
        backend:
          service:
            name: blue
            port:
              number: 80
```

### TLS : ClusterIssuer (Let's Encrypt)

```sh
# Pré-requis : Installation de cert-manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.17.0 \
  --set crds.enabled=true
# Ou :
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml
```

:::link
- Tutoriel : <https://cert-manager.io/docs/tutorials/acme/nginx-ingress/>
- Débug : <https://cert-manager.io/docs/troubleshooting/>
- Intégration de `cert-manager` dans un `Ingress` : <https://cert-manager.io/docs/usage/ingress/>
:::

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory # à garder - c'est le véritable serveur Let's Encrypt
    # server: https://acme-v02.api.letsencrypt.org/directory # serveur `prod` : https://letsencrypt.org/docs/rate-limits/
    email: contact@example.com # à remplacer
    privateKeySecretRef:
      name: letsencrypt-prod # où stocker le secret
    solvers:
      - http01:
          ingress:
            class: nginx
```

### Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: example-class
spec:
  controllerName: example.com/gateway-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: example-gateway
spec:
  gatewayClassName: example-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-httproute
spec:
  parentRefs:
  - name: example-gateway
  hostnames:
  - "www.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /login
    backendRefs:
    - name: example-svc
      port: 8080
```

### Endpoint

Lien entre `Service` et `Pod` :

```console
$ kubectl get endpoints
NAME           ENDPOINTS                     AGE
web-nodeport   10.244.1.2:80,10.244.2.2:80   114s

$ iptables -t nat -L KUBE-SERVICES
[…]
KUBE-SVC-GCYSPZR5VVR6P7RM  tcp  --  anywhere             10.96.228.139        /* default/web-nodeport cluster IP */ tcp dpt:82

$  iptables -t nat -L KUBE-SVC-GCYSPZR5VVR6P7RM
Chain KUBE-SVC-GCYSPZR5VVR6P7RM (2 references)
target     prot opt source               destination         
KUBE-MARK-MASQ  tcp  -- !10.244.0.0/16        10.96.228.139        /* default/web-nodeport cluster IP */ tcp dpt:82
KUBE-SEP-2YVSUODSDOHORZVC  all  --  anywhere             anywhere             /* default/web-nodeport -> 10.244.1.2:80 */ statistic mode random probability 0.50000000000
KUBE-SEP-XUOJDF7ZKWSRJPSP  all  --  anywhere             anywhere             /* default/web-nodeport -> 10.244.2.2:80 */
```

## Deployment

### Exemple de fichier de Déploiement et de Service

```yaml
# From: https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/application/php-apache.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  selector:
    matchLabels:
      run: php-apache
  template:
    metadata:
      labels:
        run: php-apache
    spec:
      containers:
      - name: php-apache # Requis
        image: registry.k8s.io/hpa-example # Requis
        ports:
        - containerPort: 80
        startupProbe: […] # sonde de démarrage
        livenessProbe: […] # sonde de healthcheck - conteneur killed si échec
        readinessProbe: […] # sonde d'état "Ready" - par exemple dépendance externe
        resources: # limitation de ressources pour auto-scaling
          limits:
            cpu: 500m # 0.5 unités CPU
          requests:
            cpu: 200m # 0.2 unités CPU
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
  labels:
    run: php-apache
spec:
  ports:
  - port: 80
  selector:
    run: php-apache
```

### Exemple de stratégie

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3  # 3 réplicas du pod
  strategy:
    type: RollingUpdate  # Stratégie par défaut, sinon `Recreate`
    rollingUpdate:
      maxUnavailable: 25%  # Maximum 25% de pods indisponibles pendant la mise à jour
      maxSurge: 25%        # Maximum 25% de nouveaux pods créés en plus des réplicas prévus
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app-container
        image: my-app-image
```

Kubernetes "met à jour" le Déploiement en cas de changement dans la configuration : version de l'image, … Il faut donc avoir des tags différents dans les images pour mettre à jour le(s) conteneur(s) (par exemple : `mon-image-docker:v1`, `mon-image-docker-v2`, … ).

### Exemple de fichier de ReplicaSet

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: my-replicaset
  labels:
    app: my-app
spec:
  replicas: 3  # Nombre de réplicas (pods) à maintenir
  selector: # Le ReplicaSet doit surveiller les pods avec le label app: my-app.
    matchLabels:
      app: my-app
  template: # Modèle pour créer les pods si nécessaire
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app-container
        image: nginx:latest 
        ports:
        - containerPort: 80
```

### Exemple de fichier HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50 # 50% de CPU
```

## Exemples de Jobs

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello-job
spec:
  completions: 3
  parallelism: 2
  activeDeadlineSeconds: 60 # timeout pour le Job total
  template:
    spec:
      containers:
        - name: hello
          image: busybox
          command: ["echo", "Hello from Kubernetes Job"]
      restartPolicy: Never
      activeDeadlineSeconds: 20 # timeout pour 1 Pod
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
 name: hello
spec:
 schedule: "*/5 * * * *"
 jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: hello
            image: busybox
            args:
            - /bin/sh
            - -c
            - date; echo Hello from the Kubernetes cluster
          restartPolicy: OnFailure
```

## Exemple de fichier de Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mon-namespace
```

## Exemple de RBAC (Role-Based Access Control)

### (Cluster)Role

Un `Role` (resp. `ClusterRole`) définit les permissions spécifiques qu'un utilisateur ou un système peut avoir. Un `Role` est limité à un seul namespace alors qu'un `ClusterRole` définit les permissions sur l'ensemble du cluster.

Les `verbs` possibles sont : `get`, `list`, `watch`, `create`, `update`, `delete`.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role # ou ClusterRole
metadata:
  name: example-role
  namespace: production # uniquement pour Role
rules:
  # Règle pour créer des pods dans le cluster
  - apiGroups: ["apps"]
    resources: ["pods"]
    verbs: ["create", "get", "list", "watch"]

  # Règle pour utiliser les services de réseau
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["use"]

  # Règle pour créer des ConfigMaps et Secrets
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["create"]
 
  # Règle pour utiliser les endpoints
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch"]
```

### (Cluster)RoleBinding

Le `RoleBinding` (resp. `ClusterRoleBinding`) lie un `Role` (resp. `ClusterRole`) à un sujet spécifique (utilisateur, groupe, objets) dans un namespace donné.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding # ou ClusterRoleBinding
metadata:
  name: example-rolebinding
subjects:
  - kind: User
    name: example-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role # ou ClusterRole
  name: example-role
  apiGroup: rbac.authorization.k8s.io
```

```sh
kubectl auth can-i list pods --as=example-user
```

## DaemonSet

Tourne un Nginx sur chaque noeud du cluster :

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
 name: nginx-daemonset
spec:
 selector:
    matchLabels:
      app: nginx
 template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
```

## StatefulSet

3 réplicas MySQL avec des volumes persistants individuels pour chaque réplica :

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
 name: mysql
spec:
 serviceName: "mysql" # nom du service headless
 replicas: 3 # mysql-0, mysql-1, …
 minReadySeconds: 10 # default 0
 selector:
    matchLabels:
      app: mysql # idem .spec.template.metadata.labels
 template:
    metadata:
      labels:
        app: mysql # idem .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: mysql
        image: mysql:5.7
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
 volumeClaimTemplates: # crée les PV de chaque réplica
 - metadata:
      name: mysql-data
    spec:
      accessModes: [ "ReadWriteOnce" ] # `ReadWriteOncePod` recommandé en prod
      resources:
        requests:
          storage: 5Gi
```

## NetworkPolicy

Permet de contrôler le trafic réseau entrant (`Ingress`) ou sortant (`Egress`) entre les pods.

:::link
Pour des exemples, voir : <https://github.com/ahmetb/kubernetes-network-policy-recipes>
:::

### Exemple 1

Bloquer tout le traffic par défaut :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {} # i.e. tous les Pods
  policyTypes:
  - Ingress
  - Egress
```

### Exemple 2

Permettre uniquement le trafic entrant vers un pod étiqueté avec `app: my-app`` depuis des pods étiquetés avec `role: frontend` :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
  - Ingress # ou Egress
  ingress:
  - from:  # Egress => to:
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 80
```

:::warn
Le CNI doit supporter la `NetworkPolicy` : ce n'est pas le cas de `Flannel` ! La ressource est ajoutée mais sans effet…
:::

## SecurityContext

Paramètres de sécurité appliqués à un pod ou à un conteneur :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsUser: 1000 # UID
    runAsGroup: 3000 # GID principal
    fsGroup: 2000 # GIDs secondaires
  containers:
  - name: secure-container
    image: nginx
    securityContext:
      capabilities:
        drop: [ALL]
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      seccompProfile: {...}
      appArmorProfile: {...}
      seLinuxOptions: {...}
```

## PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-pdb
spec:
  #minAvailable: 2
  #minAvailable: 90% # arrondi au supérieur
  maxUnavailable: 1
  #maxUnavailable: 10% # arrondi au supérieur
  selector:
    matchLabels:
      app: my-app
```

## Autres commandes

Pour plus d’information sur les différentes commandes de k8s, voir : <https://kubernetes.io/fr/docs/home/>

---

# Kubeseal

`Kubeseal` : outil transformant un `Secret` Kubernetes en `SealedSecret` chiffré (clé privée dans le cluster, clé publique pour générer les secrets, contrôleur `SealedSecrets`).
Seul le cluster peut déchiffrer un `SealedSecret`, il est donc possible de laisser les _Secret_ chiffrés dans _Git_.

- `--scope` : gère où un _Sealed Secret_ peut être déchiffré dans le cluster :
  - `strict` : secret non modifiable
  - `namespace-wide` : peut être renommé, limité à un namespace
  - `cluster-wide`

```sh
# Installation de SealedSecrets
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install sealed-secrets bitnami/sealed-secrets --namespace kube-system
```

Pour chiffrer un secret `mysecret.yaml` :

```sh
# Si accès direct au cluster, on chiffre directement le secret :
kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format yaml < mysecret.yaml > mysealedsecret.yaml

# Sinon, récupération de la clé publique avant chiffrement du secret avec cette clef
kubeseal --fetch-cert --controller-name=sealed-secrets --controller-namespace=kube-system > mycert.pem
kubeseal --cert mycert.pem --controller-name=sealed-secrets --controller-namespace=kube-system --format yaml < mysecret.yaml > mysealedsecret.yaml
```

Le déchiffrage s'utilise comme un Secret classique :

```sh
kubectl get secret secret-name -o yaml
```

Import / Export de clés :

```sh
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secret-key.yaml
kubectl apply -n kube-system -f sealed-secret-key.yaml
```

:::warn
Contrairement aux Secrets Kubernetes classiques, un SealedSecret ne peut pas être modifié directement dans le cluster. Toute modification requiert un chiffrement avec kubeseal avant d’être appliquée. Attention : Si une application utilise ce secret, elle ne recevra pas immédiatement la nouvelle valeur.
:::

---

# Cheatsheet Helm

## Parcourir le hub et les répos

```sh
helm search hub prometheus # https://artifacthub.io
helm repo list
helm pull "<repo_name>/<chart_name>" --untar # copie locale pour inspecter les fichiers
helm show readme "<repo_name>/<chart_name>"
helm show values "<repo_name>/<chart_name>"
```

## Récupérer et déployer une chart toute faite

```sh
helm repo add "<repo_name>" "<url>"
helm install [--set …] "<release_name>" "<repo_name>/<chart_name>"
helm upgrade -i [--set …] "<release_name>" "<repo_name>/<chart_name>" # upgrade -i installe ou met à jour
helm list # dans le namespace courant
helm list -A # dans tous les namespace
helm delete # ou (alias) helm uninstall
```

## Historique, rollback

```sh
helm show all "<chart_name>"
helm history …
helm upgrade "<chart_name>"
helm rollback "<chart_name>"
```

## Création d'une nouvelle Chart

```sh
# Crée un template pour la chart
helm create "<chart_name>"
```

## Helmfile

```sh
helmfile init # télécharge les plugins (facultatif)
helmfile apply # met à jour toutes les versions modifiées
helmfile sync # met à jour toutes les versions, même celles qui n'ont pas été modifiées
helmfile destroy
```

---

# Cheatsheet Kustomize

## Exemple de Kustomization

```
my-app/
├── kustomization.yaml
└── deployment.yaml
```

```yaml
# my-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
 name: myapp
spec:
 replicas: 3
 selector:
    matchLabels:
      app: myapp
 template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:v1
```

```yaml
# my-app/kustomization.yaml
resources:
- deployment.yaml

commonLabels:
  app: my-app

images:
  - name: my-app
    newTag: v2
```

## Tester les modifications (dry-run)

```sh
kubectl kustomize path/to/local/kustomization
```

## Appliquer la kustomization depuis un fichier local (test)

```sh
kubectl apply -k path/to/local/kustomization
```

:::link
Voir aussi : <https://blog.stephane-robert.info/docs/conteneurs/orchestrateurs/outils/kustomize/>
:::

---

# Cheatsheet FluxCD

## Bootstrap d'un nouveau dépôt

<https://fluxcd.io/flux/installation/bootstrap/>

## Ajouter un dépôt Git existant

```sh
flux create source git flux-system \
  --url=https://github.com/MON_GITHUB_USER/MON_GITHUB_REPO \
  --branch=main \
  --interval=1m \
  --namespace=flux-system
```

## Déployer des manifestes Kubernetes à partir de ce dépôt

```sh
flux create kustomization flux-system \
  --target-namespace=default \
  --source=flux-system \
  --path="./clusters/my-cluster" \
  --prune=true \
  --interval=10m \
  --namespace=flux-system
```

## Lister les HelmRelease

```sh
flux get helmreleases --all-namespaces
```

## Suivre les kustomizations

```sh
flux get kustomizations --watch
```

## Suspendre / reprendre la MAJ depuis une kustomization

```sh
flux suspend/resume kustomization nom-de-la-kusto
```

---

# Cheatsheet Kyverno

```sh
# Pré-requis : installation de Kyverno
helm upgrade --install --repo https://kyverno.github.io/kyverno/ \
--namespace kyverno --create-namespace kyverno kyverno
```

```sh
# Rapports de violations dans tous les namespace
kubectl get clusterpolicyreports --all-namespaces
```

:::tip
Il est possible de lier le cycle de vie des objets générés aux objets à l'origine de leur génération : voir [Lier des ressources aux `ownerReferences`](https://kyverno.io/docs/writing-policies/generate/#linking-trigger-with-downstream)
:::

## Exemples de validations

Exemple simple de politique `Kyverno` qui refuse la création de pods s'ils n'ont pas de label `app` :

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-app-label
spec:
  validationFailureAction: enforce
  rules:
    - name: check-for-label
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Le label 'app' est requis pour tous les pods."
        pattern:
          metadata:
            labels:
              app: "?*"
```

```yaml
# From: https://github.com/jpetazzo/container.training/blob/main/k8s/kyverno-pod-color-1.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pod-color-policy-1
spec:
  validationFailureAction: Enforce
  rules:
  - name: ensure-pod-color-is-valid
    match:
      resources:
        kinds:
        - Pod
        selector:
          matchExpressions:
          - key: color
            operator: Exists
          - key: color
            operator: NotIn
            values: [ red, green, blue ]
    validate:
      message: "If it exists, the label color must be red, green, or blue."
      deny: {}
```

```yaml
# From: https://github.com/jpetazzo/container.training/blob/main/k8s/kyverno-pod-color-2.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pod-color-policy-2
spec:
  validationFailureAction: Enforce
  background: false # obligatoire pour utiliser `{{ request }}` (update, …) sinon check asynchrone
  rules:
  - name: prevent-color-change
    match:
      resources:
        kinds:
        - Pod
    preconditions:
    - key: "{{ request.operation }}"
      operator: Equals
      value: UPDATE
    - key: "{{ request.oldObject.metadata.labels.color || '' }}" # `{{ request.oldObject }}` → l'objet tel qu'il était avant la requête
      operator: NotEquals
      value: ""
    - key: "{{ request.object.metadata.labels.color || '' }}" # `{{ request.object }}` → l'objet avec les modifications apportées par la requête
      operator: NotEquals
      value: ""
    validate:
      message: "Once label color has been added, it cannot be changed."
      deny:
        conditions:
        - key: "{{ request.object.metadata.labels.color }}"
          operator: NotEquals
          value: "{{ request.oldObject.metadata.labels.color }}"
```

## Exemples de génération de ressources

- Lors de la création d'un espace de noms, nous souhaitons également créer automatiquement :
- un `LimitRange` pour définir les requêtes et limites CPU et RAM par défaut
- un `ResourceQuota` pour limiter les ressources utilisées par l'espace de noms
- une `NetworkPolicy` pour isoler l'espace de noms

```yaml
# From: https://github.com/jpetazzo/container.training/blob/main/k8s/kyverno-namespace-setup.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: setup-namespace
spec:
  rules:
  - name: setup-limitrange
    match:
      resources: 
        kinds:
        - Namespace
    generate: 
      kind: LimitRange
      name: default-limitrange
      namespace: "{{request.object.metadata.name}}" 
      data:
        spec:
          limits:
          - type: Container
            min:
              cpu: 0.1
              memory: 0.1
            max:
              cpu: 2
              memory: 2Gi
            default:
              cpu: 0.25
              memory: 500Mi
            defaultRequest:
              cpu: 0.25
              memory: 250Mi
  - name: setup-resourcequota
    match:
      resources: 
        kinds:
        - Namespace
    generate: 
      kind: ResourceQuota
      name: default-resourcequota
      namespace: "{{request.object.metadata.name}}" 
      data:
        spec:
          hard:
            requests.cpu: "10"
            requests.memory: 10Gi
            limits.cpu: "20"
            limits.memory: 20Gi
  - name: setup-networkpolicy
    match:
      resources: 
        kinds:
        - Namespace
    generate: 
      kind: NetworkPolicy
      name: default-networkpolicy
      namespace: "{{request.object.metadata.name}}" 
      data:
        spec:
          podSelector: {}
          ingress:
          - from:
            - podSelector: {}
```

# Legal

- © 2025 Tom Avenel under CC  BY-SA 4.0
- Docker and the Docker logo are trademarks or registered trademarks of Docker, Inc. in the United States and/or other countries. Docker, Inc. and other parties may also have trademark rights in other terms used herein.
- Kubernetes® is a registered trademark of The Linux Foundation in the United States and/or other countries.

