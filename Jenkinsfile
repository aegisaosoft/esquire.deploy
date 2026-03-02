// =============================================================================
// Esquire Frameworks — Jenkins CI/CD Pipeline (Kubernetes, Multi-Repo)
//
// Fully parameterized — deploys to ANY Linux host.
// Clones 3 repos from mir0n-pro → builds Docker images → deploys to K8s.
//
// Repo layout in workspace:
//   $WORKSPACE/
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
        string(name: 'DEPLOY_HOST', defaultValue: '',
            description: 'Target host IP or hostname (auto-detected if empty)')
        string(name: 'DB_HOST', defaultValue: '',
            description: 'PostgreSQL host (defaults to DEPLOY_HOST if empty)')

        // ── Which repos to rebuild ────────────────────────────────────────────
        booleanParam(name: 'BUILD_SERVICES', defaultValue: true,
            description: 'Build backend microservices (bizTree, enyMan, pacMan, keySmith, gateway)')
        booleanParam(name: 'BUILD_FRONTEND', defaultValue: true,
            description: 'Build Angular frontend')
        booleanParam(name: 'RUN_DB_SEED',    defaultValue: false,
            description: 'Run DB seed scripts (esquire.db.seed)')
        booleanParam(name: 'FULL_RESET',     defaultValue: false,
            description: 'Delete K8s namespace and redeploy from scratch (WARNING: destroys Keycloak data)')

        // ── Branch overrides ──────────────────────────────────────────────────
        string(name: 'BRANCH_SERVICES', defaultValue: 'main', description: 'Branch for esquire.services')
        string(name: 'BRANCH_EXPLORER', defaultValue: 'main', description: 'Branch for esquire.explorer')
        string(name: 'BRANCH_DB_SEED',  defaultValue: 'main', description: 'Branch for esquire.db.seed')
    }

    environment {
        // GitHub — services from mir0n-pro, deploy repo from aegisaosoft
        GITHUB_SERVICES_ORG = 'mir0n-pro'

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
                        env.RESOLVED_HOST = sh(
                            script: "hostname -I | awk '{print \$1}'",
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

                    docker info > /dev/null 2>&1 || { echo "Docker is not running!"; exit 1; }
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
                    rsync -a --delete \
                        --exclude='target/' --exclude='.idea/' --exclude='*.iml' --exclude='.git/' \
                        esquire.services/ ${PROJECT_DIR}/esquire.services/

                    rsync -a --delete \
                        --exclude='node_modules/' --exclude='.angular/' --exclude='.git/' \
                        esquire.explorer/ ${PROJECT_DIR}/esquire.explorer/

                    rsync -a --delete --exclude='.git/' \
                        esquire.db.seed/ ${PROJECT_DIR}/esquire.db.seed/

                    rsync -a --delete --exclude='.git/' --exclude='Jenkinsfile' \
                        deploy/ ${PROJECT_DIR}/deploy/

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
                    sed -i 's|__DEPLOY_HOST__|${env.RESOLVED_HOST}|g' ${K8S_DIR}/keycloak.yaml
                    sed -i 's|__DB_HOST__|${env.RESOLVED_DB_HOST}|g'  ${K8S_DIR}/postgres-endpoint.yaml
                """
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
                stage('frontend') {
                    when { expression { return params.BUILD_FRONTEND } }
                    steps {
                        sh "docker build -t esquire/frontend:${IMAGE_TAG} -f ${PROJECT_DIR}/esquire.explorer/frontend/Dockerfile ${PROJECT_DIR}/esquire.explorer/frontend"
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
                expression { return params.BUILD_SERVICES || params.BUILD_FRONTEND }
            }
            steps {
                sh '''
                    RUNTIME=$(cat /opt/esquire/.k8s-runtime)

                    IMAGES="esquire/proxy"
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
                            if command -v minikube > /dev/null 2>&1; then
                                for img in $IMAGES; do
                                    echo "Loading $img into minikube..."
                                    minikube image load $img:latest
                                done
                            else
                                for img in $IMAGES; do
                                    echo "Loading $img into minikube (via docker)..."
                                    docker save $img:latest | docker exec -i minikube ctr -n k8s.io image import -
                                done
                            fi
                            ;;
                        *)
                            echo "Generic K8s — images accessible via Docker daemon."
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

                echo "Waiting for HTTPS Proxy..."
                sh "kubectl rollout status deployment/proxy -n ${NAMESPACE} --timeout=60s"
            }
        }

        // ── 13. Smoke test ──────────────────────────────────────────────────
        stage('Smoke Test') {
            steps {
                sh '''
                    echo "Testing Gateway via NodePort :30000..."
                    STATUS=$(curl -so /dev/null -w "%{http_code}" http://localhost:30000/actuator/health 2>/dev/null || echo "000")
                    if [ "$STATUS" = "200" ]; then
                        echo "Gateway -> 200 OK"
                    else
                        echo "Gateway -> $STATUS FAIL"
                        exit 1
                    fi

                    echo "Testing Frontend via NodePort :30200..."
                    STATUS=$(curl -so /dev/null -w "%{http_code}" http://localhost:30200 2>/dev/null || echo "000")
                    if [ "$STATUS" = "200" ]; then
                        echo "Frontend -> 200 OK"
                    else
                        echo "Frontend -> $STATUS (may still be compiling)"
                    fi

                    echo "Testing Keycloak via NodePort :30080..."
                    STATUS=$(curl -so /dev/null -w "%{http_code}" http://localhost:30080/health/ready 2>/dev/null || echo "000")
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
                    echo "  Frontend (HTTPS):  https://${env.RESOLVED_HOST}:30443"
                    echo "  Gateway  (HTTPS):  https://${env.RESOLVED_HOST}:30343"
                    echo "  Keycloak (HTTPS):  https://${env.RESOLVED_HOST}:30843"
                    echo ""
                    echo "  Frontend (HTTP):   http://${env.RESOLVED_HOST}:30200"
                    echo "  Gateway  (HTTP):   http://${env.RESOLVED_HOST}:30000"
                    echo "  Keycloak (HTTP):   http://${env.RESOLVED_HOST}:30080"
                    echo "========================================"
                """
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
                kubectl get pods -n ${NAMESPACE} -o wide 2>/dev/null || true

                echo ""
                echo "=== Events (last 20) ==="
                kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true

                echo ""
                echo "=== Logs from non-Running pods ==="
                for pod in \$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -v Running | awk '{print \$1}'); do
                    echo "--- \$pod ---"
                    kubectl logs \$pod -n ${NAMESPACE} --tail=30 2>&1 || true
                    kubectl describe pod \$pod -n ${NAMESPACE} 2>&1 | tail -15 || true
                    echo ""
                done
            """
        }
        cleanup {
            cleanWs()
        }
    }
}
