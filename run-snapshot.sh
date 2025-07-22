#!/bin/bash
set +euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
KROXYLICIOUS_DIR="${KROXYLICIOUS_DIR:-${SCRIPT_DIR}/../kroxylicious}"
cd ${KROXYLICIOUS_DIR}
mvn -Dquick -P dist clean package --non-recursive
cp -r target/web/* ${SCRIPT_DIR}
cd ${SCRIPT_DIR}
exec ./run.sh
