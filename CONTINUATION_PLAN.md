# Esquire Deploy — Continuation Plan

## Current State (2026-03-03)

### ✅ Completed
1. **Keycloak KC_HOSTNAME fix** — removed `KC_HOSTNAME` from `keycloak.yaml` (was forcing external issuer for all requests)
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

6. **Issuer mismatch fix** — builds #9–#11 all failed with gateway CrashLoopBackOff
   - Problem: `KC_HOSTNAME` forced Keycloak to return external issuer (`https://<IP>:30843`) for ALL requests, including internal gateway → Spring Security OIDC discovery rejected mismatch
   - Failed attempt 1 (build #10): `KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true` — ignored in `start-dev` mode
   - Failed attempt 2 (build #11): Jenkinsfile sed to remove `issuer-uri` — unreliable with multi-stage Docker builds (Docker cache)
   - **Final fix**: Removed `KC_HOSTNAME` and `KC_HOSTNAME_BACKCHANNEL_DYNAMIC` from `keycloak.yaml`. Without `KC_HOSTNAME`, Keycloak in `start-dev` mode dynamically resolves issuer from each request:
     - Internal (gateway → `http://keycloak:8080`): issuer = `http://keycloak:8080/realms/esquire` ✓
     - External (browser via proxy with `X-Forwarded-*`): issuer = `https://<IP>:30843/realms/esquire` ✓
   - Safe because resource server uses `jwk-set-uri` (signature-only validation, no `iss` claim check)
   - Also removed sed hack from Jenkinsfile and keycloak.yaml sed from Configure stage (no more `__DEPLOY_HOST__` placeholder in keycloak.yaml)
   - **Build #12: SUCCESS** — all pods Running, smoke tests pass

7. **Port forwarding (minikube)** — added stage 14 to Jenkinsfile
   - Problem: minikube Docker driver exposes NodePorts only on container IP (192.168.49.2), not host IP (192.168.1.104) → URLs inaccessible from browser
   - Fix: new "Port Forwarding" stage runs a `socat` container with `--net=host` that forwards all 6 NodePorts from host to minikube:
     - 30000 (gateway HTTP), 30080 (keycloak HTTP), 30200 (frontend HTTP)
     - 30443 (frontend HTTPS), 30343 (gateway HTTPS), 30843 (keycloak HTTPS)
   - Container name: `esquire-port-forward`, `--restart=unless-stopped` (survives reboots)
   - Only activates for minikube runtime (other runtimes expose NodePorts directly)

8. **Build #15: SUCCESS** — all pods Running, URLs accessible from Windows browser

9. **Login flow fix** (2026-03-03) — 3 issues fixed:
   - **Proxy headers** (`proxy.yaml`): Keycloak block used `$host:$server_port` (sent internal port 8443 instead of external NodePort 30843). Fixed: `$http_host` preserves original Host header (`192.168.1.104:30843`). Removed `X-Forwarded-Port`. Also fixed gateway block.
   - **Keycloak redirectUris** (`esquire.json`): `esq-angular` client had hardcoded `http://localhost:4200` in redirectUris/webOrigins → Keycloak rejected `redirect_uri=https://IP:30443`. Fixed: added `https://__DEPLOY_HOST__:30443` patterns + sed in Jenkinsfile Configure stage.
   - **checkLoginIframe** (`esquire.explorer/main.ts`): `checkLoginIframe: true` caused "Timeout when waiting for 3rd party check iframe message" — cross-port iframe (30443→30843) unreliable with self-signed certs. Fixed: `checkLoginIframe: false`.
   - Commits: esquire.deploy `217cba4`, esquire.explorer `ccf7df2`

### ❌ Not Yet Verified
1. **Build #16** — need to run with `FULL_RESET=true` to pick up all fixes (especially Keycloak realm reimport with corrected redirectUris + admin password reset)
2. **End-to-end login** — verify full OIDC flow: Angular → Keycloak login page → redirect back with token
3. **Keycloak HTTPS console** — `https://192.168.1.104:30843` should show admin UI (not redirect to :8443)
4. **Keycloak admin login** — credentials from K8s secret should work after FULL_RESET

---

## Next Steps

### Step 1: Run Jenkins Build #16 with FULL_RESET
- Go to Jenkins UI
- Set `FULL_RESET=true` (this destroys and recreates the `esquire` namespace → reimports Keycloak realm with fixed redirectUris + resets admin credentials)
- Set `BUILD_SERVICES=true`, `BUILD_FRONTEND=true`
- Watch all stages

### Step 2: Verify Keycloak HTTPS
1. Open `https://192.168.1.104:30843` (accept self-signed cert)
2. Should show Keycloak admin console login page (NOT redirect to `:8443`)
3. Log in with admin credentials from `.env`

### Step 3: Verify End-to-End Login
1. Open `https://192.168.1.104:30443` (accept self-signed cert)
2. App should load without "Timeout waiting for iframe" error in console
3. Click Login → should redirect to `https://192.168.1.104:30843/realms/esquire/protocol/openid-connect/auth?...`
4. Log in → should redirect back to `https://192.168.1.104:30443` with valid token

### Step 4: Diagnostics (if login fails)
- Check frontend pod logs: `kubectl logs deployment/frontend -n esquire` — look for `==> config.json:` to verify envsubst output
- Check Keycloak pod logs for redirect/CORS errors
- Verify `esq-angular` client in Keycloak admin: Clients → esq-angular → Valid redirect URIs should include `https://192.168.1.104:30443/*`

### Step 5: Make Jenkins Networking Permanent
Currently `docker network connect minikube jenkins` is lost on Jenkins container restart.
Fix: update Jenkins container creation command to include `--network minikube`.

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

Port forwarding (minikube only):
  Host (0.0.0.0:30xxx) → socat → minikube (192.168.49.x:30xxx)
  Container: esquire-port-forward (alpine + socat, --net=host)
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
