# ArgoCD GitOps Exercise

This exercise adds [ArgoCD](https://argo-cd.readthedocs.io/) to your EKS cluster for GitOps-based continuous delivery.

## Overview

### What is ArgoCD?

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes that:
- Automatically syncs your cluster state with Git repository definitions
- Provides a web UI for visualizing application deployments
- Supports automated and manual sync policies
- Offers rollback capabilities to any previous Git commit

### What is GitOps?

GitOps is an operational framework that uses Git as the single source of truth for declarative infrastructure and applications:

| Traditional CD | GitOps |
|---------------|--------|
| Push-based deployments | Pull-based deployments |
| CI system has cluster access | Only ArgoCD has cluster access |
| Imperative scripts | Declarative manifests |
| State unknown | Git = desired state |

### Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Developer     │────▶│    GitHub       │◀────│    ArgoCD       │
│   (git push)    │     │   Repository    │     │   (watches)     │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │   EKS Cluster   │
                                                │   (applies)     │
                                                └─────────────────┘
```

---

## Prerequisites

Before starting, ensure you have:

- [ ] EKS cluster deployed successfully via Terraform Stacks
- [ ] `kubectl` installed and configured for your cluster
- [ ] AWS CLI configured with appropriate permissions
- [ ] GitHub account (for forking the demo app)

Verify your cluster is accessible:

```bash
# Configure kubectl for your cluster (replace region and cluster name)
aws eks update-kubeconfig --region us-west-2 --name eks-usw2

# Verify connection
kubectl get nodes
```

---

## Step 1: Enable ArgoCD in Addons Module

Modify the EKS Blueprints Addons module to enable ArgoCD.

### 1.1 Add Variable

Edit `modules/eks-blueprints-addons/variables.tf` and add:

```hcl
variable "enable_argocd" {
  description = "Enable ArgoCD addon for GitOps"
  type        = bool
  default     = false
}
```

### 1.2 Enable ArgoCD

Edit `modules/eks-blueprints-addons/main.tf` and add the ArgoCD configuration:

```hcl
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = var.cluster_name
  cluster_endpoint  = var.cluster_endpoint
  cluster_version   = var.cluster_version
  oidc_provider_arn = var.oidc_provider_arn

  # AWS Load Balancer Controller
  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller

  # ArgoCD - ADD THIS
  enable_argocd = var.enable_argocd

  tags = var.tags
}
```

---

## Step 2: Deploy Changes via HCP Terraform

Commit and push your changes to trigger HCP Terraform:

```bash
git add modules/eks-blueprints-addons/
git commit -m "feat: Enable ArgoCD addon for GitOps"
git push
```

HCP Terraform will:
1. Detect the changes
2. Create a plan showing ArgoCD resources to be added
3. Wait for your approval

After approval, wait for the deployment to complete (approximately 5 minutes).

---

## Step 3: Verify ArgoCD Installation

Check that ArgoCD pods are running:

```bash
# Check ArgoCD namespace exists
kubectl get namespace argocd

# Check all ArgoCD pods are running
kubectl get pods -n argocd

# Expected output:
# NAME                                               READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0                    1/1     Running   0          5m
# argocd-applicationset-controller-...               1/1     Running   0          5m
# argocd-dex-server-...                              1/1     Running   0          5m
# argocd-notifications-controller-...                1/1     Running   0          5m
# argocd-redis-...                                   1/1     Running   0          5m
# argocd-repo-server-...                             1/1     Running   0          5m
# argocd-server-...                                  1/1     Running   0          5m
```

---

## Step 4: Access ArgoCD UI

### 4.1 Get Admin Password

The initial admin password is stored in a Kubernetes secret:

```bash
# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

**Save this password** - you'll need it to log in.

### 4.2 Port Forward to ArgoCD Server

```bash
# Start port forwarding (runs in foreground)
kubectl port-forward svc/argo-cd-argocd-server -n argocd 8080:443
```

### 4.3 Access the UI

Open your browser and navigate to:
- **URL**: https://localhost:8080
- **Username**: `admin`
- **Password**: (from step 4.1)

> **Note**: You'll see a certificate warning since ArgoCD uses a self-signed certificate. Click "Advanced" and proceed.

---

## Step 5: Fork the Demo Application

We'll deploy a sample Node.js web application using GitOps.

### 5.1 Fork the Repository

1. Go to https://github.com/jenkins-oscar/skiapp
2. Click **Fork** in the top-right corner
3. Select your GitHub account as the destination

You now have `https://github.com/<YOUR_GITHUB_USER>/skiapp`

### 5.2 Clone Your Fork

```bash
git clone https://github.com/<YOUR_GITHUB_USER>/skiapp.git
cd skiapp
```

---

## Step 6: Add Kubernetes Manifests

The skiapp repository has a Dockerfile but no Kubernetes manifests. Create them now.

### 6.1 Create k8s Directory

```bash
mkdir k8s
```

### 6.2 Create Deployment Manifest

Create `k8s/deployment.yaml`:

```yaml
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
        command: ["sh", "-c", "npm install && npm start"]
        workingDir: /app
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: app-source
          mountPath: /app
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      initContainers:
      - name: git-clone
        image: alpine/git
        command:
        - git
        - clone
        - https://github.com/<YOUR_GITHUB_USER>/skiapp.git
        - /app
        volumeMounts:
        - name: app-source
          mountPath: /app
      volumes:
      - name: app-source
        emptyDir: {}
```

> **Note**: Replace `<YOUR_GITHUB_USER>` with your actual GitHub username.

### 6.3 Create Service Manifest

Create `k8s/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: skiapp
  labels:
    app: skiapp
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    app: skiapp
```

### 6.4 Push the Manifests

```bash
git add k8s/
git commit -m "Add Kubernetes manifests for ArgoCD deployment"
git push
```

---

## Step 7: Create ArgoCD Application

Now configure ArgoCD to deploy your application.

Create a file `argocd-application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: skiapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_GITHUB_USER>/skiapp
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Apply it:

```bash
kubectl apply -f argocd-application.yaml
```

---

## Step 8: Verify Deployment

### 8.1 Check Application Status in ArgoCD

In the ArgoCD UI, you should see:
- **skiapp** application with status **Synced** and **Healthy**

### 8.2 Check Kubernetes Resources

```bash
# Check deployment
kubectl get deployment skiapp

# Check pods
kubectl get pods -l app=skiapp

# Check service
kubectl get svc skiapp
```

### 8.3 Access the Application

Get the LoadBalancer URL:

```bash
kubectl get svc skiapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open the URL in your browser to see the skiapp running.

> **Note**: It may take 2-3 minutes for the LoadBalancer DNS to propagate.

---

## Step 9: Test GitOps Workflow

Experience the power of GitOps by making a change through Git.

### 9.1 Update Replicas

Edit `k8s/deployment.yaml` in your forked repository:

```yaml
spec:
  replicas: 3  # Changed from 2 to 3
```

### 9.2 Commit and Push

```bash
git add k8s/deployment.yaml
git commit -m "Scale skiapp to 3 replicas"
git push
```

### 9.3 Watch ArgoCD Sync

In the ArgoCD UI:
1. The application will show **OutOfSync** briefly
2. With auto-sync enabled, it will automatically apply the change
3. Status returns to **Synced**

Verify in Kubernetes:

```bash
kubectl get pods -l app=skiapp
# Should now show 3 pods
```

---

## Cleanup

### Remove ArgoCD Application

```bash
# Delete via kubectl
kubectl delete application skiapp -n argocd

# Or via ArgoCD CLI
argocd app delete skiapp
```

### Remove Kubernetes Resources

ArgoCD with `prune: true` will automatically delete resources when the Application is deleted.

Verify cleanup:

```bash
kubectl get deployment skiapp
kubectl get svc skiapp
# Both should return "not found"
```

### (Optional) Disable ArgoCD Addon

To completely remove ArgoCD, set `enable_argocd = false` in the addons module and push the change to trigger HCP Terraform.

---

## Troubleshooting

### ArgoCD Pods Not Starting

**Symptom**: Pods stuck in Pending or CrashLoopBackOff

**Solution**:
```bash
# Check pod events
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server

# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Application Stuck in "Progressing"

**Symptom**: Application never reaches "Synced" status

**Solution**:
```bash
# Check application events
kubectl describe application skiapp -n argocd

# Check for resource issues
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Git Repository Not Accessible

**Symptom**: ArgoCD shows "repository not accessible"

**Solution**:
- Ensure the repository is public, OR
- Configure ArgoCD with repository credentials:

```bash
argocd repo add https://github.com/<YOUR_GITHUB_USER>/skiapp \
  --username <github-username> \
  --password <github-token>
```

### Image Pull Errors

**Symptom**: Pods show ImagePullBackOff

**Solution**:
```bash
# Check pod events for details
kubectl describe pod -l app=skiapp

# Common fixes:
# - Verify image name and tag
# - Check if image exists in registry
# - For private registries, add imagePullSecrets
```

### LoadBalancer Pending

**Symptom**: Service stuck in Pending state

**Solution**:
```bash
# Verify AWS Load Balancer Controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check service events
kubectl describe svc skiapp
```

---

## Reference Links

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Getting Started Guide](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [GitOps Principles](https://opengitops.dev/)
- [EKS Blueprints Addons - ArgoCD](https://aws-ia.github.io/terraform-aws-eks-blueprints-addons/main/addons/argocd/)
