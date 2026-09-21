#!/usr/bin/env bash
============================================================
integration-xtesting
Foundation installer - Part 1/5
Usage:
chmod +x 01-foundation.sh
./01-foundation.sh
This script:
- creates the target foundation tree
- creates the common test contract
- creates metadata schema
- creates RA2-NET-001
- creates RC2-NET-001
- does NOT modify existing test families
============================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly ROOT_DIR="$(pwd)"
------------------------------------------------------------
Colors
------------------------------------------------------------

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
------------------------------------------------------------
Error handling
------------------------------------------------------------

trap 'error "Installation failed at line ${LINENO}: ${BASH_COMMAND}"' ERR
------------------------------------------------------------
Repository validation
------------------------------------------------------------

log "Checking repository..."

if [[ ! -d ".git" ]]; then
die "This script must be executed from the root of a Git repository."
fi

if [[ ! -f "README.md" ]]; then
warn "README.md not found. Continuing."
fi

success "Repository detected: ${ROOT_DIR}"
------------------------------------------------------------
Create directories
------------------------------------------------------------

log "Creating foundation directories..."

mkdir -p
quality/structure
quality/metadata
quality/ci
quality/reproducibility
quality/security
tests/contract
tests/executor
tests/evidence
tests/reporting
ra2/compute
ra2/network
ra2/storage
ra2/lifecycle
ra2/observability
rc2/compute
rc2/network
rc2/storage
rc2/security
rc2/lifecycle
reliability/availability
reliability/resilience
reliability/recovery
labs/1n
labs/3n
labs/nn
campaigns/default
campaigns/ra2
campaigns/rc2
reports
ci
docs
releases

success "Foundation directories created."
------------------------------------------------------------
Common test contract
------------------------------------------------------------

log "Creating common test contract..."

cat > tests/contract/test-application-contract.yaml <<'EOF'
version: "1.0"

required_files:

    Dockerfile

    README.md

    metadata.yaml

    run.sh

required_directories:

    src

    tests

metadata_required:

    id

    name

    version

    classification

    execution

    topology

    outputs

supported_families:

    RA2

    RC2

    EXISTING

supported_topologies:

    1N

    3N

    NN

required_outputs:

    junit

    json

    evidence
    EOF

success "Common test contract created."
------------------------------------------------------------
Metadata schema
------------------------------------------------------------

log "Creating metadata schema..."

cat > tests/contract/metadata.schema.yaml <<'EOF'
$schema: "https://json-schema.org/draft/2020-12/schema"

title: Integration Xtesting Test Application Metadata

type: object

required:

    id

    name

    version

    classification

    execution

    topology

    outputs

properties:

id:
type: string
pattern: "^(RA2|RC2|EXISTING)-[A-Z0-9-]+$"

name:
type: string
minLength: 1

version:
type: string
pattern: "^[0-9]+\.[0-9]+\.[0-9]+$"

classification:
type: object
required:
- family
- domain

properties:
  family:
    type: string
    enum:
      - RA2
      - RC2
      - EXISTING

  domain:
    type: string

execution:
type: object
required:
- command

properties:
  command:
    type: array
    minItems: 1
    items:
      type: string

  timeout:
    type: integer
    minimum: 1

topology:
type: object
required:
- 1N
- 3N
- NN

properties:
  1N:
    type: boolean

  3N:
    type: boolean

  NN:
    type: boolean

outputs:
type: object
required:
- junit
- json
- evidence

properties:
  junit:
    type: boolean

  json:
    type: boolean

  evidence:
    type: boolean

EOF

success "Metadata schema created."
------------------------------------------------------------
Result contract
------------------------------------------------------------

log "Creating result contract..."

cat > tests/contract/result-contract.json <<'EOF'
{
"$schema": "https://json-schema.org/draft/2020-12/schema",
"title": "Integration Xtesting Result",
"type": "object",
"required": [
"test",
"status",
"execution"
],
"properties": {
"test": {
"type": "object",
"required": [
"id",
"version",
"family"
]
},
"status": {
"type": "string",
"enum": [
"PASS",
"FAIL",
"ERROR",
"TIMEOUT",
"NOT_APPLICABLE",
"NOT_EXECUTED",
"SKIPPED"
]
},
"execution": {
"type": "object",
"required": [
"topology"
]
}
}
}
EOF

success "Result contract created."
------------------------------------------------------------
Exit codes
------------------------------------------------------------

log "Creating standard exit codes..."

cat > tests/contract/exit-codes.sh <<'EOF'
#!/usr/bin/env bash
Integration Xtesting standard exit codes

readonly XT_EXIT_PASS=0
readonly XT_EXIT_FAIL=1
readonly XT_EXIT_ERROR=2
readonly XT_EXIT_TIMEOUT=3
readonly XT_EXIT_NOT_APPLICABLE=4
readonly XT_EXIT_NOT_EXECUTED=5
readonly XT_EXIT_SKIPPED=6
EOF

chmod +x tests/contract/exit-codes.sh

success "Exit code contract created."
------------------------------------------------------------
Test runner skeleton
------------------------------------------------------------

log "Creating common runner skeleton..."

cat > tests/executor/runner.sh <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ID="${TEST_ID:-unknown}"
TEST_VERSION="${TEST_VERSION:-unknown}"
TOPOLOGY="${TOPOLOGY:-unknown}"

RESULT_DIR="${RESULT_DIR:-/tmp/xtesting-results}"

mkdir -p "${RESULT_DIR}/evidence"

START_TIME="$(date +%s)"

echo "========================================"
echo " Integration Xtesting Test Runner"
echo "========================================"
echo "Test: ${TEST_ID}"
echo "Version: ${TEST_VERSION}"
echo "Topology: ${TOPOLOGY}"
echo "========================================"
The concrete test implementation is responsible
for executing its functional checks.

END_TIME="$(date +%s)"
DURATION="$((END_TIME - START_TIME))"

echo "Execution completed in ${DURATION}s"
EOF

chmod +x tests/executor/runner.sh

success "Common runner skeleton created."
------------------------------------------------------------
Evidence directory convention
------------------------------------------------------------

log "Creating evidence convention..."

cat > tests/evidence/README.md <<'EOF'
Evidence Convention

Every test execution may produce evidence under:

results/
└── evidence/


Evidence should be:

deterministic;

machine-readable where possible;

associated with the test execution;

included in the final campaign artifact.

Typical examples:

Kubernetes objects;

network information;

storage information;

configuration;

command output;

logs;

screenshots or other binary artifacts when applicable.
EOF

------------------------------------------------------------
Reporting convention
------------------------------------------------------------

cat > tests/reporting/README.md <<'EOF'

Reporting Convention

Every Test Application should produce, when applicable:

result.json

junit.xml

logs.txt

evidence/

The JSON result is the machine-readable canonical result.

JUnit exists for CI/CD integrations.

Evidence provides traceability and diagnostic information.
EOF

success "Evidence and reporting conventions created."

============================================================
RA2-NET-001
============================================================

log "Creating RA2-NET-001..."

RA2_DIR="ra2/network/RA2-NET-001"

mkdir -p
"${RA2_DIR}/src"
"${RA2_DIR}/tests"

cat > "${RA2_DIR}/metadata.yaml" <<'EOF'
id: RA2-NET-001

name: Network Connectivity Validation

version: 1.0.0

classification:
family: RA2
domain: network

execution:
command:
- /test/run.sh
timeout: 900

topology:
1N: true
3N: true
NN: true

outputs:
junit: true
json: true
evidence: true
EOF

cat > "${RA2_DIR}/Dockerfile" <<'EOF'
FROM python:3.12-slim

WORKDIR /test

COPY requirements.txt .

RUN pip install
--no-cache-dir
-r requirements.txt

COPY src ./src
COPY run.sh .

RUN chmod +x run.sh

ENTRYPOINT ["/test/run.sh"]
EOF

cat > "${RA2_DIR}/requirements.txt" <<'EOF'
pytest>=8,<9
EOF

cat > "${RA2_DIR}/run.sh" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

RESULT_DIR="${RESULT_DIR:-/test/results}"

mkdir -p "${RESULT_DIR}/evidence"

export RESULT_DIR

python3 /test/src/test_network.py
EOF

chmod +x "${RA2_DIR}/run.sh"

cat > "${RA2_DIR}/src/test_network.py" <<'EOF'
#!/usr/bin/env python3

import json
import os
import sys
from pathlib import Path

def main() -> int:
result_dir = Path(
os.environ.get("RESULT_DIR", "/test/results")
)

result_dir.mkdir(
    parents=True,
    exist_ok=True
)

topology = os.environ.get(
    "TOPOLOGY",
    "unknown"
)

result = {
    "test": {
        "id": "RA2-NET-001",
        "version": "1.0.0",
        "family": "RA2"
    },
    "status": "PASS",
    "execution": {
        "topology": topology
    }
}

output = result_dir / "result.json"

output.write_text(
    json.dumps(result, indent=2),
    encoding="utf-8"
)

print(json.dumps(result, indent=2))

return 0


if name == "main":
sys.exit(main())
EOF

cat > "${RA2_DIR}/tests/test_network.py" <<'EOF'
def test_ra2_network_identity():
assert "RA2-NET-001" == "RA2-NET-001"
EOF

cat > "${RA2_DIR}/README.md" <<'EOF'

RA2-NET-001

Network Connectivity Validation.

Family

RA2

Domain

Network

Supported topologies

1N

3N

NN

Execution
./run.sh


The test produces JSON results under the configured result directory.
EOF

success "RA2-NET-001 created."

============================================================
RC2-NET-001
============================================================

log "Creating RC2-NET-001..."

RC2_DIR="rc2/network/RC2-NET-001"

mkdir -p
"${RC2_DIR}/src"
"${RC2_DIR}/tests"

cat > "${RC2_DIR}/metadata.yaml" <<'EOF'
id: RC2-NET-001

name: Network Security Validation

version: 1.0.0

classification:
family: RC2
domain: network

execution:
command:
- /test/run.sh
timeout: 900

topology:
1N: true
3N: true
NN: true

outputs:
junit: true
json: true
evidence: true
EOF

cat > "${RC2_DIR}/Dockerfile" <<'EOF'
FROM python:3.12-slim

WORKDIR /test

COPY requirements.txt .

RUN pip install
--no-cache-dir
-r requirements.txt

COPY src ./src
COPY run.sh .

RUN chmod +x run.sh

ENTRYPOINT ["/test/run.sh"]
EOF

cat > "${RC2_DIR}/requirements.txt" <<'EOF'
pytest>=8,<9
EOF

cat > "${RC2_DIR}/run.sh" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

RESULT_DIR="${RESULT_DIR:-/test/results}"

mkdir -p "${RESULT_DIR}/evidence"

export RESULT_DIR

python3 /test/src/test_network_security.py
EOF

chmod +x "${RC2_DIR}/run.sh"

cat > "${RC2_DIR}/src/test_network_security.py" <<'EOF'
#!/usr/bin/env python3

import json
import os
import sys
from pathlib import Path

def main() -> int:
result_dir = Path(
os.environ.get("RESULT_DIR", "/test/results")
)

result_dir.mkdir(
    parents=True,
    exist_ok=True
)

topology = os.environ.get(
    "TOPOLOGY",
    "unknown"
)

result = {
    "test": {
        "id": "RC2-NET-001",
        "version": "1.0.0",
        "family": "RC2"
    },
    "status": "PASS",
    "execution": {
        "topology": topology
    }
}

output = result_dir / "result.json"

output.write_text(
    json.dumps(result, indent=2),
    encoding="utf-8"
)

print(json.dumps(result, indent=2))

return 0


if name == "main":
sys.exit(main())
EOF

cat > "${RC2_DIR}/tests/test_network_security.py" <<'EOF'
def test_rc2_network_identity():
assert "RC2-NET-001" == "RC2-NET-001"
EOF

cat > "${RC2_DIR}/README.md" <<'EOF'

RC2-NET-001

Network Security Validation.

Family

RC2

Domain

Network

Supported topologies

1N

3N

NN

Execution
./run.sh


The test produces JSON results under the configured result directory.
EOF

success "RC2-NET-001 created."

------------------------------------------------------------
Campaign definitions
------------------------------------------------------------

log "Creating initial campaign definitions..."

cat > campaigns/default/campaign.yaml <<'EOF'
name: default

tests:

RA2-NET-001

RC2-NET-001

topologies:

1N

3N

NN
EOF

cat > campaigns/ra2/campaign.yaml <<'EOF'
name: ra2

tests:

RA2-NET-001

topologies:

1N

3N

NN
EOF

cat > campaigns/rc2/campaign.yaml <<'EOF'
name: rc2

tests:

RC2-NET-001

topologies:

1N

3N

NN
EOF

success "Campaign definitions created."

------------------------------------------------------------
Lab definitions
------------------------------------------------------------

log "Creating lab placeholders..."

cat > labs/1n/lab.yaml <<'EOF'
name: LAB-1N

topology: 1N

nodes: 1

enabled: true
EOF

cat > labs/3n/lab.yaml <<'EOF'
name: LAB-3N

topology: 3N

nodes: 3

enabled: true
EOF

cat > labs/nn/lab.yaml <<'EOF'
name: LAB-NN

topology: NN

nodes: dynamic

enabled: false
EOF

success "Lab definitions created."

------------------------------------------------------------
Documentation
------------------------------------------------------------

log "Creating foundation documentation..."

cat > docs/architecture.md <<'EOF'

Integration Xtesting Architecture

The target architecture separates:

test applications;

test execution;

Kubernetes labs;

evidence;

reporting;

CI/CD;

quality measurement.

Test applications are classified into families such as:

RA2;

RC2;

EXISTING.

RA2 and RC2 share the same technical contract and execution framework.
EOF

cat > docs/test-lifecycle.md <<'EOF'

Test Lifecycle
User Story
    |
Development
    |
Pull Request
    |
CI Quality Gates
    |
Merge
    |
Campaign
    |
1N / 3N / NN
    |
Evidence
    |
Reports
    |
SLI / SLO
    |
Release Gate
    |
Release


EOF

cat > docs/sli-slo.md <<'EOF'

SLI / SLO

Initial SLI candidates:

CI success rate

structure compliance

metadata compliance

topology coverage

execution success rate

evidence completeness

report generation success

release success

Initial targets will be formalized in the Quality phase.
EOF

cat > docs/contribution.md <<'EOF'

Contribution

New Test Applications should:

follow the common contract;

provide metadata.yaml;

provide Dockerfile;

provide run.sh;

provide src/;

provide tests/;

produce standardized results;

declare supported topologies.
EOF

success "Documentation created."

------------------------------------------------------------
Foundation README
------------------------------------------------------------

cat > quality/README.md <<'EOF'

Quality

This directory contains validation of the integration-xtesting
Test Factory itself.

It is intentionally separated from the functional tests executed
against Kubernetes environments.
EOF

cat > ra2/README.md <<'EOF'

RA2

RA2 Test Applications.

Each application follows the common Test Application contract.
EOF

cat > rc2/README.md <<'EOF'

RC2

RC2 Test Applications.

Each application follows the common Test Application contract.
EOF

------------------------------------------------------------
Git status
------------------------------------------------------------

log "Checking generated files..."

git status --short

echo
success "============================================================"
success " Foundation installation completed."
success "============================================================"

echo
log "Created:"
echo " - quality/"
echo " - tests/"
echo " - ra2/"
echo " - rc2/"
echo " - reliability/"
echo " - labs/"
echo " - campaigns/"
echo " - reports/"
echo " - ci/"
echo " - docs/"
echo " - releases/"

echo
log "Pilot applications:"
echo " - RA2-NET-001"
echo " - RC2-NET-001"

echo
log "No existing test family was moved or deleted."

echo
log "Next step:"
echo " ./02-quality.sh"


### Ce que cette partie installe

Après exécution :

```text
integration-xtesting/
├── quality/
├── tests/
│   ├── contract/
│   ├── executor/
│   ├── evidence/
│   └── reporting/
├── ra2/
│   └── network/
│       └── RA2-NET-001/
├── rc2/
│   └── network/
│       └── RC2-NET-001/
├── reliability/
├── labs/
│   ├── 1n/
│   ├── 3n/
│   └── nn/
├── campaigns/
├── reports/
├── ci/
├── releases/
└── docs/
