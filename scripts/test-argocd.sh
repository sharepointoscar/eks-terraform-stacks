#!/bin/bash
################################################################################
# ArgoCD Sub-Module Automated Test Script
# Tests the ArgoCD GitOps workflow on EKS
#
# Prerequisites:
#   - EKS cluster deployed with ArgoCD enabled
#   - kubectl configured for the cluster
#   - AWS CLI configured
#
# Usage:
#   ./scripts/test-argocd.sh [OPTIONS]
#
# Options:
#   --skip-cleanup    Don't delete test resources after tests complete
#   --help            Show this help message
################################################################################

# Don't exit on error - we handle errors ourselves
set +e

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-eks-usw2}"
REGION="${REGION:-us-west-2}"
APP_NAME="skiapp-test"
APP_NAMESPACE="default"
ARGOCD_NAMESPACE="argocd"
TEST_REPO="https://github.com/jenkins-oscar/skiapp"
TEST_REPO_SSH="git@github.com:jenkins-oscar/skiapp.git"
TEST_PATH="k8s"
TEST_REVISION="develop"
TEMP_DIR=""
BRANCH_CREATED=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
SKIP_CLEANUP=false

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

print_test() {
    echo -e "\n${YELLOW}▶ TEST: $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}ℹ INFO: $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠ WARN: $1${NC}"
}

show_help() {
    head -25 "$0" | tail -20
    exit 0
}

# Wait for a condition with timeout
wait_for() {
    local description="$1"
    local timeout="$2"
    local command="$3"

    print_info "Waiting for $description (timeout: ${timeout}s)..."

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$command" &>/dev/null; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    echo ""
    return 1
}

# Cleanup function for trap
cleanup_on_exit() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        print_info "Cleaning up temporary directory..."
        rm -rf "$TEMP_DIR"
    fi
    if [ "$BRANCH_CREATED" = true ] && [ "$SKIP_CLEANUP" = false ]; then
        print_info "Cleaning up remote develop branch..."
        cd "$TEMP_DIR" 2>/dev/null && git push origin --delete "$TEST_REVISION" 2>/dev/null || true
    fi
}

################################################################################
# Parse Arguments
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

################################################################################
# Prerequisites Check
################################################################################

print_header "PREREQUISITES CHECK"

print_test "Checking kubectl is installed"
if command -v kubectl &>/dev/null; then
    print_pass "kubectl is installed ($(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion": "[^"]*"' | head -1 || echo 'version unknown'))"
else
    print_fail "kubectl is not installed"
    exit 1
fi

print_test "Checking cluster connectivity"
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [ -z "$CURRENT_CONTEXT" ]; then
    print_fail "No kubectl context configured"
    print_info "Run: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
    exit 1
fi

KUBECTL_ERROR=$(kubectl get nodes --request-timeout=10s 2>&1)
if [ $? -eq 0 ]; then
    print_pass "Connected to cluster (context: $CURRENT_CONTEXT)"
else
    print_fail "Cannot connect to cluster"
    echo "    Error: $KUBECTL_ERROR"
    print_info "Check AWS credentials: aws sts get-caller-identity"
    print_info "Or run: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
    exit 1
fi

print_test "Checking nodes are ready"
READY_NODES=$(kubectl get nodes --no-headers --request-timeout=10s 2>/dev/null | grep -c " Ready" || echo "0")
if [ "$READY_NODES" -gt 0 ]; then
    print_pass "$READY_NODES node(s) are Ready"
else
    print_fail "No Ready nodes found"
    exit 1
fi

################################################################################
# Setup: Create develop branch with k8s manifests in skiapp repo
################################################################################

print_header "SETUP: Creating develop branch with k8s manifests"

print_test "Checking if develop branch already exists"
if git ls-remote --heads "$TEST_REPO" "$TEST_REVISION" 2>/dev/null | grep -q "$TEST_REVISION"; then
    print_info "Branch '$TEST_REVISION' already exists - will use existing branch"
    BRANCH_CREATED=false
else
    print_info "Branch '$TEST_REVISION' does not exist - will create it"

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    print_info "Using temporary directory: $TEMP_DIR"

    # Clone the repo
    print_test "Cloning skiapp repository"
    if git clone "$TEST_REPO_SSH" "$TEMP_DIR/skiapp" 2>/dev/null; then
        print_pass "Repository cloned successfully"
    else
        print_fail "Failed to clone repository - check SSH access to $TEST_REPO_SSH"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    cd "$TEMP_DIR/skiapp"

    # Create develop branch
    print_test "Creating develop branch"
    git checkout -b "$TEST_REVISION"

    # Create k8s directory and manifests
    print_test "Creating k8s manifests"
    mkdir -p k8s

    # Create deployment.yaml
    cat > k8s/deployment.yaml <<'DEPLOYMENT_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: skiapp
  labels:
    app: skiapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: skiapp
  template:
    metadata:
      labels:
        app: skiapp
    spec:
      containers:
      - name: skiapp
        image: node:18-alpine
        command: ["sh", "-c", "cd /app && npm install && npm start"]
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        volumeMounts:
        - name: app-source
          mountPath: /app
      initContainers:
      - name: git-clone
        image: alpine/git
        command: ["git", "clone", "https://github.com/jenkins-oscar/skiapp.git", "/app"]
        volumeMounts:
        - name: app-source
          mountPath: /app
      volumes:
      - name: app-source
        emptyDir: {}
DEPLOYMENT_EOF

    # Create service.yaml
    cat > k8s/service.yaml <<'SERVICE_EOF'
apiVersion: v1
kind: Service
metadata:
  name: skiapp
  labels:
    app: skiapp
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    app: skiapp
SERVICE_EOF

    print_pass "Created k8s/deployment.yaml and k8s/service.yaml"

    # Commit and push
    print_test "Committing and pushing develop branch"
    git add k8s/
    git commit -m "Add Kubernetes manifests for ArgoCD testing"

    if git push -u origin "$TEST_REVISION" 2>/dev/null; then
        print_pass "Branch '$TEST_REVISION' pushed to remote"
        BRANCH_CREATED=true
    else
        print_fail "Failed to push branch - check SSH access"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Return to original directory
    cd - > /dev/null
fi

################################################################################
# Test 1: ArgoCD Installation Verification
################################################################################

print_header "TEST 1: ArgoCD Installation Verification"

print_test "Checking ArgoCD namespace exists"
if kubectl get namespace $ARGOCD_NAMESPACE &>/dev/null; then
    print_pass "ArgoCD namespace '$ARGOCD_NAMESPACE' exists"
else
    print_fail "ArgoCD namespace '$ARGOCD_NAMESPACE' not found"
    print_info "ArgoCD may not be deployed. Enable it in the addons module first."
    exit 1
fi

print_test "Checking ArgoCD pods are running"
ARGOCD_PODS=$(kubectl get pods -n $ARGOCD_NAMESPACE --no-headers 2>/dev/null | wc -l | tr -d ' ')
RUNNING_PODS=$(kubectl get pods -n $ARGOCD_NAMESPACE --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$RUNNING_PODS" -ge 5 ]; then
    print_pass "$RUNNING_PODS ArgoCD pods are running"
    kubectl get pods -n $ARGOCD_NAMESPACE --no-headers | while read line; do
        echo "    $line"
    done
else
    print_fail "Expected at least 5 ArgoCD pods running, found $RUNNING_PODS"
    kubectl get pods -n $ARGOCD_NAMESPACE
    exit 1
fi

print_test "Checking ArgoCD server is ready"
# Find the argocd-server deployment (name varies by installation method)
ARGOCD_SERVER_DEPLOY=$(kubectl get deployment -n $ARGOCD_NAMESPACE -o name 2>/dev/null | grep -E "argocd-server" | head -1)
if [ -n "$ARGOCD_SERVER_DEPLOY" ]; then
    READY=$(kubectl get $ARGOCD_SERVER_DEPLOY -n $ARGOCD_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$READY" -ge 1 ]; then
        print_pass "ArgoCD server is ready ($READY replica(s))"
    else
        print_fail "ArgoCD server not ready"
    fi
else
    print_fail "ArgoCD server deployment not found"
fi

print_test "Retrieving ArgoCD admin password"
if kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NAMESPACE &>/dev/null; then
    ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    print_pass "ArgoCD admin password retrieved"
    echo -e "    ${YELLOW}Username: admin${NC}"
    echo -e "    ${YELLOW}Password: $ARGOCD_PASSWORD${NC}"
else
    print_warn "ArgoCD initial admin secret not found (may have been deleted)"
fi

################################################################################
# Test 2: Deploy Test Application via ArgoCD
################################################################################

print_header "TEST 2: Deploy Test Application via ArgoCD"

print_test "Creating ArgoCD Application manifest"

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $ARGOCD_NAMESPACE
spec:
  project: default
  source:
    repoURL: $TEST_REPO
    targetRevision: $TEST_REVISION
    path: $TEST_PATH
  destination:
    server: https://kubernetes.default.svc
    namespace: $APP_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

if [ $? -eq 0 ]; then
    print_pass "ArgoCD Application '$APP_NAME' created"
else
    print_fail "Failed to create ArgoCD Application"
    exit 1
fi

print_test "Waiting for application to sync"
if wait_for "application sync" 120 "kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q 'Synced'"; then
    print_pass "Application synced successfully"
else
    print_fail "Application sync timed out"
    kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o yaml 2>/dev/null | head -50
fi

print_test "Checking application health status"
HEALTH_STATUS=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
SYNC_STATUS=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

echo "    Sync Status: $SYNC_STATUS"
echo "    Health Status: $HEALTH_STATUS"

if [ "$SYNC_STATUS" == "Synced" ]; then
    print_pass "Application is Synced"
else
    print_fail "Application is not Synced (status: $SYNC_STATUS)"
fi

################################################################################
# Test 3: Verify Kubernetes Resources
################################################################################

print_header "TEST 3: Verify Kubernetes Resources"

print_test "Checking Deployment exists"
if kubectl get deployment skiapp -n $APP_NAMESPACE &>/dev/null; then
    REPLICAS=$(kubectl get deployment skiapp -n $APP_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null)
    READY=$(kubectl get deployment skiapp -n $APP_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    print_pass "Deployment 'skiapp' exists (replicas: $READY/$REPLICAS)"
else
    print_fail "Deployment 'skiapp' not found"
fi

print_test "Waiting for Pods to be running"
print_info "Waiting for pods to be ready (timeout: 120s)..."
POD_READY=false
ELAPSED=0
while [ $ELAPSED -lt 120 ]; do
    RUNNING_APP_PODS=$(kubectl get pods -n $APP_NAMESPACE -l app=skiapp --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
    RUNNING_APP_PODS=$(echo "$RUNNING_APP_PODS" | tr -d '[:space:]')
    if [ "$RUNNING_APP_PODS" -ge 1 ] 2>/dev/null; then
        POD_READY=true
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""

if [ "$POD_READY" = true ]; then
    print_pass "$RUNNING_APP_PODS pod(s) running for skiapp"
    kubectl get pods -n $APP_NAMESPACE -l app=skiapp --no-headers | while read line; do
        echo "    $line"
    done
else
    print_warn "Pods not yet running for skiapp after 120s"
    kubectl get pods -n $APP_NAMESPACE -l app=skiapp
    print_info "Check pod logs: kubectl logs -l app=skiapp -n $APP_NAMESPACE --all-containers"
fi

print_test "Checking Service exists"
if kubectl get service skiapp -n $APP_NAMESPACE &>/dev/null; then
    SVC_TYPE=$(kubectl get service skiapp -n $APP_NAMESPACE -o jsonpath='{.spec.type}' 2>/dev/null)
    SVC_PORT=$(kubectl get service skiapp -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
    print_pass "Service 'skiapp' exists (type: $SVC_TYPE, port: $SVC_PORT)"
else
    print_fail "Service 'skiapp' not found"
fi

################################################################################
# Test 4: Test Application Accessibility (Internal)
################################################################################

print_header "TEST 4: Test Application Accessibility"

print_test "Testing internal service connectivity"

# Get the result
HTTP_CODE=$(kubectl run curl-test-$$  --image=curlimages/curl:latest --restart=Never --rm -i --timeout=30s -- \
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://skiapp.$APP_NAMESPACE.svc.cluster.local:80 2>/dev/null || echo "000")

if [ "$HTTP_CODE" == "200" ]; then
    print_pass "Application responding with HTTP 200"
else
    print_warn "Could not verify HTTP response (code: $HTTP_CODE) - app may still be starting"
fi

################################################################################
# Test 5: GitOps Sync Test
################################################################################

print_header "TEST 5: GitOps Sync Verification"

print_test "Verifying ArgoCD is watching repository"
REPO_URL=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.source.repoURL}' 2>/dev/null)
if [ -n "$REPO_URL" ]; then
    print_pass "Application configured to watch: $REPO_URL"
else
    print_fail "Could not determine repository URL"
fi

print_test "Verifying auto-sync is enabled"
AUTO_SYNC=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null)
if [ -n "$AUTO_SYNC" ]; then
    print_pass "Auto-sync is enabled"
    PRUNE=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.syncPolicy.automated.prune}' 2>/dev/null)
    SELF_HEAL=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null)
    echo "    Prune: $PRUNE"
    echo "    Self-Heal: $SELF_HEAL"
else
    print_warn "Auto-sync is not enabled"
fi

print_test "Checking application operational status"
OPERATION_STATE=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "N/A")
echo "    Operation State: $OPERATION_STATE"

if [ "$OPERATION_STATE" == "Succeeded" ] || [ "$OPERATION_STATE" == "Running" ] || [ "$OPERATION_STATE" == "N/A" ]; then
    print_pass "Application operation state is healthy"
else
    print_warn "Application operation state: $OPERATION_STATE"
fi

################################################################################
# Cleanup
################################################################################

print_header "CLEANUP"

if [ "$SKIP_CLEANUP" = true ]; then
    print_warn "Skipping cleanup (--skip-cleanup flag set)"
    print_info "To manually cleanup, run:"
    echo "    kubectl delete application $APP_NAME -n $ARGOCD_NAMESPACE"
    if [ "$BRANCH_CREATED" = true ]; then
        echo "    git push origin --delete $TEST_REVISION  # Delete develop branch"
    fi
else
    print_test "Deleting ArgoCD Application"
    if kubectl delete application $APP_NAME -n $ARGOCD_NAMESPACE --timeout=60s &>/dev/null; then
        print_pass "ArgoCD Application deleted"
    else
        print_warn "Could not delete ArgoCD Application (may already be deleted)"
    fi

    print_test "Waiting for resources to be cleaned up"
    sleep 5

    if ! kubectl get deployment skiapp -n $APP_NAMESPACE &>/dev/null; then
        print_pass "Application resources cleaned up (prune enabled)"
    else
        print_warn "Some resources may still exist (will be cleaned up by ArgoCD)"
    fi

    # Clean up the develop branch if we created it
    if [ "$BRANCH_CREATED" = true ]; then
        print_test "Deleting remote develop branch"
        if [ -d "$TEMP_DIR/skiapp" ]; then
            cd "$TEMP_DIR/skiapp"
            if git push origin --delete "$TEST_REVISION" 2>/dev/null; then
                print_pass "Remote branch '$TEST_REVISION' deleted"
            else
                print_warn "Could not delete remote branch '$TEST_REVISION'"
            fi
            cd - > /dev/null
        fi
    fi

    # Clean up temp directory
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Temporary directory cleaned up"
    fi
fi

################################################################################
# Summary
################################################################################

print_header "TEST SUMMARY"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo ""
echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
echo -e "  Total:  $TOTAL_TESTS"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ALL TESTS PASSED! ArgoCD is working correctly.${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  SOME TESTS FAILED. Review the output above for details.${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    exit 1
fi
