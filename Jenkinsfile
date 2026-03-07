// =============================================================================
// Esquire Frameworks — Jenkins CI/CD Pipeline (Kubernetes, Multi-Repo)
//
// Fully parameterized — deploys to ANY Linux host.
// Clones repos from mir0n-pro/aegisaosoft → builds Docker images → deploys to K8s.
//
// Repo layout in workspace:
//   $WORKSPACE/
//   ├── esquire.mainshell/   ← git repo 0 (React mainshell)
//   ├── esquire.services/    ← git repo 1 (backend Java microservices)
//   ├── esquire.explorer/    ← git repo 2 (Angular frontend)
//   ├── esquire.db.seed/     ← git repo 3 (DB seed scripts)
//   └── deploy/              ← this repo (infra: k8s, compose, Jenkinsfile)
//
// Jenkins job: Pipeline → SCM → aegisaosoft/esquire.deploy
// =============================================================================

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 40, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    parameters {
        // ── Target host ───────────────────────────────────────────────────────
        string(name: 'DEPLOY_HOST', defaultValue: '192.168.1.104',
            description: 'Target host IP or hostname')
        string(name: 'DB_HOST', defaultValue: '',
            description: 'PostgreSQL host (defaults to DEPLOY_HOST if empty)')
        string(name: 'REGISTRY', defaultValue: '',
            description: 'Container registry (e.g. myregistry:5000). Empty = local images for minikube/microk8s/k3s')

        // ── Which repos to rebuild ────────────────────────────────────────────
        booleanParam(name: 'BUILD_MAINSHELL', defaultValue: true,
            description: 'Build React mainshell (esquire.mainshell)')
        booleanParam(name: 'BUILD_SERVICES', defaultValue: false,
            description: 'Build backend microservices (bizTree, enyMan, pacMan, keySmith, gateway)')
        booleanParam(name: 'BUILD_FRONTEND', defaultValue: false,
            description: 'Build Angular frontend')
        booleanParam(name: 'RUN_DB_SEED',    defaultValue: false,
            description: 'Run DB seed scripts (esquire.db.seed)')
        booleanParam(name: 'FULL_RESET',     defaultValue: false,
            description: 'Delete K8s namespace and redeploy from scratch (WARNING: destroys Keycloak data)')
        booleanParam(name: 'GENERATE_CERTS', defaultValue: false,
            description: 'Generate fresh TLS certificate for DEPLOY_HOST (otherwise uses pre-built mkcert cert)')
        booleanParam(name: 'ENABLE_DASHBOARD', defaultValue: true,
            description: 'Enable Minikube Dashboard (accessible at http://DEPLOY_HOST:30900)')

        // ── Branch overrides ──────────────────────────────────────────────────
        string(name: 'BRANCH_MAINSHELL', defaultValue: 'develop', description: 'Branch for esquire.mainshell')
        string(name: 'BRANCH_SERVICES',  defaultValue: 'develop', description: 'Branch for esquire.services')
        string(name: 'BRANCH_EXPLORER',  defaultValue: 'develop', description: 'Branch for esquire.explorer')
        string(name: 'BRANCH_DB_SEED',   defaultValue: 'develop', description: 'Branch for esquire.db.seed')
    }

    environment {
        // GitHub — services from mir0n-pro, mainshell from aegisaosoft
        GITHUB_SERVICES_ORG   = 'mir0n-pro'
        GITHUB_MAINSHELL_ORG  = 'aegisaosoft'

        // Paths on server
        PROJECT_DIR = '/opt/esquire'
        K8S_DIR     = '/opt/esquire/deploy/k8s'
        IMPORT_DIR  = '/opt/esquire/deploy/import'
        ENV_FILE    = '/opt/esquire/deploy/.env'

        // K8s
        NAMESPACE = 'esquire'
        IMAGE_TAG = 'latest'
    }

    stages {

        // ── 1. Checkout all repos in parallel ───────────────────────────────
        stage('Checkout') {
            parallel {
                stage('deploy (this repo)') {
                    steps {
                        checkout scm
                        script {
                            env.GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                        }
                        echo "Deploy repo commit: ${env.GIT_COMMIT_SHORT}"
                    }
                }
                stage('esquire.mainshell') {
                    steps {
                        dir('esquire.mainshell') {
                            git url: "https://github.com/${GITHUB_MAINSHELL_ORG}/esquire.mainshell.git",
                                branch: "${params.BRANCH_MAINSHELL}"
                        }
                    }
                }
                stage('esquire.services') {
                    steps {
                        dir('esquire.services') {
                            git url: "https://github.com/${GITHUB_SERVICES_ORG}/esquire.services.git",
                                branch: "${params.BRANCH_SERVICES}"
                        }
                    }
                }
                stage('esquire.explorer') {
                    steps {
                        dir('esquire.explorer') {
                            git url: "https://github.com/${GITHUB_SERVICES_ORG}/esquire.explorer.git",
                                branch: "${params.BRANCH_EXPLORER}"
                        }
                    }
                }
                stage('esquire.db.seed') {
                    steps {
                        dir('esquire.db.seed') {
                            git url: "https://github.com/${GITHUB_SERVICES_ORG}/esquire.db.seed.git",
                                branch: "${params.BRANCH_DB_SEED}"
                        }
                    }
                }
            }
        }

        // ── 2. Resolve host IPs ────────────────────────────────────────────
        stage('Resolve Hosts') {
            steps {
                script {
                    // Auto-detect host IP if not provided
                    if (params.DEPLOY_HOST?.trim()) {
                        env.RESOLVED_HOST = params.DEPLOY_HOST.trim()
                    } else {
                        // Detect real host IP (works inside Docker container too)
                        env.RESOLVED_HOST = sh(
                            script: """
                                if [ -f /.dockerenv ]; then
                                    docker run --rm --net=host busybox sh -c "ip route get 1 2>/dev/null | sed 's/.*src \\([^ ]*\\).*/\\1/'"
                                else
                                    hostname -I | awk '{print \$1}'
                                fi
                            """,
                            returnStdout: true
                        ).trim()
                    }
                    // DB host defaults to deploy host
                    env.RESOLVED_DB_HOST = params.DB_HOST?.trim() ? params.DB_HOST.trim() : env.RESOLVED_HOST

                    echo "Deploy host: ${env.RESOLVED_HOST}"
                    echo "DB host:     ${env.RESOLVED_DB_HOST}"
                }
            }
        }

        // ── 3. Prepare server ───────────────────────────────────────────────
        stage('Prepare') {
            steps {
                sh """
                    mkdir -p ${PROJECT_DIR}

                    docker ps > /dev/null 2>&1 || { echo "Docker is not running!"; exit 1; }
                    kubectl version --client > /dev/null 2>&1 || { echo "kubectl not found!"; exit 1; }

                    if command -v microk8s > /dev/null 2>&1; then
                        echo "microk8s" > ${PROJECT_DIR}/.k8s-runtime
                    elif command -v k3s > /dev/null 2>&1; then
                        echo "k3s" > ${PROJECT_DIR}/.k8s-runtime
                    elif command -v minikube > /dev/null 2>&1 || docker ps --format '{{.Names}}' | grep -q '^minikube\$'; then
                        echo "minikube" > ${PROJECT_DIR}/.k8s-runtime
                    else
                        echo "generic" > ${PROJECT_DIR}/.k8s-runtime
                    fi
                    echo "K8s runtime: \$(cat ${PROJECT_DIR}/.k8s-runtime)"
                """
            }
        }

        // ── 4. Sync to /opt/esquire ─────────────────────────────────────────
        stage('Sync') {
            steps {
                sh """
                    # esquire.mainshell — overwrite only
                    mkdir -p ${PROJECT_DIR}/esquire.mainshell
                    tar cf - --exclude='.git' --exclude='node_modules' --exclude='.vscode' \
                        -C esquire.mainshell . | tar xf - -C ${PROJECT_DIR}/esquire.mainshell/

                    # esquire.services — overwrite only (target/ is root-owned from Maven, excluded anyway)
                    mkdir -p ${PROJECT_DIR}/esquire.services
                    tar cf - --exclude='.git' --exclude='target' --exclude='.idea' --exclude='*.iml' \
                        -C esquire.services . | tar xf - -C ${PROJECT_DIR}/esquire.services/

                    # esquire.explorer — overwrite only
                    mkdir -p ${PROJECT_DIR}/esquire.explorer
                    tar cf - --exclude='.git' --exclude='node_modules' --exclude='.angular' \
                        -C esquire.explorer . | tar xf - -C ${PROJECT_DIR}/esquire.explorer/

                    # esquire.db.seed — overwrite only
                    mkdir -p ${PROJECT_DIR}/esquire.db.seed
                    tar cf - --exclude='.git' \
                        -C esquire.db.seed . | tar xf - -C ${PROJECT_DIR}/esquire.db.seed/

                    # deploy — clean copy (needs fresh __DEPLOY_HOST__ placeholders)
                    rm -rf ${PROJECT_DIR}/deploy
                    mkdir -p ${PROJECT_DIR}/deploy
                    tar cf - --exclude='.git' --exclude='Jenkinsfile' \
                        -C deploy . | tar xf - -C ${PROJECT_DIR}/deploy/

                    # Fix Windows line endings in shell scripts
                    find ${PROJECT_DIR} -name '*.sh' -exec sed -i 's/\\r\$//' {} +
                """
            }
        }

        // ── 5. Inject host IPs into configs ─────────────────────────────────
        stage('Configure') {
            steps {
                echo "Injecting DEPLOY_HOST=${env.RESOLVED_HOST}, DB_HOST=${env.RESOLVED_DB_HOST}..."
                sh """
                    # .env — set DEPLOY_HOST
                    sed -i 's|^DEPLOY_HOST=.*|DEPLOY_HOST=${env.RESOLVED_HOST}|' ${ENV_FILE}

                    # K8s manifests — replace __DEPLOY_HOST__ and __DB_HOST__ placeholders
                    sed -i 's|__DEPLOY_HOST__|${env.RESOLVED_HOST}|g' ${K8S_DIR}/configmap.yaml
                    sed -i 's|__DEPLOY_HOST__|${env.RESOLVED_HOST}|g' ${K8S_DIR}/gateway.yaml
                    sed -i 's|__DEPLOY_HOST__|${env.RESOLVED_HOST}|g' ${K8S_DIR}/frontend.yaml
                    sed -i 's|__DEPLOY_HOST__|${env.RESOLVED_HOST}|g' ${K8S_DIR}/mainshell.yaml
                    sed -i 's|__DB_HOST__|${env.RESOLVED_DB_HOST}|g'  ${K8S_DIR}/postgres-endpoint.yaml

                    # Keycloak realm import — replace __DEPLOY_HOST__ in redirectUris/webOrigins
                    sed -i 's|__DEPLOY_HOST__|${env.RESOLVED_HOST}|g' ${IMPORT_DIR}/esquire.json

                """

                // TLS certificate: generate or reuse from persistent store
                script {
                    def certDir = "${PROJECT_DIR}/certs"
                    def proxyDir = "${PROJECT_DIR}/deploy/proxy"
                    if (params.GENERATE_CERTS) {
                        echo "Generating TLS certificate for ${env.RESOLVED_HOST}..."
                        sh """
                            mkdir -p ${certDir}
                            openssl req -x509 -nodes -days 825 \
                                -newkey rsa:2048 \
                                -keyout ${certDir}/esquire.key \
                                -out    ${certDir}/esquire.crt \
                                -subj   "/CN=${env.RESOLVED_HOST}/O=Esquire/C=US" \
                                -addext "subjectAltName=DNS:localhost,IP:${env.RESOLVED_HOST},IP:127.0.0.1"
                            cp ${certDir}/esquire.crt ${certDir}/esquire.key ${proxyDir}/
                            echo "Certificate generated and saved for IP: ${env.RESOLVED_HOST}"
                        """
                    } else if (sh(script: "test -f ${certDir}/esquire.crt && test -f ${certDir}/esquire.key", returnStatus: true) == 0) {
                        echo "Reusing previously generated certificate from ${certDir}..."
                        sh "cp ${certDir}/esquire.crt ${certDir}/esquire.key ${proxyDir}/"
                    } else {
                        echo "Using pre-built mkcert certificate from repo."
                    }
                }
            }
        }

        // ── 6. Maven pre-build (if Dockerfiles are NOT multi-stage) ────────
        //    Auto-detects: if Dockerfile has "AS builder" → multi-stage, skip.
        //    Otherwise → run Maven in Docker container to produce JARs first.
        stage('Maven Build') {
            when {
                expression { return params.BUILD_SERVICES }
            }
            steps {
                script {
                    def isMultiStage = sh(
                        script: "grep -qi 'AS builder' ${PROJECT_DIR}/esquire.services/bizTree/Dockerfile && echo true || echo false",
                        returnStdout: true
                    ).trim()

                    if (isMultiStage == 'true') {
                        echo "Multi-stage Dockerfiles detected — skipping Maven pre-build."
                        env.DOCKERFILE_MODE = 'multistage'
                    } else {
                        echo "Simple Dockerfiles detected — running Maven build in Docker..."
                        env.DOCKERFILE_MODE = 'simple'
                        sh """
                            docker run --rm \
                                -v ${PROJECT_DIR}/esquire.services:/build \
                                -v esquire-maven-cache:/root/.m2 \
                                -w /build \
                                maven:3-eclipse-temurin-21 \
                                mvn clean package -DskipTests -q

                            # Fix ownership: Maven runs as root, but Jenkins needs to manage these files
                            docker run --rm \
                                -v ${PROJECT_DIR}/esquire.services:/build \
                                busybox chown -R \$(id -u):\$(id -g) /build
                        """
                        echo "Maven build complete. JARs ready in target/ directories."
                    }
                }
            }
        }

        // ── 7. Build Docker images ──────────────────────────────────────────
        //    Simple Dockerfiles:    context = service subdir  (COPY target/*.jar)
        //    Multi-stage Dockerfiles: context = repo root     (needs parent pom + common)
        stage('Build Images') {
            parallel {
                stage('biztree') {
                    when { expression { return params.BUILD_SERVICES } }
                    steps {
                        script {
                            def ctx = (env.DOCKERFILE_MODE == 'multistage')
                                ? "${PROJECT_DIR}/esquire.services"
                                : "${PROJECT_DIR}/esquire.services/bizTree"
                            sh "docker build -t esquire/biztree:${IMAGE_TAG} -f ${PROJECT_DIR}/esquire.services/bizTree/Dockerfile ${ctx}"
                        }
                    }
                }
                stage('enyman') {
                    when { expression { return params.BUILD_SERVICES } }
                    steps {
                        script {
                            def ctx = (env.DOCKERFILE_MODE == 'multistage')
                                ? "${PROJECT_DIR}/esquire.services"
                                : "${PROJECT_DIR}/esquire.services/enyMan"
                            sh "docker build -t esquire/enyman:${IMAGE_TAG} -f ${PROJECT_DIR}/esquire.services/enyMan/Dockerfile ${ctx}"
                        }
                    }
                }
                stage('pacman') {
                    when { expression { return params.BUILD_SERVICES } }
                    steps {
                        script {
                            def ctx = (env.DOCKERFILE_MODE == 'multistage')
                                ? "${PROJECT_DIR}/esquire.services"
                                : "${PROJECT_DIR}/esquire.services/pacMan"
                            sh "docker build -t esquire/pacman:${IMAGE_TAG} -f ${PROJECT_DIR}/esquire.services/pacMan/Dockerfile ${ctx}"
                        }
                    }
                }
                stage('keysmith') {
                    when { expression { return params.BUILD_SERVICES } }
                    steps {
                        script {
                            def ctx = (env.DOCKERFILE_MODE == 'multistage')
                                ? "${PROJECT_DIR}/esquire.services"
                                : "${PROJECT_DIR}/esquire.services/keySmith"
                            sh "docker build -t esquire/keysmith:${IMAGE_TAG} -f ${PROJECT_DIR}/esquire.services/keySmith/Dockerfile ${ctx}"
                        }
                    }
                }
                stage('gateway') {
                    when { expression { return params.BUILD_SERVICES } }
                    steps {
                        script {
                            def ctx = (env.DOCKERFILE_MODE == 'multistage')
                                ? "${PROJECT_DIR}/esquire.services"
                                : "${PROJECT_DIR}/esquire.services/gateway"
                            sh "docker build -t esquire/gateway:${IMAGE_TAG} -f ${PROJECT_DIR}/esquire.services/gateway/Dockerfile ${ctx}"
                        }
                    }
                }
                stage('mainshell') {
                    when { expression { return params.BUILD_MAINSHELL } }
                    steps {
                        sh "docker build --no-cache -t esquire/mainshell:${IMAGE_TAG} ${PROJECT_DIR}/esquire.mainshell"
                    }
                }
                stage('frontend') {
                    when { expression { return params.BUILD_FRONTEND } }
                    steps {
                        sh "docker build --no-cache -t esquire/frontend:${IMAGE_TAG} -f ${PROJECT_DIR}/esquire.explorer/frontend/Dockerfile ${PROJECT_DIR}/esquire.explorer/frontend"
                    }
                }
                stage('proxy') {
                    steps {
                        sh "docker build -t esquire/proxy:${IMAGE_TAG} ${PROJECT_DIR}/deploy/proxy"
                    }
                }
            }
        }

        // ── 7. Import images into K8s runtime ───────────────────────────────
        stage('Import Images') {
            when {
                expression { return params.BUILD_MAINSHELL || params.BUILD_SERVICES || params.BUILD_FRONTEND }
            }
            steps {
                sh '''
                    RUNTIME=$(cat /opt/esquire/.k8s-runtime)

                    IMAGES="esquire/proxy"
                    if [ "$BUILD_MAINSHELL" = "true" ]; then
                        IMAGES="$IMAGES esquire/mainshell"
                    fi
                    if [ "$BUILD_SERVICES" = "true" ]; then
                        IMAGES="$IMAGES esquire/biztree esquire/enyman esquire/pacman esquire/keysmith esquire/gateway"
                    fi
                    if [ "$BUILD_FRONTEND" = "true" ]; then
                        IMAGES="$IMAGES esquire/frontend"
                    fi

                    case "$RUNTIME" in
                        microk8s)
                            for img in $IMAGES; do
                                echo "Importing $img into microk8s..."
                                docker save $img:latest | microk8s ctr image import -
                            done
                            ;;
                        k3s)
                            for img in $IMAGES; do
                                echo "Importing $img into k3s..."
                                docker save $img:latest | sudo k3s ctr images import -
                            done
                            ;;
                        minikube)
                            # Minikube with Docker driver: load into minikube's Docker daemon
                            # (NOT containerd — kubelet uses Docker runtime, not CRI)
                            for img in $IMAGES; do
                                echo "Loading $img into minikube Docker..."
                                docker save $img:latest | docker exec -i minikube docker load
                            done
                            ;;
                        *)
                            if [ -n "$REGISTRY" ]; then
                                echo "Full K8s — pushing images to registry $REGISTRY..."
                                for img in $IMAGES; do
                                    docker tag $img:latest $REGISTRY/$img:latest
                                    docker push $REGISTRY/$img:latest
                                done
                            else
                                echo "Generic K8s — images accessible via Docker daemon."
                            fi
                            ;;
                    esac
                '''
            }
        }

        // ── 8. DB Seed (optional) ───────────────────────────────────────────
        stage('DB Seed') {
            when {
                expression { return params.RUN_DB_SEED }
            }
            steps {
                echo "Running database seed scripts..."
                sh """
                    cd ${PROJECT_DIR}/esquire.db.seed/postgres

                    # Read DB credentials from .env
                    source ${ENV_FILE}
                    export PGHOST=${env.RESOLVED_DB_HOST}
                    export PGPORT=5432
                    export PGDATABASE=\$POSTGRES_DB
                    export PGUSER=\$POSTGRES_USER
                    export PGPASSWORD=\$POSTGRES_PASSWORD

                    for sql in \$(ls -1 *.sql 2>/dev/null | sort); do
                        echo "Executing \$sql..."
                        psql -f \$sql
                    done
                """
            }
        }

        // ── 9. Full reset (optional) ────────────────────────────────────────
        stage('Full Reset') {
            when {
                expression { return params.FULL_RESET }
            }
            steps {
                echo "Deleting namespace ${NAMESPACE}..."
                sh """
                    kubectl delete namespace ${NAMESPACE} --ignore-not-found --timeout=60s
                    while kubectl get namespace ${NAMESPACE} > /dev/null 2>&1; do
                        echo "Waiting for namespace to terminate..."
                        sleep 3
                    done
                """
            }
        }

        // ── 10. Apply K8s manifests ─────────────────────────────────────────
        stage('Apply Manifests') {
            steps {
                echo "Applying Kubernetes manifests..."
                sh """
                    kubectl apply -f ${K8S_DIR}/namespace.yaml
                    kubectl apply -f ${K8S_DIR}/configmap.yaml
                    kubectl apply -f ${K8S_DIR}/secret.yaml
                    kubectl apply -f ${K8S_DIR}/postgres-endpoint.yaml

                    kubectl create configmap keycloak-realm \
                        --from-file=realm.json=${IMPORT_DIR}/esquire.json \
                        --namespace=${NAMESPACE} \
                        --dry-run=client -o yaml | kubectl apply -f -

                    kubectl apply -f ${K8S_DIR}/keycloak.yaml
                    kubectl apply -f ${K8S_DIR}/biztree.yaml
                    kubectl apply -f ${K8S_DIR}/enyman.yaml
                    kubectl apply -f ${K8S_DIR}/pacman.yaml
                    kubectl apply -f ${K8S_DIR}/keysmith.yaml
                    kubectl apply -f ${K8S_DIR}/gateway.yaml
                    kubectl apply -f ${K8S_DIR}/frontend.yaml
                    kubectl apply -f ${K8S_DIR}/mainshell.yaml
                    kubectl apply -f ${K8S_DIR}/proxy.yaml
                """
            }
        }

        // ── 11. Rolling restart ─────────────────────────────────────────────
        stage('Rolling Restart') {
            steps {
                script {
                    def restarts = []
                    if (params.BUILD_SERVICES) {
                        restarts += ['biztree', 'enyman', 'pacman', 'keysmith', 'gateway']
                    }
                    if (params.BUILD_MAINSHELL) {
                        restarts += ['mainshell']
                    }
                    if (params.BUILD_FRONTEND) {
                        restarts += ['frontend']
                    }
                    restarts += ['proxy']
                    if (restarts) {
                        def names = restarts.join(' ')
                        sh """
                            for deploy in ${names}; do
                                kubectl rollout restart deployment/\$deploy -n ${NAMESPACE}
                            done
                        """
                    } else {
                        echo "No images were rebuilt — skipping restart."
                    }
                }
            }
        }

        // ── 12. Wait for rollouts ───────────────────────────────────────────
        stage('Wait for Rollouts') {
            steps {
                echo "Waiting for Keycloak..."
                sh "kubectl rollout status deployment/keycloak -n ${NAMESPACE} --timeout=180s"

                echo "Waiting for backend services..."
                sh """
                    kubectl rollout status deployment/biztree  -n ${NAMESPACE} --timeout=120s &
                    kubectl rollout status deployment/enyman   -n ${NAMESPACE} --timeout=120s &
                    kubectl rollout status deployment/pacman   -n ${NAMESPACE} --timeout=120s &
                    kubectl rollout status deployment/keysmith -n ${NAMESPACE} --timeout=120s &
                    wait
                """

                echo "Waiting for Gateway..."
                sh "kubectl rollout status deployment/gateway -n ${NAMESPACE} --timeout=120s"

                echo "Waiting for Frontend..."
                sh "kubectl rollout status deployment/frontend -n ${NAMESPACE} --timeout=180s"

                echo "Waiting for Mainshell..."
                sh "kubectl rollout status deployment/mainshell -n ${NAMESPACE} --timeout=180s"

                echo "Waiting for HTTPS Proxy..."
                sh "kubectl rollout status deployment/proxy -n ${NAMESPACE} --timeout=60s"
            }
        }

        // ── 13. Smoke test ──────────────────────────────────────────────────
        stage('Smoke Test') {
            steps {
                sh '''
                    # Get K8s node IP (works with minikube, microk8s, etc.)
                    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
                    echo "K8s node IP: $NODE_IP"

                    echo "Testing Gateway via NodePort :30000..."
                    STATUS=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 http://$NODE_IP:30000/actuator/health 2>/dev/null || echo "000")
                    if [ "$STATUS" = "200" ]; then
                        echo "Gateway -> 200 OK"
                    else
                        echo "Gateway -> $STATUS FAIL"
                        exit 1
                    fi

                    echo "Testing Frontend via NodePort :30200..."
                    STATUS=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 http://$NODE_IP:30200 2>/dev/null || echo "000")
                    if [ "$STATUS" = "200" ]; then
                        echo "Frontend -> 200 OK"
                    else
                        echo "Frontend -> $STATUS (may still be compiling)"
                    fi

                    echo "Testing Mainshell via NodePort :30300..."
                    STATUS=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 http://$NODE_IP:30300 2>/dev/null || echo "000")
                    if [ "$STATUS" = "200" ]; then
                        echo "Mainshell -> 200 OK"
                    else
                        echo "Mainshell -> $STATUS (may still be starting)"
                    fi

                    echo "Testing Keycloak via NodePort :30080..."
                    STATUS=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 http://$NODE_IP:30080/health/ready 2>/dev/null || echo "000")
                    if [ "$STATUS" = "200" ]; then
                        echo "Keycloak -> 200 OK"
                    else
                        echo "Keycloak -> $STATUS"
                    fi
                '''

                sh """
                    echo ""
                    echo "========================================"
                    echo "  Pod Status"
                    echo "========================================"
                    kubectl get pods -n ${NAMESPACE} -o wide
                    echo ""
                    echo "========================================"
                    echo "  Services"
                    echo "========================================"
                    kubectl get svc -n ${NAMESPACE}
                    echo ""
                    echo "========================================"
                    echo "  Deployment Complete!"
                    echo "========================================"
                    echo "  Mainshell (HTTPS): https://${env.RESOLVED_HOST}:30543"
                    echo "  Frontend  (HTTPS): https://${env.RESOLVED_HOST}:30443"
                    echo "  Gateway   (HTTPS): https://${env.RESOLVED_HOST}:30343"
                    echo "  Keycloak  (HTTPS): https://${env.RESOLVED_HOST}:30843"
                    echo ""
                    echo "  Mainshell (HTTP):  http://${env.RESOLVED_HOST}:30300"
                    echo "  Frontend  (HTTP):  http://${env.RESOLVED_HOST}:30200"
                    echo "  Gateway   (HTTP):  http://${env.RESOLVED_HOST}:30000"
                    echo "  Keycloak  (HTTP):  http://${env.RESOLVED_HOST}:30080"
                    echo "========================================"
                """
            }
        }

        // ── 14. Port forwarding (minikube only) ──────────────────────────────
        //    Minikube (Docker driver) exposes NodePorts only on its container IP
        //    (e.g. 192.168.49.2), not on the host. This stage runs a socat
        //    forwarder on the host network so all NodePorts are reachable at
        //    the host IP from browsers on the local network.
        stage('Port Forwarding') {
            steps {
                script {
                    def runtime = sh(script: "cat ${PROJECT_DIR}/.k8s-runtime", returnStdout: true).trim()
                    if (runtime == 'minikube') {
                        env.MINIKUBE_NODE_IP = sh(
                            script: "kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}'",
                            returnStdout: true
                        ).trim()
                        echo "Minikube node IP: ${env.MINIKUBE_NODE_IP}"
                        echo "Setting up port forwarding: host:30xxx → ${env.MINIKUBE_NODE_IP}:30xxx"

                        // Write forwarding script to /opt/esquire/ (shared host path)
                        sh """
                            cat > ${PROJECT_DIR}/port-forward.sh << 'PFEOF'
#!/bin/sh
set -e
apk add --no-cache socat >/dev/null 2>&1
for PORT in 30000 30080 30200 30300 30443 30343 30543 30843; do
    socat TCP-LISTEN:\$PORT,fork,reuseaddr TCP:\$TARGET_IP:\$PORT &
    echo "Forwarding 0.0.0.0:\$PORT -> \$TARGET_IP:\$PORT"
done
echo "All port forwards active. Waiting..."
wait
PFEOF
                            chmod +x ${PROJECT_DIR}/port-forward.sh
                        """

                        sh '''
                            # Stop any existing forwarder
                            docker rm -f esquire-port-forward 2>/dev/null || true

                            # Start socat forwarder with host networking
                            docker run -d --name esquire-port-forward \
                                --net=host \
                                --restart=unless-stopped \
                                -e TARGET_IP="$MINIKUBE_NODE_IP" \
                                -v /opt/esquire/port-forward.sh:/forward.sh:ro \
                                alpine sh /forward.sh

                            # Wait for startup and verify
                            sleep 3
                            if docker ps --filter name=esquire-port-forward --format '{{.Status}}' | grep -q 'Up'; then
                                echo "Port forwarding container is running"
                                docker logs esquire-port-forward 2>&1
                            else
                                echo "WARNING: Port forwarding container may have failed:"
                                docker logs esquire-port-forward 2>&1 || true
                            fi
                        '''

                        echo "URLs now accessible at host IP:"
                        echo "  Mainshell (HTTPS): https://${env.RESOLVED_HOST}:30543"
                        echo "  Frontend  (HTTPS): https://${env.RESOLVED_HOST}:30443"
                        echo "  Gateway   (HTTPS): https://${env.RESOLVED_HOST}:30343"
                        echo "  Keycloak  (HTTPS): https://${env.RESOLVED_HOST}:30843"
                    } else {
                        echo "Runtime: ${runtime} — NodePorts are directly accessible, no forwarding needed."
                    }
                }
            }
        }

        // ── 15. Minikube Dashboard (optional) ────────────────────────────────
        //    Enables the K8s dashboard addon and exposes it via NodePort 30900.
        //    For minikube: also adds the port to socat forwarder.
        stage('Dashboard') {
            when {
                expression { return params.ENABLE_DASHBOARD }
            }
            steps {
                script {
                    def runtime = sh(script: "cat ${PROJECT_DIR}/.k8s-runtime", returnStdout: true).trim()

                    echo "Enabling Kubernetes Dashboard..."
                    sh """
                        minikube addons enable dashboard 2>/dev/null || \
                            docker exec minikube minikube addons enable dashboard 2>/dev/null || \
                            kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml || true
                        minikube addons enable metrics-server 2>/dev/null || \
                            docker exec minikube minikube addons enable metrics-server 2>/dev/null || true
                    """

                    // Wait for dashboard pod to be ready
                    sh """
                        kubectl rollout status deployment/kubernetes-dashboard \
                            -n kubernetes-dashboard --timeout=90s || true
                    """

                    // Patch dashboard service to NodePort 30900
                    sh '''
                        kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard \
                            -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8443,"nodePort":30900}]}}' \
                            2>/dev/null || \
                        kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard \
                            -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":9090,"nodePort":30900}]}}' \
                            2>/dev/null || true
                    '''

                    // For minikube: add port 30900 to socat forwarder
                    if (runtime == 'minikube' && env.MINIKUBE_NODE_IP) {
                        sh """
                            docker exec -d esquire-port-forward \
                                socat TCP-LISTEN:30900,fork,reuseaddr TCP:${env.MINIKUBE_NODE_IP}:30900 \
                                2>/dev/null || true
                        """
                    }

                    echo "Dashboard: http://${env.RESOLVED_HOST}:30900"
                }
            }
        }
    }

    post {
        success {
            echo "Esquire deployed to Kubernetes on ${env.RESOLVED_HOST} (commit: ${env.GIT_COMMIT_SHORT})"
        }
        failure {
            echo "Deploy failed! Collecting diagnostics..."
            sh """
                echo "=== Pod status ==="
                timeout 15 kubectl get pods -n ${NAMESPACE} -o wide 2>/dev/null || true

                echo ""
                echo "=== Events (last 20) ==="
                timeout 15 kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true

                echo ""
                echo "=== Logs from non-Running pods ==="
                for pod in \$(timeout 10 kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -v Running | awk '{print \$1}'); do
                    echo "--- \$pod ---"
                    timeout 10 kubectl logs \$pod -n ${NAMESPACE} --tail=30 2>&1 || true
                    timeout 10 kubectl describe pod \$pod -n ${NAMESPACE} 2>&1 | tail -15 || true
                    echo ""
                done
            """
        }
        cleanup {
            cleanWs()
        }
    }
}
