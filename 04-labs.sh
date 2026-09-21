#!/usr/bin/env bash

# ============================================================
# integration-xtesting
# Kubernetes Labs + Executor + Evidence - Part 4/5
# ============================================================

set -Eeuo pipefail

readonly ROOT_DIR="$(pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}

trap 'error "Failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

# ============================================================
# Repository validation
# ============================================================

log "Checking repository..."

[[ -d ".git" ]] || die "Run this script from repository root."
[[ -d "quality" ]] || die "Part 1 is missing."
[[ -d "ci" ]] || die "Part 3 is missing."

success "Repository validated."

# ============================================================
# Directory structure
# ============================================================

log "Creating Kubernetes lab structure..."

mkdir -p \
    labs/1N \
    labs/3N \
    labs/NN \
    labs/common \
    labs/manifests \
    labs/scripts \
    labs/config \
    executor \
    executor/src \
    executor/scripts \
    executor/config \
    campaigns \
    campaigns/ra2 \
    campaigns/rc2 \
    reports/labs \
    reports/executions \
    reports/evidence

success "Lab structure created."

# ============================================================
# Lab profiles
# ============================================================

log "Creating lab profiles..."

cat > labs/config/labs.yaml <<'EOF'
version: "1.0"

labs:

  - name: 1N
    nodes: 1
    enabled: true
    purpose: single-node validation

  - name: 3N
    nodes: 3
    enabled: true
    purpose: multi-node validation

  - name: NN
    nodes: dynamic
    enabled: true
    purpose: scalability validation
EOF

cat > labs/1N/profile.yaml <<'EOF'
name: 1N
nodes: 1
mode: fixed
enabled: true
EOF

cat > labs/3N/profile.yaml <<'EOF'
name: 3N
nodes: 3
mode: fixed
enabled: true
EOF

cat > labs/NN/profile.yaml <<'EOF'
name: NN
nodes: dynamic
mode: dynamic
enabled: true
EOF

success "Lab profiles created."

# ============================================================
# Lab discovery
# ============================================================

log "Creating Kubernetes discovery script..."

cat > labs/scripts/discover.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

OUTPUT="${1:-reports/labs/discovery.json}"

mkdir -p "$(dirname "${OUTPUT}")"

if ! command -v kubectl >/dev/null 2>&1; then

    echo "kubectl is not installed."

    cat > "${OUTPUT}" <<EOF
{
  "status": "UNAVAILABLE",
  "reason": "kubectl-not-installed"
}
EOF

    exit 0
fi

if ! kubectl cluster-info >/dev/null 2>&1; then

    echo "Kubernetes cluster is not reachable."

    cat > "${OUTPUT}" <<EOF
{
  "status": "UNAVAILABLE",
  "reason": "cluster-not-reachable"
}
EOF

    exit 0
fi

nodes="$(kubectl get nodes \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')"

kubernetes_version="$(
    kubectl version -o json 2>/dev/null \
    | python3 -c '
import json
import sys

try:
    data=json.load(sys.stdin)
    print(
        data.get("serverVersion", {})
            .get("gitVersion", "unknown")
    )
except Exception:
    print("unknown")
'
)"

ready_nodes="$(
    kubectl get nodes \
        --no-headers 2>/dev/null \
        | awk '$2 == "Ready" {count++} END {print count+0}'
)"

cat > "${OUTPUT}" <<EOF
{
  "status": "AVAILABLE",
  "nodes": ${nodes},
  "ready_nodes": ${ready_nodes},
  "kubernetes_version": "${kubernetes_version}"
}
EOF

echo "Kubernetes cluster discovered."
cat "${OUTPUT}"
SH

chmod +x labs/scripts/discover.sh

success "Lab discovery created."

# ============================================================
# Lab capability detector
# ============================================================

log "Creating capability detector..."

cat > labs/scripts/capabilities.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

OUTPUT="${1:-reports/labs/capabilities.json}"

mkdir -p "$(dirname "${OUTPUT}")"

ONE_N=false
THREE_N=false
NN=false

if command -v kubectl >/dev/null 2>&1 &&
   kubectl cluster-info >/dev/null 2>&1
then

    nodes="$(
        kubectl get nodes \
            --no-headers 2>/dev/null \
            | wc -l \
            | tr -d ' '
    )"

    if [[ "${nodes}" -ge 1 ]]; then
        ONE_N=true
    fi

    if [[ "${nodes}" -ge 3 ]]; then
        THREE_N=true
        NN=true
    fi
fi

cat > "${OUTPUT}" <<EOF
{
  "1N": ${ONE_N},
  "3N": ${THREE_N},
  "NN": ${NN}
}
EOF

echo "Lab capabilities:"
cat "${OUTPUT}"
SH

chmod +x labs/scripts/capabilities.sh

success "Capability detector created."

# ============================================================
# Evidence collector
# ============================================================

log "Creating evidence collector..."

cat > labs/scripts/collect-evidence.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ID="${1:?test id required}"
LAB="${2:?lab required}"
OUTPUT_DIR="${3:-reports/evidence}"

TARGET="${OUTPUT_DIR}/${TEST_ID}/${LAB}"

mkdir -p "${TARGET}"

echo "Collecting evidence:"
echo "  Test : ${TEST_ID}"
echo "  Lab  : ${LAB}"
echo "  Path : ${TARGET}"

if command -v kubectl >/dev/null 2>&1 &&
   kubectl cluster-info >/dev/null 2>&1
then

    kubectl get nodes -o wide \
        > "${TARGET}/nodes.txt" 2>&1 || true

    kubectl get pods -A -o wide \
        > "${TARGET}/pods.txt" 2>&1 || true

    kubectl get namespaces \
        > "${TARGET}/namespaces.txt" 2>&1 || true

    kubectl get events -A \
        > "${TARGET}/events.txt" 2>&1 || true

    kubectl cluster-info \
        > "${TARGET}/cluster-info.txt" 2>&1 || true

else

    echo "Kubernetes unavailable." \
        > "${TARGET}/cluster-unavailable.txt"

fi

cat > "${TARGET}/manifest.json" <<EOF
{
  "test": "${TEST_ID}",
  "lab": "${LAB}",
  "evidence_path": "${TARGET}"
}
EOF

echo "Evidence collection completed."
SH

chmod +x labs/scripts/collect-evidence.sh

success "Evidence collector created."

# ============================================================
# Kubernetes executor
# ============================================================

log "Creating Kubernetes executor..."

cat > executor/run.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ID="${1:?test id required}"
LAB="${2:?lab required}"
IMAGE="${3:?image required}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_ID="${TEST_ID}-${LAB}-$(date +%Y%m%d%H%M%S)"

NAMESPACE="xtesting-${LAB,,}"

REPORT_DIR="${ROOT_DIR}/reports/executions/${RUN_ID}"

mkdir -p "${REPORT_DIR}"

START="$(date +%s)"

echo "=================================================="
echo " Xtesting Kubernetes Executor"
echo "=================================================="
echo "Test      : ${TEST_ID}"
echo "Lab       : ${LAB}"
echo "Image     : ${IMAGE}"
echo "Namespace : ${NAMESPACE}"
echo "Run ID    : ${RUN_ID}"
echo

if ! command -v kubectl >/dev/null 2>&1; then

    cat > "${REPORT_DIR}/result.json" <<EOF
{
  "test": "${TEST_ID}",
  "lab": "${LAB}",
  "image": "${IMAGE}",
  "status": "SKIPPED",
  "reason": "kubectl-not-installed"
}
EOF

    echo "kubectl unavailable: execution skipped."
    exit 0
fi

if ! kubectl cluster-info >/dev/null 2>&1; then

    cat > "${REPORT_DIR}/result.json" <<EOF
{
  "test": "${TEST_ID}",
  "lab": "${LAB}",
  "image": "${IMAGE}",
  "status": "SKIPPED",
  "reason": "cluster-not-reachable"
}
EOF

    echo "Cluster unavailable: execution skipped."
    exit 0
fi

kubectl create namespace "${NAMESPACE}" \
    --dry-run=client \
    -o yaml \
    | kubectl apply -f -

cat > "${REPORT_DIR}/job.yaml" <<EOF
apiVersion: batch/v1
kind: Job

metadata:
  name: ${RUN_ID}
  namespace: ${NAMESPACE}

spec:

  backoffLimit: 0

  template:

    metadata:
      labels:
        xtesting.test: "${TEST_ID}"
        xtesting.lab: "${LAB}"

    spec:

      restartPolicy: Never

      containers:

        - name: test
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
EOF

kubectl apply -f "${REPORT_DIR}/job.yaml"

echo
echo "Waiting for Job..."

if kubectl wait \
    --namespace "${NAMESPACE}" \
    --for=condition=complete \
    "job/${RUN_ID}" \
    --timeout=30m
then

    STATUS="PASS"

else

    STATUS="FAIL"

fi

kubectl logs \
    --namespace "${NAMESPACE}" \
    "job/${RUN_ID}" \
    > "${REPORT_DIR}/logs.txt" 2>&1 || true

kubectl describe job \
    --namespace "${NAMESPACE}" \
    "${RUN_ID}" \
    > "${REPORT_DIR}/describe.txt" 2>&1 || true

END="$(date +%s)"
DURATION="$((END - START))"

cat > "${REPORT_DIR}/result.json" <<EOF
{
  "test": "${TEST_ID}",
  "lab": "${LAB}",
  "image": "${IMAGE}",
  "status": "${STATUS}",
  "duration_seconds": ${DURATION}
}
EOF

"${ROOT_DIR}/labs/scripts/collect-evidence.sh" \
    "${TEST_ID}" \
    "${LAB}" \
    "${ROOT_DIR}/reports/evidence"

echo
echo "Execution status: ${STATUS}"
echo "Duration: ${DURATION}s"

if [[ "${STATUS}" == "FAIL" ]]; then
    exit 1
fi
SH

chmod +x executor/run.sh

success "Kubernetes executor created."

# ============================================================
# Campaign configuration
# ============================================================

log "Creating campaign configuration..."

cat > campaigns/ra2/campaign.yaml <<'EOF'
name: RA2 campaign

family: RA2

tests:

  - id: RA2-NET-001
    image: ra2-net-001:ci
    topology:
      1N: true
      3N: true
      NN: false
EOF

cat > campaigns/rc2/campaign.yaml <<'EOF'
name: RC2 campaign

family: RC2

tests:

  - id: RC2-NET-001
    image: rc2-net-001:ci
    topology:
      1N: true
      3N: true
      NN: false
EOF

success "Campaign definitions created."

# ============================================================
# Campaign runner
# ============================================================

log "Creating campaign runner..."

cat > campaigns/run.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAMILY="${1:-all}"

run_test() {

    local test_id="$1"
    local image="$2"
    local lab="$3"

    echo
    echo "=============================================="
    echo "Campaign execution"
    echo "Test : ${test_id}"
    echo "Lab  : ${lab}"
    echo "=============================================="

    "${ROOT_DIR}/executor/run.sh" \
        "${test_id}" \
        "${lab}" \
        "${image}"
}

run_ra2() {

    run_test \
        "RA2-NET-001" \
        "ra2-net-001:ci" \
        "1N"

    run_test \
        "RA2-NET-001" \
        "ra2-net-001:ci" \
        "3N"
}

run_rc2() {

    run_test \
        "RC2-NET-001" \
        "rc2-net-001:ci" \
        "1N"

    run_test \
        "RC2-NET-001" \
        "rc2-net-001:ci" \
        "3N"
}

case "${FAMILY}" in

    ra2)
        run_ra2
        ;;

    rc2)
        run_rc2
        ;;

    all)
        run_ra2
        run_rc2
        ;;

    *)
        echo "Usage: $0 [ra2|rc2|all]"
        exit 1
        ;;

esac

echo
echo "=============================================="
echo "CAMPAIGN: PASS"
echo "=============================================="
SH

chmod +x campaigns/run.sh

success "Campaign runner created."

# ============================================================
# Campaign matrix
# ============================================================

log "Creating campaign matrix..."

cat > campaigns/matrix.yaml <<'EOF'
version: "1.0"

matrix:

  RA2:
    RA2-NET-001:
      1N: true
      3N: true
      NN: false

  RC2:
    RC2-NET-001:
      1N: true
      3N: true
      NN: false
EOF

success "Campaign matrix created."

# ============================================================
# Lab validation
# ============================================================

log "Creating lab validation..."

cat > labs/validate.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=================================================="
echo " Kubernetes Labs Validation"
echo "=================================================="

for lab in 1N 3N NN; do

    echo
    echo "Checking lab: ${lab}"

    [[ -f "${ROOT_DIR}/labs/${lab}/profile.yaml" ]] \
        || {
            echo "Missing profile for ${lab}"
            exit 1
        }

    echo "  profile: PASS"

done

echo
echo "Checking executor..."

[[ -x "${ROOT_DIR}/executor/run.sh" ]] \
    || {
        echo "Executor missing."
        exit 1
    }

echo "  executor: PASS"

echo
echo "Checking evidence collector..."

[[ -x "${ROOT_DIR}/labs/scripts/collect-evidence.sh" ]] \
    || {
        echo "Evidence collector missing."
        exit 1
    }

echo "  evidence collector: PASS"

echo
echo "LAB VALIDATION: PASS"
SH

chmod +x labs/validate.sh

success "Lab validator created."

# ============================================================
# Integration documentation
# ============================================================

log "Creating documentation..."

cat > docs/kubernetes-labs.md <<'EOF'
# Kubernetes Labs

The integration-xtesting execution model uses three logical profiles.

## 1N

Single-node environment.

Used for:

- basic execution;
- smoke validation;
- functional validation.

## 3N

Three-node environment.

Used for:

- distributed execution;
- networking;
- scheduling;
- multi-node behavior.

## NN

Dynamic number of nodes.

Used for:

- scalability;
- stress;
- topology-dependent validation.

## Execution flow

```text
Test Application
       |
       v
    Executor
       |
       v
 Kubernetes Job
       |
       v
      Lab
       |
       +---- logs
       |
       +---- result
       |
       +---- evidence
       |
       v
    Report

EOF

cat > docs/execution-model.md <<'EOF'
Test Execution Model

A test application declares its supported topology.

Example:

topology:
  1N: true
  3N: true
  NN: false

The campaign engine uses this matrix to determine where the test can execute.

The executor remains independent from the test implementation.

Campaign
   |
   v
Executor
   |
   v
Kubernetes Job
   |
   v
Test Container
   |
   +---- stdout
   +---- result
   +---- evidence

EOF

success "Documentation created."
============================================================
Final local validation
============================================================

echo
log "Running lab validation..."

./labs/validate.sh

echo
log "Running discovery..."

./labs/scripts/discover.sh
reports/labs/discovery.json

echo
log "Running capability detection..."

./labs/scripts/capabilities.sh
reports/labs/capabilities.json
============================================================
Final summary
============================================================

echo
echo "============================================================"
success " PART 4/5 COMPLETED"
echo "============================================================"

echo
echo "Created:"
echo " labs/1N/"
echo " labs/3N/"
echo " labs/NN/"
echo " labs/config/"
echo " labs/scripts/"
echo " executor/"
echo " campaigns/"
echo " reports/evidence/"
echo " reports/executions/"

echo
echo "Important commands:"
echo
echo " ./labs/validate.sh"
echo " ./labs/scripts/discover.sh"
echo " ./labs/scripts/capabilities.sh"
echo
echo " ./campaigns/run.sh ra2"
echo " ./campaigns/run.sh rc2"
echo " ./campaigns/run.sh all"

echo
echo "Kubernetes execution requires:"
echo " - kubectl"
echo " - reachable Kubernetes cluster"
echo " - test images available to the cluster"

echo
echo "Next:"
echo " ./05-release-dashboard.sh"


### Ce que cette partie ajoute

Le modèle d'exécution devient maintenant :

```text
                    TEST APPLICATION
                    RA2 / RC2
                         │
                         ▼
                    CAMPAIGN
                         │
               ┌─────────┼─────────┐
               ▼         ▼         ▼
              1N        3N        NN
               │         │         │
               └─────────┼─────────┘
                         ▼
                    EXECUTOR
                         │
                         ▼
                  Kubernetes Job
                         │
                         ▼
                     Result
                    /      \
                   /        \
               Logs       Evidence
                   \        /
                    \      /
                     ▼    ▼
                     REPORT

Le point important est que l'executor ne connaît pas la logique métier du test. Il sait seulement :

test ID
   +
image
   +
topology
   ↓
Kubernetes Job
   ↓
result + logs + evidence
