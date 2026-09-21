#!/usr/bin/env bash
============================================================
integration-xtesting
Quality / SLI / SLO installer - Part 2/5
Usage:
chmod +x 02-quality.sh
./02-quality.sh
This script installs:
- structure validator
- metadata validator
- test validator
- SLI calculation
- SLO definition
- SLO evaluator
- global quality gate
It does NOT modify existing test families.
============================================================

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
============================================================
Repository validation
============================================================

log "Checking repository..."

if [[ ! -d ".git" ]]; then
die "Run this script from the root of the integration-xtesting Git repository."
fi

if [[ ! -f "tests/contract/test-application-contract.yaml" ]]; then
die "Part 1 must be installed first."
fi

success "Foundation detected."
============================================================
Quality directory
============================================================

log "Creating Quality directories..."

mkdir -p
quality/structure
quality/metadata
quality/ci
quality/reproducibility
quality/security
quality/sli
quality/slo
quality/reports

success "Quality directories ready."
============================================================
1. Structure validator
============================================================

log "Creating structure validator..."

cat > quality/structure/validate.py <<'PY'
#!/usr/bin/env python3

"""
Integration Xtesting Test Application structure validator.

Usage:

python3 quality/structure/validate.py ra2/network/RA2-NET-001

Exit codes:

0 = PASS
1 = validation failure
2 = execution error

"""

from future import annotations

import sys
from pathlib import Path

REQUIRED_FILES = (
"Dockerfile",
"README.md",
"metadata.yaml",
"run.sh",
)

REQUIRED_DIRECTORIES = (
"src",
"tests",
)

def validate(application: Path) -> list[str]:
errors: list[str] = []

if not application.exists():
    errors.append(f"Application does not exist: {application}")
    return errors

if not application.is_dir():
    errors.append(f"Application is not a directory: {application}")
    return errors

for filename in REQUIRED_FILES:
    path = application / filename

    if not path.is_file():
        errors.append(f"Missing required file: {path}")

for dirname in REQUIRED_DIRECTORIES:
    path = application / dirname

    if not path.is_dir():
        errors.append(f"Missing required directory: {path}")

run_script = application / "run.sh"

if run_script.exists():
    if not run_script.stat().st_mode & 0o111:
        errors.append(f"run.sh is not executable: {run_script}")

return errors

def main() -> int:
if len(sys.argv) != 2:
print(
"Usage: validate.py <test-application>",
file=sys.stderr,
)
return 2

application = Path(sys.argv[1])

errors = validate(application)

if errors:
    print("STRUCTURE: FAIL")

    for error in errors:
        print(f"  - {error}")

    return 1

print(f"STRUCTURE: PASS - {application}")

return 0

if name == "main":
sys.exit(main())
PY

chmod +x quality/structure/validate.py

success "Structure validator created."
============================================================
2. Metadata validator
============================================================

log "Creating metadata validator..."

cat > quality/metadata/validate.py <<'PY'
#!/usr/bin/env python3

"""
Integration Xtesting metadata validator.

This validator deliberately uses only Python standard library
functionality so the Quality Gate can run before application
dependencies are installed.
"""

from future import annotations

import re
import sys
from pathlib import Path

VERSION_RE = re.compile(
r"^[0-9]+.[0-9]+.[0-9]+$"
)

ID_RE = re.compile(
r"^(RA2|RC2|EXISTING)-[A-Z0-9-]+$"
)

REQUIRED_TOP_LEVEL = (
"id",
"name",
"version",
"classification",
"execution",
"topology",
"outputs",
)

def parse_simple_yaml(path: Path) -> dict:
"""
Minimal YAML parser for the controlled metadata structure.

This is intentionally conservative. The full YAML parser can
be introduced later as a CI dependency.
"""

result: dict = {}
section = None

for raw_line in path.read_text(
    encoding="utf-8"
).splitlines():

    line = raw_line.strip()

    if not line or line.startswith("#"):
        continue

    if not raw_line.startswith(" "):
        if ":" in line:
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip()

            if value:
                result[key] = value
                section = None
            else:
                result[key] = {}
                section = key

        continue

    if section and ":" in line:
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()

        if isinstance(result.get(section), dict):
            result[section][key] = value

return result

def validate(path: Path) -> list[str]:
errors: list[str] = []

if not path.is_file():
    return [f"Missing metadata file: {path}"]

metadata = parse_simple_yaml(path)

for field in REQUIRED_TOP_LEVEL:
    if field not in metadata:
        errors.append(
            f"Missing required metadata field: {field}"
        )

test_id = metadata.get("id", "")

if test_id and not ID_RE.match(str(test_id)):
    errors.append(
        f"Invalid test id: {test_id}"
    )

version = metadata.get("version", "")

if version and not VERSION_RE.match(str(version)):
    errors.append(
        f"Invalid semantic version: {version}"
    )

classification = metadata.get(
    "classification",
    {},
)

if isinstance(classification, dict):
    family = classification.get("family")

    if family not in {
        "RA2",
        "RC2",
        "EXISTING",
    }:
        errors.append(
            f"Invalid family: {family}"
        )

execution = metadata.get(
    "execution",
    {},
)

if isinstance(execution, dict):
    if "command" not in execution:
        errors.append(
            "Missing execution.command"
        )

topology = metadata.get(
    "topology",
    {},
)

if isinstance(topology, dict):
    for name in ("1N", "3N", "NN"):
        if name not in topology:
            errors.append(
                f"Missing topology declaration: {name}"
            )

outputs = metadata.get(
    "outputs",
    {},
)

if isinstance(outputs, dict):
    for name in (
        "junit",
        "json",
        "evidence",
    ):
        if name not in outputs:
            errors.append(
                f"Missing output declaration: {name}"
            )

return errors

def main() -> int:
if len(sys.argv) != 2:
print(
"Usage: validate.py <metadata.yaml>",
file=sys.stderr,
)
return 2

metadata = Path(sys.argv[1])

errors = validate(metadata)

if errors:
    print("METADATA: FAIL")

    for error in errors:
        print(f"  - {error}")

    return 1

print(f"METADATA: PASS - {metadata}")

return 0

if name == "main":
sys.exit(main())
PY

chmod +x quality/metadata/validate.py

success "Metadata validator created."
============================================================
3. Application discovery
============================================================

log "Creating application discovery..."

cat > quality/structure/discover.py <<'PY'
#!/usr/bin/env python3

from pathlib import Path

ROOTS = (
Path("ra2"),
Path("rc2"),
)

def discover() -> list[Path]:
applications: list[Path] = []

for root in ROOTS:

    if not root.exists():
        continue

    for metadata in root.glob(
        "**/metadata.yaml"
    ):
        applications.append(
            metadata.parent
        )

return sorted(applications)

if name == "main":

for application in discover():
    print(application)

PY

chmod +x quality/structure/discover.py

success "Application discovery created."
============================================================
4. Complete validation
============================================================

log "Creating complete test validator..."

cat > quality/ci/validate-tests.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STRUCTURE="${ROOT_DIR}/quality/structure/validate.py"
METADATA="${ROOT_DIR}/quality/metadata/validate.py"
DISCOVER="${ROOT_DIR}/quality/structure/discover.py"

failures=0
applications=0

echo "=============================================="
echo " Integration Xtesting Test Validation"
echo "=============================================="

while IFS= read -r application; do

[[ -z "${application}" ]] && continue

applications=$((applications + 1))

echo
echo "Application: ${application}"

if ! python3 \
    "${STRUCTURE}" \
    "${application}"
then
    failures=$((failures + 1))
    continue
fi

if ! python3 \
    "${METADATA}" \
    "${application}/metadata.yaml"
then
    failures=$((failures + 1))
    continue
fi

done < <(
cd "${ROOT_DIR}"
python3 "${DISCOVER}"
)

echo
echo "=============================================="
echo "Applications: ${applications}"
echo "Failures: ${failures}"
echo "=============================================="

if [[ "${failures}" -ne 0 ]]; then
exit 1
fi

exit 0
SH

chmod +x quality/ci/validate-tests.sh

success "Complete test validator created."
============================================================
5. SLI definitions
============================================================

log "Creating SLI definitions..."

cat > quality/sli/slis.yaml <<'EOF'
version: "1.0"

slis:

    id: SLI-01
    name: ci_success_rate
    description: Successful CI pipelines divided by total CI pipelines
    unit: percentage

    id: SLI-02
    name: structure_compliance
    description: Applications respecting the Test Application contract
    unit: percentage

    id: SLI-03
    name: metadata_compliance
    description: Applications with valid metadata
    unit: percentage

    id: SLI-04
    name: execution_success_rate
    description: Successful test executions divided by total executions
    unit: percentage

    id: SLI-05
    name: topology_coverage
    description: Required topology executions actually performed
    unit: percentage

    id: SLI-06
    name: evidence_completeness
    description: Executions producing expected evidence
    unit: percentage

    id: SLI-07
    name: report_generation
    description: Executions producing valid reports
    unit: percentage

    id: SLI-08
    name: release_success_rate
    description: Releases passing all release gates
    unit: percentage
    EOF

success "SLI definitions created."
============================================================
6. SLO definitions
============================================================

log "Creating SLO definitions..."

cat > quality/slo/slos.yaml <<'EOF'
version: "1.0"

slos:

    id: SLO-01
    name: ci_reliability
    sli: SLI-01
    target: 95
    operator: ">="

    id: SLO-02
    name: structure_compliance
    sli: SLI-02
    target: 100
    operator: ">="

    id: SLO-03
    name: metadata_compliance
    sli: SLI-03
    target: 100
    operator: ">="

    id: SLO-04
    name: execution_success_rate
    sli: SLI-04
    target: 95
    operator: ">="

    id: SLO-05
    name: topology_coverage
    sli: SLI-05
    target: 95
    operator: ">="

    id: SLO-06
    name: evidence_completeness
    sli: SLI-06
    target: 100
    operator: ">="

    id: SLO-07
    name: report_generation
    sli: SLI-07
    target: 100
    operator: ">="

    id: SLO-08
    name: release_success_rate
    sli: SLI-08
    target: 99
    operator: ">="
    EOF

success "SLO definitions created."
============================================================
7. SLI calculator
============================================================

log "Creating SLI calculator..."

cat > quality/sli/calculate.py <<'PY'
#!/usr/bin/env python3

"""
Generic SLI calculator.

Usage:

python3 calculate.py successful total

Example:

python3 calculate.py 95 100

Result:

95.0

"""

from future import annotations

import sys

def calculate(successful: float, total: float) -> float:

if total == 0:
    return 0.0

return round(
    (successful / total) * 100,
    2,
)

def main() -> int:

if len(sys.argv) != 3:
    print(
        "Usage: calculate.py <successful> <total>",
        file=sys.stderr,
    )
    return 2

successful = float(sys.argv[1])
total = float(sys.argv[2])

if successful < 0 or total < 0:
    print(
        "Values must be positive",
        file=sys.stderr,
    )
    return 2

if successful > total:
    print(
        "Successful value cannot exceed total",
        file=sys.stderr,
    )
    return 2

print(calculate(successful, total))

return 0

if name == "main":
sys.exit(main())
PY

chmod +x quality/sli/calculate.py

success "SLI calculator created."
============================================================
8. SLO evaluator
============================================================

log "Creating SLO evaluator..."

cat > quality/slo/evaluate.py <<'PY'
#!/usr/bin/env python3

"""
SLO evaluator.

Usage:

python3 evaluate.py <actual> <target>

Exit codes:

0 = PASS
1 = FAIL
2 = invalid usage

"""

from future import annotations

import sys

def main() -> int:

if len(sys.argv) != 3:
    print(
        "Usage: evaluate.py <actual> <target>",
        file=sys.stderr,
    )
    return 2

actual = float(sys.argv[1])
target = float(sys.argv[2])

passed = actual >= target

print(
    f"actual={actual} target={target}"
)

if passed:
    print("SLO: PASS")
    return 0

print("SLO: FAIL")

return 1

if name == "main":
sys.exit(main())
PY

chmod +x quality/slo/evaluate.py

success "SLO evaluator created."
============================================================
9. Quality Gate
============================================================

log "Creating global Quality Gate..."

cat > quality/ci/quality-gate.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=================================================="
echo " INTEGRATION-XTESTING QUALITY GATE"
echo "=================================================="

echo
echo "[1/3] Structure + Metadata validation"

if ! "${ROOT_DIR}/quality/ci/validate-tests.sh"; then
echo
echo "QUALITY GATE: FAIL"
exit 1
fi

echo
echo "[2/3] Foundation contract"

if [[ ! -f
"${ROOT_DIR}/tests/contract/test-application-contract.yaml"
]]; then

echo "Missing application contract"
echo "QUALITY GATE: FAIL"

exit 1

fi

if [[ ! -f
"${ROOT_DIR}/tests/contract/result-contract.json"
]]; then

echo "Missing result contract"
echo "QUALITY GATE: FAIL"

exit 1

fi

echo "Contract: PASS"

echo
echo "[3/3] Required quality definitions"

required_files=(
"${ROOT_DIR}/quality/sli/slis.yaml"
"${ROOT_DIR}/quality/slo/slos.yaml"
"${ROOT_DIR}/quality/sli/calculate.py"
"${ROOT_DIR}/quality/slo/evaluate.py"
)

for file in "${required_files[@]}"; do

if [[ ! -f "${file}" ]]; then
    echo "Missing: ${file}"
    echo "QUALITY GATE: FAIL"
    exit 1
fi

done

echo "Quality definitions: PASS"

echo
echo "=================================================="
echo "QUALITY GATE: PASS"
echo "=================================================="
SH

chmod +x quality/ci/quality-gate.sh

success "Global Quality Gate created."
============================================================
10. Quality report
============================================================

log "Creating quality report generator..."

cat > quality/reports/generate.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REPORT_DIR="${ROOT_DIR}/reports"

mkdir -p "${REPORT_DIR}"

STRUCTURE_STATUS="PASS"
METADATA_STATUS="PASS"
CONTRACT_STATUS="PASS"

if ! "${ROOT_DIR}/quality/ci/validate-tests.sh"
> "${REPORT_DIR}/quality-validation.log"
2>&1
then
STRUCTURE_STATUS="FAIL"
METADATA_STATUS="FAIL"
fi

if [[ ! -f
"${ROOT_DIR}/tests/contract/result-contract.json"
]]; then
CONTRACT_STATUS="FAIL"
fi

cat > "${REPORT_DIR}/quality-summary.json" <<EOF
{
"project": "integration-xtesting",
"quality": {
"structure": "${STRUCTURE_STATUS}",
"metadata": "${METADATA_STATUS}",
"contract": "${CONTRACT_STATUS}"
}
}
EOF

cat > "${REPORT_DIR}/quality-summary.md" <<EOF
Integration Xtesting Quality Summary
Quality Gate	Status
Structure	${STRUCTURE_STATUS}
Metadata	${METADATA_STATUS}
Contract	${CONTRACT_STATUS}
EOF	

echo "Reports generated:"
echo " ${REPORT_DIR}/quality-summary.json"
echo " ${REPORT_DIR}/quality-summary.md"
SH

chmod +x quality/reports/generate.sh

success "Quality report generator created."
============================================================
11. Quality documentation
============================================================

log "Creating quality documentation..."

cat > quality/README.md <<'EOF'
Integration Xtesting Quality

The quality/ directory validates the Test Factory itself.

It must remain conceptually separate from functional validation
of the Kubernetes system under test.
Layers

Structure
    |
Metadata
    |
Unit / Test validation
    |
Build
    |
Security
    |
Execution
    |
Reporting
    |
Release

SLI

SLI means Service Level Indicator.

It is an observed measurement.

Examples:

CI success rate;

structure compliance;

execution success rate;

topology coverage;

report generation.

SLO

SLO means Service Level Objective.

It defines the target for an SLI.

Example:

SLI: structure compliance
SLO: 100%


EOF

cat > docs/sli-slo.md <<'EOF'

SLI / SLO
Principle

SLI measures what happens.

SLO defines the expected level.

The SLI/SLO layer measures the quality of the
integration-xtesting Test Factory.

It does not replace RA2/RC2 functional results.

Initial SLOs
ID	SLO	Target
SLO-01	CI reliability	>= 95%
SLO-02	Structure compliance	>= 100%
SLO-03	Metadata compliance	>= 100%
SLO-04	Execution success	>= 95%
SLO-05	Topology coverage	>= 95%
SLO-06	Evidence completeness	>= 100%
SLO-07	Report generation	>= 100%
SLO-08	Release success	>= 99%
EOF		

success "Quality documentation created."

============================================================
12. Local quality command
============================================================

log "Creating local quality command..."

cat > ci/quality.sh <<'SH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT_DIR}/quality/ci/quality-gate.sh"
SH

chmod +x ci/quality.sh

success "Local quality command created."

============================================================
13. Run Quality Gate now
============================================================

echo
log "Running initial Quality Gate..."

if "${ROOT_DIR}/quality/ci/quality-gate.sh"; then
success "Initial Quality Gate: PASS"
else
die "Initial Quality Gate: FAIL"
fi

============================================================
14. Generate report
============================================================

log "Generating initial quality report..."

"${ROOT_DIR}/quality/reports/generate.sh"

success "Initial quality report generated."

============================================================
15. Summary
============================================================

echo
echo "============================================================"
success " PART 2/5 COMPLETED"
echo "============================================================"

echo
echo "Installed:"
echo " quality/structure/validate.py"
echo " quality/structure/discover.py"
echo " quality/metadata/validate.py"
echo " quality/ci/validate-tests.sh"
echo " quality/ci/quality-gate.sh"
echo " quality/sli/slis.yaml"
echo " quality/sli/calculate.py"
echo " quality/slo/slos.yaml"
echo " quality/slo/evaluate.py"
echo " quality/reports/generate.sh"
echo " ci/quality.sh"

echo
echo "Run manually:"
echo " ./ci/quality.sh"

echo
echo "Reports:"
echo " reports/quality-summary.md"
echo " reports/quality-summary.json"

echo
echo "Next:"
echo " ./03-cicd.sh"


## Ce que tu obtiens après cette partie

Le flux local devient déjà :

```text
                 Test Application
                        │
                        ▼
              Structure Validator
                        │
                        ▼
               Metadata Validator
                        │
                        ▼
                 Quality Gate
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
            PASS                 FAIL
              │
              ▼
         Quality Report
              │
              ▼
           SLI / SLO

