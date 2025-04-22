
---

Prof : Charlie Bromberg
Groupe 08 : Owen Jeammot, Maël Joumier

---
**Objectif de l'exercice :**
- Deployer un cluster k8s en utilisant minikube
- Configurer les services du cluster en applicant les concepts vu en cours
- Introduire des vulnerabilites intentionnelles permettant un chemin d'attaque precis
- Exploiter le cluster en appliquant les principes d'attaque et d'escalade

**Scenario propose :**
Exposer un server web (ici flask) qui est vulnérable a l'injection de commande -> Escalade de privilege sur la machine web via un sudo NOPASSWD sur python -> Découverte reseau afin de trouver un pods non accessible depuis l'exterieurs -> Decouverte d'un service SSH accessible en connexion root avec un mot de passe faible -> Escape du pod  qui etait alors privileged -> Prise totale du cluster.

On peut retrouver ci dessous le schéma explicatif permettant de résumer l'attaque.


<p align="center">
  <img src="image-removebg-preview.png" alt="description">
</p>

## Mise en place du cluster

> OS : Debian
>Il faut au préalable avoir installer [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) et [minikube](https://minikube.sigs.k8s.io/docs/start/?arch=%2Flinux%2Fx86-64%2Fstable%2Fdebian+package)

Voici la structure du projet : 
```
📁 exo-2-k8s
├── 📁 docker
│   ├── 🐍 app.py
│   └── 🐳 Dockerfile
├── 📁 exploit
│   ├── 📄 cmd.txt
│   └── 🐍 exploit.py
├── 📁 k8s
│   ├── 📁 settings
│   │   ├── 📄 namespaces.yaml
│   │   ├── 📄 networkpolicy.yaml
│   │   ├── 📄 rbac.yaml
│   │   └── 📄 volumes.yaml
│   ├── 📁 ssh
│   │   ├── 📄 vuln-ssh-deployment.yaml
│   │   ├── 📄 vuln-ssh-secret.yaml
│   │   └── 📄 vuln-ssh-service.yaml
│   └── 📁 web
│       ├── 📄 vuln-web-configmap.yaml
│       ├── 📄 vuln-web-deployment.yaml
│       ├── 📄 vuln-web-service.yaml
├── ⚙️ .gitignore
├── 📜 LICENSE
└── 📝 README.md

```

Pour commencer nous allons nous focaliser sur la partie du server web en flask. Nous avons vraiment fait un server minimaliste qui permet simplement de lancer des commande sur le docker via une request avec l'argument cmd.

```python
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/ping')
def ping():
    cmd = request.args.get('cmd')
    if cmd:
        return os.popen(cmd).read()
    return "OK"

app.run(host="0.0.0.0", port=5000)
```

Une fois notre server simple teste nous pouvons mettre le projet dans un `Dockerfile`

```docker
FROM python:3.13.3-bookworm

# Update et installation de sudo
RUN apt update && apt install -y sudo

# Ajout des droits sudo en nopasswd au binaire python3
RUN echo "ALL ALL=(ALL) NOPASSWD: /usr/local/bin/python3" >> /etc/sudoers

# Creation de l'user flaskuser
RUN useradd -m -s /bin/bash flaskuser

# Installation du module flask
RUN pip install flask

# Copie du script python app.py en local vers notre docker
COPY app.py /app/app.py

# Initialisation du directory initiale
WORKDIR /app

# Setup de l'user par default du docker
USER flaskuser

# Commande de lancement du script python
CMD ["python", "app.py"]
```
Nous venons de crere notre application web dans un docker nous pouvons maintenant nous lancer dans la construction de notre cluster minikube. Pour ce faire on démarre minikube : `minikube start`. Puis on va pouvoir build notre image docker web que l'on vient de crerer dans le cluster minikube :
```bash
eval $(minikube docker-env)
docker build -t vuln-web:latest .
```
A note qu'il est important de faire un eval pour changer le contexte dans le quel on veut build le docker sinon ce dernier va se build dans notre registry local et pas sur le cluster minikube.
Voila parfait nous avons tout les prérequis afin de construire notre projet, lancons-nous maintenant dans la création de notre cluster. Pour ce faire nous allons commencer par créer tout nos fichiers de configuration afin de créer le cluster.

### K8S cluster settings :

On commence par se focusse sur cette partie : 
```
├── 📁 k8s
│   ├── 📁 settings
│   │   ├── 📄 namespaces.yaml
│   │   ├── 📄 networkpolicy.yaml
│   │   ├── 📄 rbac.yaml
│   │   └── 📄 volumes.yaml
```
##### **Namespaces :**

```yml
---
apiVersion: v1
kind: Namespace
metadata:
  name: vuln-web-external

---
apiVersion: v1
kind: Namespace
metadata:
  name: vuln-ssh-internal
```

Assez simple ici on cree deux namespace : vuln-web-external et vuln-ssh-internal. Le but d'un namespace est de separer les ressources dans des espaces logique differents afin de mieux gere les ressources.

##### **Networkpolicy :**

```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-ssh
  namespace: vuln-ssh-internal
spec:
  podSelector: # permet de selectionner le pods vise par la regle
    matchLabels:
      app: vuln-ssh
  ingress:
  - from:
    - namespaceSelector: # permet d'autoriser l'access au namespace vuln-web-external
        matchLabels:
          name: vuln-web-external
  policyTypes:
  - Ingress
```

Le but de ce fichier de configuration est de restrindre l'access a la machine vuln-ssh seulement au pods qui appartienne au namespace vuln-web-external. Le but des NetworkPolicy sont de creer des regles pour la connectivite des ressources dans le cluster.

##### **RBAC :**

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ssh-admin
  namespace: vuln-ssh-internal
  
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: superadmin
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: superadmin-binding
subjects:
- kind: ServiceAccount
  name: ssh-admin
  namespace: vuln-ssh-internal
roleRef:
  kind: ClusterRole
  name: superadmin
  apiGroup: rbac.authorization.k8s.io
```

RBAC (Role-Based Access Control), ce dernier permet de donner des droits administrateurs a un pod ou une personne, un processus... Dans ce fichier on s'occupe donc de faire 3 chose : 
	- Creation d'un compte de service `ssh-admin` dans le namespace `vuln-ssh-internal`
	- Creation d'un role rbac qui donne tout les droits sur tout les groupes d'apim toutes les ressources et tout les verbs.
	- Creation du lien entre le role rbac et le compte de service.
Grace a ces trois regles on a maintenant un compte de service `ssh-admin` qui possede tout les droits sur le cluster.


##### **Volumes :**

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: host-ssh-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: host-ssh-pvc
  namespace: vuln-ssh-internal
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

On s'occupe ici de creer un PV (PersistentVolume) et  un PVC (PersistentVolumeClaim).
	- PV : C'est un espace de stockage dans le cluster mis à disposition par un administrateur ou provisionné automatiquement. C’est comme un disque dur partagé, que Kubernetes peut connecter à des pods.
	- PVC est une demande de stockage faite par un pod qui permet de dire combien il veut en espace, les droits (R, W...).
On a donc dans ce fichier de configuration la creation d'un volume de 10G en RW qui est monte sur `/` de l'host. Puis on a une demande d'attribution d'espace dans le namespace `vuln-ssh-internal` de 1G.

Voila avec tout cela nous avons fini de configurer les parametteres "generale" de notre cluster et nous allons pouvoir nous focus sur la creation de nos services. Commencons par le service web expose : 

### K8S cluster web :

```
│   └── 📁 web
│       ├── 📄 vuln-web-configmap.yaml
│       ├── 📄 vuln-web-deployment.yaml
│       ├── 📄 vuln-web-service.yaml
```

Le but ici va donc de presenter les differents fichiers de configuration necessaire a la creation du pods web dans les conditions necessaire a notre scenario :

##### **ConfigMap :**

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: vuln-web-config
  namespace: vuln-web-external
data:
  FLASK_ENV: "development"
```

Un configmap permet de stocker des parametres de configuration pour des applciations qui sont dans des pods. On peut y mettre des variables d'enriroemment comme ici : `FLASK_ENV: "development"` mais on peut aussi mettre des fichiers de configuration, des chaines de texte ... Tout ca dans le but d'externatliser la config pour pouvoir modifier le comporatement du pods sans changer l'image docker.

##### **Deployment :**


```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vuln-web
  namespace: vuln-web-external
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vuln-web
  template:
    metadata:
      labels:
        app: vuln-web
    spec:
      containers:
      - name: web
        image: vuln-web:latest
        imagePullPolicy: Never # permet de prendre l'image build en local precedement
        resources: # permet de preciser la consomation max du pod
          limits:
            memory: 512Mi
            cpu: "1"
          requests:
            memory: 256Mi
            cpu: "0.2"
        ports:
        - containerPort: 5000
        livenessProbe: # Permet de verifier que l'application est en vie
          httpGet:
            path: /ping
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe: # Permet de verifier que l'appl est prete a recevoir du trafic
          httpGet:
            path: /ping
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 10
        envFrom: # Provisionement de variable d'envormmement en prenant la configmap
        - configMapRef:
            name: vuln-web-config
```

Ce fichier de type deployment permet de decrire precisement comment nous voulons deployer notre machine. Dans ce fichier on precise l'image docker que l'on veut utiliser, le nombre de replique que nous voulons, le label dans le quel on veut notre pods, les ressources que l'on veut q;il utilise...

##### **Service :**

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: vuln-web-svc
  namespace: vuln-web-external
spec:
  selector:
    app: vuln-web
  ports:
    - protocol: TCP
      port: 80 # Port interne dans le cluster
      targetPort: 5000 # Port du docker
      nodePort: 30080 # Port exterieur 
  type: NodePort
```

Le but de ce fichier de conguration de type `service` est d'exposer notre pods vers l'exterieur du cluster. Pour ce faire nous allons mapper le port originale du pods `5000` vers un port externieur sur notre cluster minikube `30080` afin de pouvoir tapper notre application depuis l'exterieur. Ici le service que l'on declare est de type `NodePort` nous permet de rendre l'applkication accessible sur : `http://IP_du_Node:30080`

Superbe maintenant notre application web vulnerable devrait pouvoir etre accesible depuis l'exterieure nous allons maintenant nous occuper de notre deuxieme machine vulnerable 

### K8S cluster ssh :

```
│   ├── 📁 ssh
│   │   ├── 📄 vuln-ssh-deployment.yaml
│   │   ├── 📄 vuln-ssh-secret.yaml
│   │   └── 📄 vuln-ssh-service.yaml
```

Nous observons deja que la structure est assez similaire a notre precedent deploiyement de web. Plongons nous un en plus en profondeur afin de voir les diferences.

##### **Secret :**

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ssh-credentials
  namespace: vuln-ssh-internal
type: kubernetes.io/basic-auth # Permet de provisionner des identifients
data:
  username: cm9vdA==        # "root"
  password: cm9vdA==        # "root"
```

A la difference de tout a l'heure au lieu de declarer une configMap nous avons declarer un fichier de configuration `Secret` qui comme son nom l'indique de gerer les secrets. Dans ce fichier nous utilisons donc le type `basic-auth` afin de provisionner des identifiants mot de passe a un compte.

##### **Deployment :**

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vuln-ssh
  namespace: vuln-ssh-internal
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vuln-ssh
  template:
    metadata:
      labels:
        app: vuln-ssh
    spec:
      serviceAccountName: ssh-admin # Lui donne les acces ssh-admin
      containers:
      - name: vuln-ssh
        image: rastasheep/ubuntu-sshd:18.04 # Image docker
        imagePullPolicy: Always
        resources: # Limitation materiel du pod
          limits:
            memory: 512Mi
            cpu: "1"
          requests:
            memory: 256Mi
            cpu: "0.2"
        ports:
        - containerPort: 22
        securityContext:
          privileged: true # Permet l'acces au system host
          capabilities:
            add: ["SYS_ADMIN", "SYS_PTRACE", "NET_ADMIN" # Donne des capabilities (droits).
          runAsUser: 0 # S'execute en root
          allowPrivilegeEscalation: true
        env:
        - name: ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ssh-credentials # Provisionnement du secret precedement evoque
              key: password
        command: ["/bin/bash"]
        args:
        - "-c"
        - |
          echo "root:$ROOT_PASSWORD" | chpasswd && \
          /usr/sbin/sshd -D # Commande au demarage du docker afin de mettre le mp du docker provisionner dans le secret
        volumeMounts:
        - name: host-root
          mountPath: /host 
      volumes: # Permet de monter le systeme de 
      - name: host-root
        hostPath:
          path: /
          type: Directory
      restartPolicy: Always
```