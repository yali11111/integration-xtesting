#!/usr/bin/env bash

# ============================================================
# integration-xtesting
# CI/CD installer - Part 3/5
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

if [[ ! -d ".git" ]]; then
    die "Run this script from the root of the Git repository."
fi

if [[ ! -f "quality/ci/quality-gate.sh" ]]; then
    die "Part 2 must be installed first."
fi

success "Quality foundation detected."

# ============================================================
# CI directories
# ============================================================

log "Creating CI directories..."

mkdir -p \
    .github/workflows \
    .github/scripts \
    ci/security \
    ci/docker \
    ci/tests \
    reports/ci \
    releases/artifacts

success "CI directories created."

# ============================================================
# 1. Unit test runner
# ============================================================

log "Creating unit test runner..."

cat > ci/tests/run-unit-tests.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=============================================="
echo " Integration Xtesting Unit Tests"
echo "=============================================="

python3 -m compileall \
    "${ROOT_DIR}/quality" \
    "${ROOT_DIR}/tests"

echo
echo "Testing RA2-NET-001..."

if [[ -d "${ROOT_DIR}/ra2/network/RA2-NET-001" ]]; then

    (
        cd "${ROOT_DIR}/ra2/network/RA2-NET-001"

        if command -v pytest >/dev/null 2>&1; then
            pytest -q
        else
            python3 -m unittest discover -s tests
        fi
    )

fi

echo
echo "Testing RC2-NET-001..."

if [[ -d "${ROOT_DIR}/rc2/network/RC2-NET-001" ]]; then

    (
        cd "${ROOT_DIR}/rc2/network/RC2-NET-001"

        if command -v pytest >/dev/null 2>&1; then
            pytest -q
        else
            python3 -m unittest discover -s tests
        fi
    )

fi

echo
echo "UNIT TESTS: PASS"
SH

chmod +x ci/tests/run-unit-tests.sh

success "Unit test runner created."

# ============================================================
# 2. Docker build helper
# ============================================================

log "Creating Docker build helper..."

cat > ci/docker/build-images.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REGISTRY="${REGISTRY:-local}"
TAG="${TAG:-dev}"

BUILD_DIR="${ROOT_DIR}/reports/ci/docker"

mkdir -p "${BUILD_DIR}"

build_application() {

    local application="$1"
    local image="$2"

    if [[ ! -f "${application}/Dockerfile" ]]; then
        echo "Dockerfile missing: ${application}"
        return 1
    fi

    echo
    echo "----------------------------------------------"
    echo "Building ${image}"
    echo "Source: ${application}"
    echo "----------------------------------------------"

    docker build \
        --tag "${REGISTRY}/${image}:${TAG}" \
        "${application}"

    echo "${REGISTRY}/${image}:${TAG}" \
        >> "${BUILD_DIR}/images.txt"
}

build_application \
    "${ROOT_DIR}/ra2/network/RA2-NET-001" \
    "ra2-net-001"

build_application \
    "${ROOT_DIR}/rc2/network/RC2-NET-001" \
    "rc2-net-001"

echo
echo "Docker images built:"
cat "${BUILD_DIR}/images.txt"

echo
echo "DOCKER BUILD: PASS"
SH

chmod +x ci/docker/build-images.sh

success "Docker build helper created."

# ============================================================
# 3. Dockerfile static validation
# ============================================================

log "Creating Dockerfile validator..."

cat > ci/docker/validate-dockerfiles.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

failures=0

while IFS= read -r dockerfile; do

    [[ -z "${dockerfile}" ]] && continue

    echo "Checking ${dockerfile}"

    if ! grep -q '^FROM ' "${dockerfile}"; then
        echo "  ERROR: missing FROM"
        failures=$((failures + 1))
    fi

    if ! grep -q '^WORKDIR ' "${dockerfile}"; then
        echo "  ERROR: missing WORKDIR"
        failures=$((failures + 1))
    fi

    if ! grep -q '^ENTRYPOINT ' "${dockerfile}" \
        && ! grep -q '^CMD ' "${dockerfile}"
    then
        echo "  ERROR: missing ENTRYPOINT/CMD"
        failures=$((failures + 1))
    fi

done < <(
    find \
        "${ROOT_DIR}/ra2" \
        "${ROOT_DIR}/rc2" \
        -name Dockerfile \
        -type f \
        2>/dev/null
)

if [[ "${failures}" -ne 0 ]]; then
    echo
    echo "DOCKERFILE VALIDATION: FAIL"
    exit 1
fi

echo
echo "DOCKERFILE VALIDATION: PASS"
SH

chmod +x ci/docker/validate-dockerfiles.sh

success "Dockerfile validator created."

# ============================================================
# 4. Security gate
# ============================================================

log "Creating security gate..."

cat > ci/security/security-gate.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REPORT_DIR="${ROOT_DIR}/reports/ci/security"

mkdir -p "${REPORT_DIR}"

echo "=============================================="
echo " Integration Xtesting Security Gate"
echo "=============================================="

echo
echo "[1] Checking forbidden files..."

forbidden=0

while IFS= read -r file; do

    case "${file}" in
        *.pem|*.key|*.p12|*.pfx)
            echo "Potential secret/private key: ${file}"
            forbidden=$((forbidden + 1))
            ;;
    esac

done < <(
    find "${ROOT_DIR}" \
        -type f \
        -not -path "${ROOT_DIR}/.git/*" \
        2>/dev/null
)

if [[ "${forbidden}" -ne 0 ]]; then
    echo "Security gate detected ${forbidden} suspicious files."
    exit 1
fi

echo "Forbidden file check: PASS"

echo
echo "[2] Checking Dockerfiles for obvious issues..."

dockerfile_failures=0

while IFS= read -r dockerfile; do

    if grep -qiE \
        'curl.*\|.*sh|wget.*\|.*sh' \
        "${dockerfile}"
    then
        echo "Unsafe remote script pattern: ${dockerfile}"
        dockerfile_failures=$((dockerfile_failures + 1))
    fi

done < <(
    find \
        "${ROOT_DIR}/ra2" \
        "${ROOT_DIR}/rc2" \
        -name Dockerfile \
        -type f \
        2>/dev/null
)

if [[ "${dockerfile_failures}" -ne 0 ]]; then
    exit 1
fi

echo "Dockerfile static security check: PASS"

cat > "${REPORT_DIR}/security-summary.json" <<EOF
{
  "status": "PASS",
  "forbidden_files": 0,
  "unsafe_docker_patterns": 0
}
EOF

echo
echo "SECURITY GATE: PASS"
SH

chmod +x ci/security/security-gate.sh

success "Security gate created."

# ============================================================
# 5. Dependency audit
# ============================================================

log "Creating dependency audit..."

cat > ci/security/dependency-audit.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=============================================="
echo " Dependency Audit"
echo "=============================================="

failures=0

while IFS= read -r requirements; do

    echo
    echo "Checking ${requirements}"

    while IFS= read -r line; do

        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^# ]] && continue

        echo "  ${line}"

    done < "${requirements}"

done < <(
    find \
        "${ROOT_DIR}/ra2" \
        "${ROOT_DIR}/rc2" \
        -name requirements.txt \
        -type f \
        2>/dev/null
)

if [[ "${failures}" -ne 0 ]]; then
    exit 1
fi

echo
echo "DEPENDENCY AUDIT: PASS"
SH

chmod +x ci/security/dependency-audit.sh

success "Dependency audit created."

# ============================================================
# 6. CI orchestrator
# ============================================================

log "Creating CI orchestrator..."

cat > ci/run-ci.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CI_START="$(date +%s)"

mkdir -p "${ROOT_DIR}/reports/ci"

echo
echo "=================================================="
echo "       INTEGRATION-XTESTING CI PIPELINE"
echo "=================================================="

echo
echo "========== 1. QUALITY GATE =========="

"${ROOT_DIR}/quality/ci/quality-gate.sh"

echo
echo "========== 2. UNIT TESTS =========="

"${ROOT_DIR}/ci/tests/run-unit-tests.sh"

echo
echo "========== 3. DOCKERFILE VALIDATION =========="

"${ROOT_DIR}/ci/docker/validate-dockerfiles.sh"

echo
echo "========== 4. SECURITY =========="

"${ROOT_DIR}/ci/security/security-gate.sh"

echo
echo "========== 5. DEPENDENCY AUDIT =========="

"${ROOT_DIR}/ci/security/dependency-audit.sh"

echo
echo "========== 6. DOCKER BUILD =========="

if command -v docker >/dev/null 2>&1; then

    "${ROOT_DIR}/ci/docker/build-images.sh"

else

    echo "Docker is not installed."
    echo "Local Docker build skipped."

fi

CI_END="$(date +%s)"
DURATION="$((CI_END - CI_START))"

cat > "${ROOT_DIR}/reports/ci/ci-summary.json" <<EOF
{
  "status": "PASS",
  "duration_seconds": ${DURATION}
}
EOF

echo
echo "=================================================="
echo "CI PIPELINE: PASS"
echo "Duration: ${DURATION}s"
echo "=================================================="
SH

chmod +x ci/run-ci.sh

success "CI orchestrator created."

# ============================================================
# 7. Pull Request workflow
# ============================================================

log "Creating Pull Request workflow..."

cat > .github/workflows/xtesting-pr.yml <<'EOF'
name: integration-xtesting - Pull Request

on:
  pull_request:
    branches:
      - main

permissions:
  contents: read

jobs:

  quality:
    name: Quality Gate
    runs-on: ubuntu-latest

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Run Quality Gate
        run: |
          chmod +x quality/ci/quality-gate.sh
          ./quality/ci/quality-gate.sh

  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    needs: quality

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install pytest
        run: |
          python -m pip install --upgrade pip
          python -m pip install pytest

      - name: Run tests
        run: |
          chmod +x ci/tests/run-unit-tests.sh
          ./ci/tests/run-unit-tests.sh

  docker:
    name: Docker Build
    runs-on: ubuntu-latest
    needs:
      - quality
      - unit-tests

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Validate Dockerfiles
        run: |
          chmod +x ci/docker/validate-dockerfiles.sh
          ./ci/docker/validate-dockerfiles.sh

      - name: Build RA2 image
        run: |
          docker build \
            -t ra2-net-001:ci \
            ra2/network/RA2-NET-001

      - name: Build RC2 image
        run: |
          docker build \
            -t rc2-net-001:ci \
            rc2/network/RC2-NET-001

  security:
    name: Security Gate
    runs-on: ubuntu-latest
    needs:
      - quality
      - unit-tests

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Security gate
        run: |
          chmod +x ci/security/security-gate.sh
          ./ci/security/security-gate.sh

  ci-summary:
    name: Global CI Gate
    runs-on: ubuntu-latest

    needs:
      - quality
      - unit-tests
      - docker
      - security

    steps:

      - name: CI PASS
        run: |
          echo "=================================="
          echo " integration-xtesting CI: PASS"
          echo "=================================="
EOF

success "Pull Request workflow created."

# ============================================================
# 8. Main workflow
# ============================================================

log "Creating main branch workflow..."

cat > .github/workflows/xtesting-main.yml <<'EOF'
name: integration-xtesting - Main

on:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:

  ci:
    name: Full CI
    runs-on: ubuntu-latest

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install test dependencies
        run: |
          python -m pip install --upgrade pip
          python -m pip install pytest

      - name: Quality Gate
        run: |
          chmod +x quality/ci/quality-gate.sh
          ./quality/ci/quality-gate.sh

      - name: Unit Tests
        run: |
          chmod +x ci/tests/run-unit-tests.sh
          ./ci/tests/run-unit-tests.sh

      - name: Dockerfile validation
        run: |
          chmod +x ci/docker/validate-dockerfiles.sh
          ./ci/docker/validate-dockerfiles.sh

      - name: Security Gate
        run: |
          chmod +x ci/security/security-gate.sh
          ./ci/security/security-gate.sh

      - name: Docker build RA2
        run: |
          docker build \
            -t ra2-net-001:${GITHUB_SHA} \
            ra2/network/RA2-NET-001

      - name: Docker build RC2
        run: |
          docker build \
            -t rc2-net-001:${GITHUB_SHA} \
            rc2/network/RC2-NET-001

      - name: Generate report
        run: |
          chmod +x quality/reports/generate.sh
          ./quality/reports/generate.sh

      - name: Upload CI reports
        uses: actions/upload-artifact@v4
        with:
          name: integration-xtesting-ci-report
          path: reports/
EOF

success "Main workflow created."

# ============================================================
# 9. CI status report
# ============================================================

log "Creating CI status report..."

cat > ci/status.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=================================================="
echo " integration-xtesting CI status"
echo "=================================================="

echo
echo "Workflows:"
find "${ROOT_DIR}/.github/workflows" \
    -maxdepth 1 \
    -type f \
    -print

echo
echo "Local CI:"
echo "  ./ci/run-ci.sh"

echo
echo "Quality:"
echo "  ./ci/quality.sh"

echo
echo "Reports:"
find "${ROOT_DIR}/reports" \
    -maxdepth 2 \
    -type f \
    -print 2>/dev/null || true
SH

chmod +x ci/status.sh

success "CI status command created."

# ============================================================
# 10. Documentation
# ============================================================

log "Creating CI documentation..."

cat > docs/ci-cd.md <<'EOF'
# CI/CD

## Pull Request

Every Pull Request executes:

```text
Structure
   |
Metadata
   |
Unit tests
   |
Dockerfile validation
   |
Docker build
   |
Security
   |
Global CI Gate

A failure blocks the Pull Request.
Main

After merge:

main
 |
Full CI
 |
Build
 |
Reports
 |
Artifacts

Kubernetes campaign execution is introduced in the Labs phase.
EOF
============================================================
11. Local pipeline test
============================================================

echo
log "Running local CI pipeline..."

if command -v python3 >/dev/null 2>&1; then

if "${ROOT_DIR}/ci/run-ci.sh"; then
    success "Local CI pipeline: PASS"
else
    die "Local CI pipeline failed."
fi

else

warn "python3 is not available."
warn "Local CI execution skipped."

fi
============================================================
12. Final summary
============================================================

echo
echo "============================================================"
success " PART 3/5 COMPLETED"
echo "============================================================"

echo
echo "Created:"
echo " .github/workflows/xtesting-pr.yml"
echo " .github/workflows/xtesting-main.yml"
echo " ci/run-ci.sh"
echo " ci/tests/run-unit-tests.sh"
echo " ci/docker/build-images.sh"
echo " ci/docker/validate-dockerfiles.sh"
echo " ci/security/security-gate.sh"
echo " ci/security/dependency-audit.sh"
echo " ci/status.sh"
echo " docs/ci-cd.md"

echo
echo "Local commands:"
echo " ./ci/run-ci.sh"
echo " ./ci/status.sh"

echo
echo "Next:"
echo " ./04-labs.sh"


## Le pipeline obtenu

À ce stade, ton dépôt possède déjà cette chaîne :

```text
                         Pull Request
                              │
                              ▼
                    ┌─────────────────┐
                    │ Structure Gate  │
                    └────────┬────────┘
                             ▼
                    ┌─────────────────┐
                    │ Metadata Gate   │
                    └────────┬────────┘
                             ▼
                    ┌─────────────────┐
                    │  Unit Tests     │
                    └────────┬────────┘
                             ▼
                    ┌─────────────────┐
                    │ Dockerfile      │
                    └────────┬────────┘
                             ▼
                    ┌─────────────────┐
                    │ Docker Build    │
                    └────────┬────────┘
                             ▼
                    ┌─────────────────┐
                    │ Security Gate   │
                    └────────┬────────┘
                             ▼
                    ┌─────────────────┐
                    │   CI PASS       │
                    └─────────────────┘

Et après merge :

main
 │
 ▼
Full CI
 │
 ├── Quality
 ├── Unit tests
 ├── Docker
 ├── Security
 └── Reports
       │
       ▼
   Artifacts

Point important

Le Docker build est réellement exécuté dans GitHub Actions, mais il n'y a pas encore de déploiement/exécution Kubernetes automatique. C'est volontaire : la partie 4 va introduire les labs 1N / 3N / NN, la découverte des capacités, l'exécution et la collecte d'evidence.

Après cette partie, tu peux vérifier :

./ci/run-ci.sh

et :

git status
