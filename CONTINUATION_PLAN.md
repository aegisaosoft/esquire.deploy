# Esquire Deploy — Continuation Plan

## Current State (2026-03-02)

### ✅ Completed
1. **Keycloak KC_HOSTNAME fix** — `keycloak.yaml` has `KC_HOSTNAME: "https://__DEPLOY_HOST__:30843"`, `KC_PROXY_HEADERS: "xforwarded"`
2. **Jenkinsfile fixes** (commit `e149a8e` on GitHub):
   - Default branches changed from `main` → `develop` (all 3 repos use `develop`)
   - Container-aware IP detection: uses `docker run --net=host busybox` when inside Docker
   - Docker check: `docker ps` instead of `docker info` (which fails on warnings)
   - Smoke test: uses `kubectl get nodes` IP instead of `localhost`
   - Minikube image import: `docker exec -i minikube ctr -n k8s.io image import -` (no minikube CLI needed)
   - Registry support: REGISTRY parameter for full K8s (pushes to registry)
3. **Jenkins container networking**:
   - `docker restart jenkins` — picks up docker group
   - `docker network connect minikube jenkins` — Jenkins can reach minikube API (192.168.49.2)
   - Verified: `docker exec jenkins docker ps` ✅ and `docker exec jenkins kubectl get nodes` ✅
4. **nginx TLS proxy** (`proxy.yaml`) — HTTPS termination:
   - `:30443` → frontend (Angular :4200)
   - `:30343` → gateway (Spring :7070)
   - `:30843` → keycloak (:8080)
5. **Frontend config** — `config.json.template` uses `keycloakUrl` (not `keycloakConfigUrl`), ports 30343/30843

6. **KC_HOSTNAME_BACKCHANNEL_DYNAMIC fix** — added `KC_HOSTNAME_BACKCHANNEL_DYNAMIC: "true"` to `keycloak.yaml`
   - Build #9 failed: gateway CrashLoopBackOff due to issuer mismatch
   - Gateway connects internally at `http://keycloak:8080`, but Keycloak returned issuer `https://<IP>:30843`
   - ⚠️ Build #10 FAILED — `KC_HOSTNAME_BACKCHANNEL_DYNAMIC` does NOT work with `start-dev` mode (Keycloak ignores it)
7. **Gateway issuer-uri sed fix** — Jenkinsfile Configure stage now removes `issuer-uri` from gateway's application.yml
   - Root cause: Spring Security OIDC discovery validates issuer, which mismatches in K8s
   - Fix: Remove `issuer-uri` so Spring Boot uses the explicitly configured endpoints (authorization-uri, token-uri, jwk-set-uri, user-info-uri) without OIDC discovery
   - The sed targets `issuer-uri: http://${KEYCLOAK_HOST` lines in application.yml before Maven build

### ❌ Not Yet Verified
1. **Build #11** — need to re-run Jenkins after issuer-uri sed fix
2. **Keycloak redirect** not tested end-to-end (was `http://localhost:8080`, should be `https://<IP>:30843`)
3. **Full pipeline** — Maven build, Docker image build, minikube import, K8s deploy, smoke tests

---

## Next Steps

### Step 1: Run Jenkins Build
- Go to Jenkins UI (http://192.168.1.104:8888 or whatever the Jenkins URL is)
- Run build with parameters:
  - `DEPLOY_HOST`: `192.168.1.104` (or leave empty to auto-detect)
  - `BUILD_SERVICES`: true
  - `BUILD_FRONTEND`: true
  - All other defaults
- Monitor console output for errors

### Step 2: Expected Issues / Watch Points
1. **Maven Build stage** — first build may be slow (downloads deps to `esquire-maven-cache` Docker volume)
2. **Docker image builds** — check that Dockerfiles exist and are correct in all service dirs
3. **Minikube image import** — `docker save | docker exec -i minikube ctr` can be slow for large images
4. **Apply Manifests** — check that all YAML files exist in `/opt/esquire/deploy/k8s/`
5. **Keycloak startup** — takes 30-60s, readiness probe at `/health/ready:9000`
6. **Frontend compilation** — `ng serve` takes time; smoke test at :30200 may show non-200 initially (this is OK, pipeline allows it)
7. **Post-failure diagnostics** — if build fails, `post { failure }` kubectl commands may hang ~2.5 min each; consider adding `--timeout` or `timeout` wrapper

### Step 3: Verify Keycloak Redirect
After successful deploy:
1. Open `https://<IP>:30443` in browser (accept self-signed cert)
2. Should see Angular app → click Login
3. Should redirect to `https://<IP>:30843/realms/esquire/protocol/openid-connect/auth?...`
4. NOT `http://localhost:8080/...` ← this was the original bug

### Step 4: Make Jenkins Networking Permanent
Currently `docker network connect minikube jenkins` is lost on Jenkins container restart.
Fix: update Jenkins container creation command to include `--network minikube`:
```bash
# Option A: Add to docker run command
docker run -d --name jenkins --network minikube ...

# Option B: Use docker-compose with networks
# Option C: Add to a startup script that runs after docker start
```

### Step 5: Post-Failure Diagnostics Timeout
Add timeouts to `post { failure }` block to prevent 5+ minute hangs:
```groovy
post {
    failure {
        sh """
            timeout 15 kubectl get pods -n ${NAMESPACE} -o wide 2>/dev/null || true
            timeout 15 kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
        """
    }
}
```

---

## Architecture Overview

```
Browser → https://<IP>:30443 (nginx proxy)
           ├── / → frontend:4200 (Angular)
           └── (via :30343) → gateway:7070 (Spring Cloud Gateway)
                               ├── /api/biztree/** → biztree:8081
                               ├── /api/enyman/** → enyman:8082
                               ├── /api/pacman/** → pacman:8083
                               └── /api/keysmith/** → keysmith:8084

Keycloak → https://<IP>:30843 (nginx proxy → keycloak:8080)
PostgreSQL → external (DEPLOY_HOST:5432)
```

## Key Files
- **Jenkinsfile**: `C:\aegis-esquire\esquire.deploy\Jenkinsfile` (Windows) / cloned to Jenkins workspace
- **K8s manifests**: `C:\aegis-esquire\esquire.deploy\deploy\k8s\*.yaml`
- **proxy config**: `C:\aegis-esquire\esquire.deploy\deploy\k8s\proxy.yaml` (nginx + TLS)
- **frontend config template**: in `esquire.explorer/frontend/public/assets/config.json.template`
- **Keycloak realm**: `C:\aegis-esquire\esquire.deploy\deploy\import\esquire.json`

## Repos (all on GitHub under `mir0n-pro`, branch `develop`)
1. `mir0n-pro/esquire.services` — Java microservices (bizTree, enyMan, pacMan, keySmith, gateway)
2. `mir0n-pro/esquire.explorer` — Angular frontend
3. `mir0n-pro/esquire.db.seed` — DB seed SQL scripts
4. `aegisaosoft/esquire.deploy` — Infra: Jenkinsfile, K8s manifests, docker-compose, proxy

## Jenkins Setup
- Runs as Docker container named `jenkins` on Linux host
- Docker socket mounted: `-v /var/run/docker.sock:/var/run/docker.sock`
- kubectl + kubeconfig mounted from host
- After restart: needs `docker network connect minikube jenkins`
