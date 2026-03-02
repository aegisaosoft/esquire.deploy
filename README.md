# Esquire Deploy

Infrastructure repository for the **Esquire Frameworks** platform.
Contains Jenkins CI/CD pipeline, Kubernetes manifests, Docker Compose configs and Nginx reverse-proxy.

## Architecture

```
                         aegisaosoft/esquire.deploy  (this repo)
                                    |
                     Jenkins Pipeline (Jenkinsfile)
                                    |
              ┌─────────────────────┼─────────────────────┐
              v                     v                     v
   mir0n-pro/esquire.services  mir0n-pro/esquire.explorer  mir0n-pro/esquire.db.seed
   (Java 21, Spring Boot)     (Angular 20, Material)      (PostgreSQL seed SQL)
              |                     |
              v                     v
        5 Docker images       1 Docker image
        biztree, enyman       frontend
        pacman, keysmith
        gateway
              |                     |
              └─────────┬───────────┘
                        v
               Kubernetes (namespace: esquire)
               192.168.1.104
```

## Repository structure

```
esquire.deploy/
├── Jenkinsfile                     # Jenkins CI/CD pipeline
├── README.md
├── deploy/
│   ├── .env                        # Environment variables
│   ├── compose.yaml                # Docker Compose — HTTPS (Nginx proxy)
│   ├── compose.remote.yaml         # Docker Compose — direct ports
│   ├── deploy.sh                   # Manual deploy script (bash)
│   ├── import/
│   │   └── esquire.json            # Keycloak realm configuration
│   ├── proxy/
│   │   ├── Dockerfile              # Nginx reverse-proxy image
│   │   ├── nginx.conf              # HTTPS config (443, 3443, 8443)
│   │   └── entrypoint.sh           # Self-signed cert generation
│   └── k8s/
│       ├── namespace.yaml          # K8s namespace "esquire"
│       ├── configmap.yaml          # App configuration
│       ├── secret.yaml             # DB & Keycloak credentials
│       ├── postgres-endpoint.yaml  # External PostgreSQL service
│       ├── keycloak.yaml           # Keycloak deployment + service
│       ├── biztree.yaml            # bizTree deployment + service
│       ├── enyman.yaml             # enyMan deployment + service
│       ├── pacman.yaml             # pacMan deployment + service
│       ├── keysmith.yaml           # keySmith deployment + service
│       ├── gateway.yaml            # API Gateway deployment + service
│       ├── frontend.yaml           # Angular frontend deployment + service
│       └── deploy-k8s.sh           # Manual K8s deploy script
└── scripts/
    └── *.bat                       # Legacy Windows startup scripts
```

## Services

| Service    | Port  | K8s NodePort | Description                        |
|------------|-------|--------------|------------------------------------|
| biztree    | 3002  | —            | Entity tree navigation             |
| enyman     | 3003  | —            | Entity Manager                     |
| pacman     | 3004  | —            | Personal Account Manager           |
| keysmith   | 3005  | —            | Access profiles & Keycloak bridge  |
| gateway    | 7070  | 30000        | API Gateway (Spring Cloud Gateway) |
| frontend   | 4200  | 30200        | Angular UI                         |
| keycloak   | 8080  | 30080        | Identity & Access Management       |

## Prerequisites

Ubuntu server (192.168.1.104) with:

- **Docker** + **Docker Compose**
- **Kubernetes** (microk8s, k3s or kubeadm)
- **kubectl**
- **Jenkins** (with Pipeline plugin)
- **PostgreSQL** running on the host (database `esq2025`)

### Server setup

```bash
# Jenkins user needs Docker + K8s access
sudo usermod -aG docker jenkins
sudo usermod -aG microk8s jenkins   # for microk8s
# or copy kubeconfig
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /root/.kube/config /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube

# Create project directory
sudo mkdir -p /opt/esquire
sudo chown jenkins:jenkins /opt/esquire

# Restart Jenkins
sudo systemctl restart jenkins
```

## Jenkins setup

1. **New Item** > Pipeline
2. **Pipeline** > Definition: **Pipeline script from SCM**
3. SCM: Git > `https://github.com/aegisaosoft/esquire.deploy.git`
4. Branch: `main`
5. Script Path: `Jenkinsfile`

## Pipeline parameters

| Parameter         | Default | Description                                                  |
|-------------------|---------|--------------------------------------------------------------|
| `BUILD_SERVICES`  | true    | Build backend images (biztree, enyman, pacman, keysmith, gw) |
| `BUILD_FRONTEND`  | true    | Build Angular frontend image                                 |
| `RUN_DB_SEED`     | false   | Execute SQL seed scripts from esquire.db.seed                |
| `FULL_RESET`      | false   | Delete K8s namespace and redeploy from scratch               |
| `BRANCH_SERVICES` | main    | Git branch for esquire.services                              |
| `BRANCH_EXPLORER` | main    | Git branch for esquire.explorer                              |
| `BRANCH_DB_SEED`  | main    | Git branch for esquire.db.seed                               |

## Pipeline stages

```
 1. Checkout          Clone all 4 repos in parallel
 2. Prepare           Verify Docker + kubectl, detect K8s runtime
 3. Sync              rsync sources to /opt/esquire
 4. Build Images      docker build × 6 images (parallel)
 5. Import Images     docker save | microk8s/k3s ctr import
 6. DB Seed           (optional) psql seed scripts
 7. Full Reset        (optional) kubectl delete namespace
 8. Apply Manifests   kubectl apply (namespace → config → services)
 9. Rolling Restart   kubectl rollout restart (rebuilt services only)
10. Wait for Rollouts kubectl rollout status (all deployments)
11. Smoke Test        curl health endpoints via NodePorts
```

## Usage examples

### Full deploy (all services)

Run with default parameters — builds everything and deploys.

### Frontend only

```
BUILD_SERVICES = false
BUILD_FRONTEND = true
```

### Backend only

```
BUILD_SERVICES = true
BUILD_FRONTEND = false
```

### Redeploy without rebuild

```
BUILD_SERVICES = false
BUILD_FRONTEND = false
```

Re-applies K8s manifests without rebuilding Docker images.

### Clean install

```
FULL_RESET  = true
RUN_DB_SEED = true
```

Destroys the namespace, re-seeds the database, and deploys fresh.

## Manual deploy (without Jenkins)

### Kubernetes

```bash
cd deploy/k8s
chmod +x deploy-k8s.sh
./deploy-k8s.sh
```

### Docker Compose (HTTPS)

```bash
cd deploy
chmod +x deploy.sh
./deploy.sh deploy
```

### Docker Compose (direct ports)

```bash
cd deploy
docker compose -f compose.remote.yaml up -d
```

## Access

After deployment:

| Endpoint   | Kubernetes              | Docker Compose (HTTPS)          | Docker Compose (remote)          |
|------------|-------------------------|---------------------------------|----------------------------------|
| Frontend   | http://192.168.1.104:30200 | https://192.168.1.104        | http://192.168.1.104:4200        |
| Gateway    | http://192.168.1.104:30000 | https://192.168.1.104:3443   | http://192.168.1.104:3000        |
| Keycloak   | http://192.168.1.104:30080 | https://192.168.1.104:8443   | http://192.168.1.104:8080        |

## Related repositories

| Repository | GitHub | Description |
|---|---|---|
| esquire.services | [mir0n-pro/esquire.services](https://github.com/mir0n-pro/esquire.services) | Java backend microservices |
| esquire.explorer | [mir0n-pro/esquire.explorer](https://github.com/mir0n-pro/esquire.explorer) | Angular frontend |
| esquire.db.seed  | [mir0n-pro/esquire.db.seed](https://github.com/mir0n-pro/esquire.db.seed)   | Database seed scripts |
