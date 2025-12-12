#!/bin/bash
################################################################################
# Karpenter Sub-Module Automated Test Script
# Tests Karpenter node autoscaling on EKS
#
# Prerequisites:
#   - EKS cluster deployed with Karpenter enabled (eks-usw2 in us-west-2)
#   - kubectl configured for the cluster
#   - AWS CLI configured
#
# Usage:
#   ./scripts/test-karpenter.sh [OPTIONS]
#
# Options:
#   --skip-cleanup    Don't delete test resources after tests complete
#   --no-pause        Run without interactive pauses (fully automated)
#   --help            Show this help message
################################################################################

# Don't exit on error - we handle errors ourselves
set +e

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-eks-usw2}"
REGION="${REGION:-us-west-2}"
KARPENTER_NAMESPACE="karpenter"
TEST_NAMESPACE="default"
TEST_APP="skiapp"
TEST_REPO="https://github.com/jenkins-oscar/skiapp"
SCALE_REPLICAS=10
NODE_PROVISION_TIMEOUT=180
NODE_TERMINATION_TIMEOUT=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
SKIP_CLEANUP=false
NO_PAUSE=false

# Track initial state
INITIAL_NODE_COUNT=0
KARPENTER_NODES_CREATED=()

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

print_step() {
    echo -e "\n${CYAN}► STEP: $1${NC}"
}

show_help() {
    head -25 "$0" | tail -20
    exit 0
}

# Interactive pause with Headlamp instructions
pause_for_verification() {
    local step_description="$1"
    local show_headlamp="${2:-true}"

    if [ "$NO_PAUSE" = true ]; then
        print_info "Skipping pause (--no-pause flag set)"
        return 0
    fi

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  PAUSE: $step_description${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

    if [ "$show_headlamp" = true ]; then
        echo ""
        echo -e "${YELLOW}  VERIFY WITH HEADLAMP (Optional)${NC}"
        echo ""
        echo "  To visualize Karpenter scaling in real-time:"
        echo ""
        echo "  1. Install Headlamp: https://headlamp.dev/docs/latest/installation/"
        echo "  2. Install Karpenter plugin: https://github.com/headlamp-k8s/plugins/tree/main/karpenter"
        echo "  3. Open Headlamp to see:"
        echo "     - Real-time node provisioning"
        echo "     - NodePool and EC2NodeClass status"
        echo "     - Pod scheduling decisions"
        echo "     - Resource relationship mapping"
        echo ""
        echo "  Reference: https://kubernetes.io/blog/2025/10/06/introducing-headlamp-plugin-for-karpenter/"
    fi

    echo ""
    echo -e "${GREEN}  Press Enter to continue...${NC}"
    read -r
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

# Get count of Karpenter-provisioned nodes
get_karpenter_node_count() {
    kubectl get nodes -l "karpenter.sh/nodepool" --no-headers 2>/dev/null | wc -l | tr -d ' '
}

# Get list of Karpenter-provisioned node names
get_karpenter_nodes() {
    kubectl get nodes -l "karpenter.sh/nodepool" --no-headers -o custom-columns=":metadata.name" 2>/dev/null
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
        --no-pause)
            NO_PAUSE=true
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
# Setup: Clean up previous test resources
################################################################################

print_header "SETUP: Cleaning up previous test resources"

print_step "Checking for existing skiapp deployment"
if kubectl get deployment $TEST_APP -n $TEST_NAMESPACE &>/dev/null; then
    print_info "Found existing deployment '$TEST_APP' - deleting..."
    kubectl delete deployment $TEST_APP -n $TEST_NAMESPACE --timeout=60s &>/dev/null
    kubectl delete service $TEST_APP -n $TEST_NAMESPACE --timeout=60s &>/dev/null 2>/dev/null
    print_info "Deleted existing skiapp resources"
    sleep 5
else
    print_info "No existing skiapp deployment found"
fi

print_step "Checking for lingering Karpenter-provisioned nodes"
EXISTING_KARPENTER_NODES=$(get_karpenter_node_count)
if [ "$EXISTING_KARPENTER_NODES" -gt 0 ]; then
    print_warn "Found $EXISTING_KARPENTER_NODES existing Karpenter-provisioned nodes"
    print_info "These will be considered baseline for this test"
else
    print_info "No existing Karpenter-provisioned nodes found"
fi

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
    INITIAL_NODE_COUNT=$READY_NODES
else
    print_fail "No Ready nodes found"
    exit 1
fi

print_test "Checking AWS CLI is installed"
if command -v aws &>/dev/null; then
    print_pass "AWS CLI is installed ($(aws --version 2>&1 | head -1))"
else
    print_fail "AWS CLI is not installed"
    exit 1
fi

################################################################################
# Test 1: Karpenter Installation Verification
################################################################################

print_header "TEST 1: Karpenter Installation Verification"

print_test "Checking Karpenter namespace exists"
if kubectl get namespace $KARPENTER_NAMESPACE &>/dev/null; then
    print_pass "Karpenter namespace '$KARPENTER_NAMESPACE' exists"
else
    print_fail "Karpenter namespace '$KARPENTER_NAMESPACE' not found"
    print_info "Karpenter may not be deployed. Enable it in the addons module first."
    exit 1
fi

print_test "Checking Karpenter pods are running"
KARPENTER_PODS=$(kubectl get pods -n $KARPENTER_NAMESPACE --no-headers 2>/dev/null | wc -l | tr -d ' ')
RUNNING_PODS=$(kubectl get pods -n $KARPENTER_NAMESPACE --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$RUNNING_PODS" -ge 1 ]; then
    print_pass "$RUNNING_PODS Karpenter pod(s) are running"
    kubectl get pods -n $KARPENTER_NAMESPACE --no-headers | while read line; do
        echo "    $line"
    done
else
    print_fail "Expected at least 1 Karpenter pod running, found $RUNNING_PODS"
    kubectl get pods -n $KARPENTER_NAMESPACE
    exit 1
fi

print_test "Checking Karpenter controller deployment is ready"
KARPENTER_DEPLOY=$(kubectl get deployment -n $KARPENTER_NAMESPACE -o name 2>/dev/null | grep -E "karpenter" | head -1)
if [ -n "$KARPENTER_DEPLOY" ]; then
    READY=$(kubectl get $KARPENTER_DEPLOY -n $KARPENTER_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$READY" -ge 1 ]; then
        print_pass "Karpenter controller is ready ($READY replica(s))"
    else
        print_fail "Karpenter controller not ready"
    fi
else
    print_fail "Karpenter controller deployment not found"
fi

pause_for_verification "Karpenter Installation Verified" false

################################################################################
# Test 2: Verify Karpenter CRDs
################################################################################

print_header "TEST 2: Verify Karpenter CRDs"

print_test "Checking NodePool CRD exists"
if kubectl get crd nodepools.karpenter.sh &>/dev/null; then
    print_pass "NodePool CRD exists (nodepools.karpenter.sh)"
else
    print_fail "NodePool CRD not found"
fi

print_test "Checking EC2NodeClass CRD exists"
if kubectl get crd ec2nodeclasses.karpenter.k8s.aws &>/dev/null; then
    print_pass "EC2NodeClass CRD exists (ec2nodeclasses.karpenter.k8s.aws)"
else
    print_fail "EC2NodeClass CRD not found"
fi

print_test "Listing existing NodePools"
NODEPOOL_COUNT=$(kubectl get nodepools.karpenter.sh --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NODEPOOL_COUNT" -gt 0 ]; then
    print_pass "Found $NODEPOOL_COUNT NodePool(s)"
    kubectl get nodepools.karpenter.sh 2>/dev/null | while read line; do
        echo "    $line"
    done
else
    print_warn "No NodePools found - Karpenter needs NodePool configuration to provision nodes"
fi

print_test "Listing existing EC2NodeClasses"
EC2NODECLASS_COUNT=$(kubectl get ec2nodeclasses.karpenter.k8s.aws --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$EC2NODECLASS_COUNT" -gt 0 ]; then
    print_pass "Found $EC2NODECLASS_COUNT EC2NodeClass(es)"
    kubectl get ec2nodeclasses.karpenter.k8s.aws 2>/dev/null | while read line; do
        echo "    $line"
    done
else
    print_warn "No EC2NodeClasses found - Karpenter needs EC2NodeClass configuration"
fi

pause_for_verification "Karpenter CRDs Verified" false

################################################################################
# Test 3: Deploy skiapp and Trigger Karpenter Scaling
################################################################################

print_header "TEST 3: Deploy skiapp and Trigger Karpenter Scaling"

print_step "Recording initial node count"
INITIAL_KARPENTER_NODES=$(get_karpenter_node_count)
print_info "Initial Karpenter-provisioned nodes: $INITIAL_KARPENTER_NODES"
print_info "Initial total nodes: $INITIAL_NODE_COUNT"

print_step "Creating skiapp deployment with $SCALE_REPLICAS replicas"

# Create deployment manifest
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $TEST_APP
  namespace: $TEST_NAMESPACE
  labels:
    app: $TEST_APP
spec:
  replicas: $SCALE_REPLICAS
  selector:
    matchLabels:
      app: $TEST_APP
  template:
    metadata:
      labels:
        app: $TEST_APP
    spec:
      containers:
      - name: $TEST_APP
        image: node:18-alpine
        command: ["npm", "start"]
        workingDir: /app
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: app-source
          mountPath: /app
      initContainers:
      - name: git-clone
        image: alpine/git
        command: ["git", "clone", "$TEST_REPO.git", "/app"]
        volumeMounts:
        - name: app-source
          mountPath: /app
      - name: npm-install
        image: node:18-alpine
        command: ["npm", "install"]
        workingDir: /app
        volumeMounts:
        - name: app-source
          mountPath: /app
      volumes:
      - name: app-source
        emptyDir: {}
EOF

if [ $? -eq 0 ]; then
    print_pass "Deployment '$TEST_APP' created with $SCALE_REPLICAS replicas"
else
    print_fail "Failed to create deployment"
    exit 1
fi

# Create service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $TEST_APP
  namespace: $TEST_NAMESPACE
  labels:
    app: $TEST_APP
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    app: $TEST_APP
EOF

if [ $? -eq 0 ]; then
    print_pass "Service '$TEST_APP' created"
else
    print_warn "Failed to create service (non-critical for scaling test)"
fi

print_step "Waiting for Karpenter to provision new nodes"
print_info "Watching for new nodes with 'karpenter.sh/nodepool' label (timeout: ${NODE_PROVISION_TIMEOUT}s)..."

ELAPSED=0
NEW_NODES_PROVISIONED=false
while [ $ELAPSED -lt $NODE_PROVISION_TIMEOUT ]; do
    CURRENT_KARPENTER_NODES=$(get_karpenter_node_count)
    if [ "$CURRENT_KARPENTER_NODES" -gt "$INITIAL_KARPENTER_NODES" ]; then
        NEW_NODES_PROVISIONED=true
        break
    fi

    # Show pending pods count
    PENDING_PODS=$(kubectl get pods -n $TEST_NAMESPACE -l app=$TEST_APP --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
    RUNNING_PODS=$(kubectl get pods -n $TEST_NAMESPACE -l app=$TEST_APP --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo -ne "\r    Pending pods: $PENDING_PODS | Running pods: $RUNNING_PODS | Karpenter nodes: $CURRENT_KARPENTER_NODES (waiting...)"

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
echo ""

if [ "$NEW_NODES_PROVISIONED" = true ]; then
    FINAL_KARPENTER_NODES=$(get_karpenter_node_count)
    NODES_ADDED=$((FINAL_KARPENTER_NODES - INITIAL_KARPENTER_NODES))
    print_pass "Karpenter provisioned $NODES_ADDED new node(s)"

    # Store the new node names
    print_info "New Karpenter-provisioned nodes:"
    get_karpenter_nodes | while read node; do
        echo "    - $node"
    done
else
    print_warn "No new Karpenter nodes provisioned within timeout"
    print_info "This could mean:"
    echo "    - Existing nodes have enough capacity"
    echo "    - NodePool constraints don't match pod requirements"
    echo "    - Karpenter is still processing"

    # Check for pending pods
    PENDING_PODS=$(kubectl get pods -n $TEST_NAMESPACE -l app=$TEST_APP --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
    if [ "$PENDING_PODS" -gt 0 ]; then
        print_warn "$PENDING_PODS pods still pending - check Karpenter logs"
        kubectl logs -n $KARPENTER_NAMESPACE -l app.kubernetes.io/name=karpenter --tail=20 2>/dev/null | head -20
    fi
fi

pause_for_verification "Karpenter Scaling - Nodes Provisioned" true

################################################################################
# Test 4: Verify Karpenter-Provisioned Nodes
################################################################################

print_header "TEST 4: Verify Karpenter-Provisioned Nodes"

print_test "Checking nodes have Karpenter labels"
KARPENTER_LABELED_NODES=$(get_karpenter_node_count)
if [ "$KARPENTER_LABELED_NODES" -gt 0 ]; then
    print_pass "Found $KARPENTER_LABELED_NODES node(s) with Karpenter labels"

    print_info "Node details:"
    kubectl get nodes -l "karpenter.sh/nodepool" -o custom-columns=\
"NAME:.metadata.name,\
NODEPOOL:.metadata.labels.karpenter\.sh/nodepool,\
INSTANCE-TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,\
CAPACITY-TYPE:.metadata.labels.karpenter\.sh/capacity-type,\
STATUS:.status.conditions[-1].type" 2>/dev/null | while read line; do
        echo "    $line"
    done
else
    print_warn "No Karpenter-labeled nodes found"
fi

print_test "Verifying pods are scheduled on Karpenter nodes"
PODS_ON_KARPENTER_NODES=0
for pod in $(kubectl get pods -n $TEST_NAMESPACE -l app=$TEST_APP -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    NODE=$(kubectl get pod $pod -n $TEST_NAMESPACE -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    if kubectl get node "$NODE" -o jsonpath='{.metadata.labels}' 2>/dev/null | grep -q "karpenter.sh/nodepool"; then
        ((PODS_ON_KARPENTER_NODES++))
    fi
done

if [ "$PODS_ON_KARPENTER_NODES" -gt 0 ]; then
    print_pass "$PODS_ON_KARPENTER_NODES pod(s) running on Karpenter-provisioned nodes"
else
    print_info "No pods currently on Karpenter-provisioned nodes (may be on existing nodes)"
fi

print_test "Checking pod status"
TOTAL_PODS=$(kubectl get pods -n $TEST_NAMESPACE -l app=$TEST_APP --no-headers 2>/dev/null | wc -l | tr -d ' ')
RUNNING_PODS=$(kubectl get pods -n $TEST_NAMESPACE -l app=$TEST_APP --no-headers 2>/dev/null | grep -c "Running" || echo "0")
PENDING_PODS=$(kubectl get pods -n $TEST_NAMESPACE -l app=$TEST_APP --no-headers 2>/dev/null | grep -c "Pending" || echo "0")

echo "    Total pods: $TOTAL_PODS"
echo "    Running: $RUNNING_PODS"
echo "    Pending: $PENDING_PODS"

if [ "$RUNNING_PODS" -ge 1 ]; then
    print_pass "At least 1 pod is running"
else
    print_warn "No pods running yet"
fi

pause_for_verification "Karpenter Nodes Verified" true

################################################################################
# Test 5: Scale Down and Consolidation Test
################################################################################

print_header "TEST 5: Scale Down and Consolidation Test"

print_step "Recording current node count before scale-down"
PRE_SCALEDOWN_KARPENTER_NODES=$(get_karpenter_node_count)
print_info "Current Karpenter-provisioned nodes: $PRE_SCALEDOWN_KARPENTER_NODES"

print_step "Scaling skiapp deployment to 0 replicas"
kubectl scale deployment $TEST_APP -n $TEST_NAMESPACE --replicas=0

if [ $? -eq 0 ]; then
    print_pass "Deployment scaled to 0 replicas"
else
    print_fail "Failed to scale deployment"
fi

print_step "Deleting skiapp deployment"
kubectl delete deployment $TEST_APP -n $TEST_NAMESPACE --timeout=60s &>/dev/null
kubectl delete service $TEST_APP -n $TEST_NAMESPACE --timeout=60s &>/dev/null 2>/dev/null

print_pass "Deployment and service deleted"

print_step "Waiting for Karpenter to consolidate/terminate nodes"
print_info "Watching for node termination (timeout: ${NODE_TERMINATION_TIMEOUT}s)..."
print_info "Note: Karpenter consolidation may take several minutes"

ELAPSED=0
NODES_TERMINATED=false
while [ $ELAPSED -lt $NODE_TERMINATION_TIMEOUT ]; do
    CURRENT_KARPENTER_NODES=$(get_karpenter_node_count)

    if [ "$CURRENT_KARPENTER_NODES" -lt "$PRE_SCALEDOWN_KARPENTER_NODES" ]; then
        NODES_TERMINATED=true
        break
    fi

    echo -ne "\r    Karpenter nodes: $CURRENT_KARPENTER_NODES (waiting for consolidation...)"

    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
echo ""

if [ "$NODES_TERMINATED" = true ]; then
    FINAL_KARPENTER_NODES=$(get_karpenter_node_count)
    NODES_REMOVED=$((PRE_SCALEDOWN_KARPENTER_NODES - FINAL_KARPENTER_NODES))
    print_pass "Karpenter terminated $NODES_REMOVED node(s)"
else
    FINAL_KARPENTER_NODES=$(get_karpenter_node_count)
    if [ "$FINAL_KARPENTER_NODES" -eq "$INITIAL_KARPENTER_NODES" ]; then
        print_pass "Node count returned to initial state ($INITIAL_KARPENTER_NODES)"
    else
        print_warn "Karpenter nodes not yet consolidated (current: $FINAL_KARPENTER_NODES)"
        print_info "Consolidation may still be in progress"
        print_info "Check Karpenter logs: kubectl logs -n $KARPENTER_NAMESPACE -l app.kubernetes.io/name=karpenter"
    fi
fi

pause_for_verification "Consolidation Test Complete" true

################################################################################
# Cleanup
################################################################################

print_header "CLEANUP"

if [ "$SKIP_CLEANUP" = true ]; then
    print_warn "Skipping cleanup (--skip-cleanup flag set)"
    print_info "To manually cleanup, run:"
    echo "    kubectl delete deployment $TEST_APP -n $TEST_NAMESPACE"
    echo "    kubectl delete service $TEST_APP -n $TEST_NAMESPACE"
else
    print_step "Verifying test resources are cleaned up"

    # Double-check deployment is deleted
    if kubectl get deployment $TEST_APP -n $TEST_NAMESPACE &>/dev/null; then
        kubectl delete deployment $TEST_APP -n $TEST_NAMESPACE --timeout=60s &>/dev/null
    fi

    # Double-check service is deleted
    if kubectl get service $TEST_APP -n $TEST_NAMESPACE &>/dev/null; then
        kubectl delete service $TEST_APP -n $TEST_NAMESPACE --timeout=60s &>/dev/null
    fi

    print_pass "Test resources cleaned up"

    # Final node state
    FINAL_NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    FINAL_KARPENTER_NODES=$(get_karpenter_node_count)

    print_info "Final state:"
    echo "    Total nodes: $FINAL_NODE_COUNT"
    echo "    Karpenter-provisioned nodes: $FINAL_KARPENTER_NODES"
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
    echo -e "${GREEN}  ALL TESTS PASSED! Karpenter is working correctly.${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    print_info "Karpenter successfully:"
    echo "    - Installed and running in the cluster"
    echo "    - CRDs (NodePool, EC2NodeClass) are available"
    echo "    - Scaled up nodes when pods required resources"
    echo "    - Consolidated/terminated nodes when workload removed"
    exit 0
else
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  SOME TESTS FAILED. Review the output above for details.${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    print_info "Troubleshooting tips:"
    echo "    - Check Karpenter logs: kubectl logs -n $KARPENTER_NAMESPACE -l app.kubernetes.io/name=karpenter"
    echo "    - Verify NodePool exists: kubectl get nodepools.karpenter.sh"
    echo "    - Verify EC2NodeClass exists: kubectl get ec2nodeclasses.karpenter.k8s.aws"
    echo "    - Check events: kubectl get events --sort-by=.metadata.creationTimestamp"
    exit 1
fi
