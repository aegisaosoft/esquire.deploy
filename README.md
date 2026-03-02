# Esquire Deploy

Infrastructure repository for the **Esquire Frameworks** platform.
Contains Jenkins CI/CD pipeline, Kubernetes manifests, Docker Compose configs and Nginx reverse-proxy.

**Fully parameterized** — deploys to any Linux host. No hardcoded IPs.

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
               <any Linux host>
```

## Repository structure

```
esquire.deploy/
├── Jenkinsfile                     # Jenkins CI/CD pipeline
├── README.md
├── deploy/
│   ├── .env                        # Environment variables (DEPLOY_HOST auto-set)
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
│       ├── configmap.yaml          # App configuration (uses __DEPLOY_HOST__ placeholder)
│       ├── secret.yaml             # DB & Keycloak credentials
│       ├── postgres-endpoint.yaml  # External PostgreSQL service (uses __DB_HOST__ placeholder)
│       ├── keycloak.yaml           # Keycloak deployment + service
│       ├── biztree.yaml            # bizTree deployment + service
│       ├── enyman.yaml             # enyMan deployment + service
│       ├── pacman.yaml             # pacMan deployment + service
│       ├── keysmith.yaml           # keySmith deployment + service
│       ├── gateway.yaml            # API Gateway (uses __DEPLOY_HOST__ placeholder)
│       ├── frontend.yaml           # Angular frontend (uses __DEPLOY_HOST__ placeholder)
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

Any Linux host with:

- **Docker** + **Docker Compose**
- **Kubernetes** (microk8s, k3s or kubeadm)
- **kubectl**
- **Jenkins** (with Pipeline plugin)
- **PostgreSQL** running on the host or reachable by network (database `esq2025`)

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

| Parameter         | Default       | Description                                                  |
|-------------------|---------------|--------------------------------------------------------------|
| `DEPLOY_HOST`     | (auto-detect) | Target host IP or hostname. If empty, uses `hostname -I`     |
| `DB_HOST`         | = DEPLOY_HOST | PostgreSQL host IP. If empty, defaults to DEPLOY_HOST        |
| `BUILD_SERVICES`  | true          | Build backend images (biztree, enyman, pacman, keysmith, gw) |
| `BUILD_FRONTEND`  | true          | Build Angular frontend image                                 |
| `RUN_DB_SEED`     | false         | Execute SQL seed scripts from esquire.db.seed                |
| `FULL_RESET`      | false         | Delete K8s namespace and redeploy from scratch               |
| `BRANCH_SERVICES` | main          | Git branch for esquire.services                              |
| `BRANCH_EXPLORER` | main          | Git branch for esquire.explorer                              |
| `BRANCH_DB_SEED`  | main          | Git branch for esquire.db.seed                               |

## Pipeline stages

```
 1. Checkout          Clone all 4 repos in parallel
 2. Resolve Hosts     Auto-detect or use provided DEPLOY_HOST / DB_HOST
 3. Prepare           Verify Docker + kubectl, detect K8s runtime
 4. Sync              rsync sources to /opt/esquire
 5. Configure         Inject host IPs into .env and K8s manifests
 6. Build Images      docker build × 6 images (parallel)
 7. Import Images     docker save | microk8s/k3s ctr import
 8. DB Seed           (optional) psql seed scripts
 9. Full Reset        (optional) kubectl delete namespace
10. Apply Manifests   kubectl apply (namespace → config → services)
11. Rolling Restart   kubectl rollout restart (rebuilt services only)
12. Wait for Rollouts kubectl rollout status (all deployments)
13. Smoke Test        curl health endpoints via NodePorts
```

## Usage examples

### Full deploy (all services)

Run with default parameters — auto-detects host IP, builds and deploys everything.

### Deploy to a specific host

```
DEPLOY_HOST = 10.0.0.50
```

### DB on a separate server

```
DEPLOY_HOST = 10.0.0.50
DB_HOST     = 10.0.0.100
```

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

# Auto-detect host IP:
./deploy-k8s.sh

# Or specify host IP:
./deploy-k8s.sh 10.0.0.50

# Or specify host IP + separate DB host:
./deploy-k8s.sh 10.0.0.50 10.0.0.100
```

### Docker Compose (HTTPS)

```bash
cd deploy
# Set DEPLOY_HOST in .env first
echo "DEPLOY_HOST=10.0.0.50" >> .env
chmod +x deploy.sh
./deploy.sh deploy
```

### Docker Compose (direct ports)

```bash
cd deploy
echo "DEPLOY_HOST=10.0.0.50" >> .env
docker compose -f compose.remote.yaml up -d
```

## Access

After deployment (replace `<HOST>` with your DEPLOY_HOST):

| Endpoint   | Kubernetes               | Docker Compose (HTTPS)      | Docker Compose (remote)       |
|------------|--------------------------|-----------------------------|-------------------------------|
| Frontend   | http://\<HOST\>:30200    | https://\<HOST\>            | http://\<HOST\>:4200          |
| Gateway    | http://\<HOST\>:30000    | https://\<HOST\>:3443       | http://\<HOST\>:3000          |
| Keycloak   | http://\<HOST\>:30080    | https://\<HOST\>:8443       | http://\<HOST\>:8080          |

## Related repositories

| Repository | GitHub | Description |
|---|---|---|
| esquire.services | [mir0n-pro/esquire.services](https://github.com/mir0n-pro/esquire.services) | Java backend microservices |
| esquire.explorer | [mir0n-pro/esquire.explorer](https://github.com/mir0n-pro/esquire.explorer) | Angular frontend |
| esquire.db.seed  | [mir0n-pro/esquire.db.seed](https://github.com/mir0n-pro/esquire.db.seed)   | Database seed scripts |
