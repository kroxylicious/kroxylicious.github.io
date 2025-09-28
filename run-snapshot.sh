#!/bin/bash
# This script builds the documentation in a local checkout of the kroxylicious/kroxylicious repository, then incorporates
# the built documentation into a local deployment of the website and serves it on localhost:4000 using ./run.sh.
#
# It is assumed this repository is checked out beside a cloned https://github.com/kroxylicious/kroxylicious/ like:
# .
# ├── kroxylicious
# └── kroxylicious.github.io
# 
# if you organize your directories differently, you can set the KROXYLICIOUS_DIR env variable like
# KROXYLICIOUS_DIR=/path/to/my/kroxylicious ./run-snapshot.sh to point it at your kroxylicious dir.

trap "exit" INT
set +euo pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
KROXYLICIOUS_DIR="${KROXYLICIOUS_DIR:-${SCRIPT_DIR}/../kroxylicious}"
TEST_FILE="${KROXYLICIOUS_DIR}/pom.xml"
if [ ! -f "${TEST_FILE}" ]; then
  echo "${TEST_FILE} not found, set KROXYLICIOUS_DIR env var to point to a checkout of https://github.com/kroxylicious/kroxylicious"
  exit 1
fi

cd ${KROXYLICIOUS_DIR}
mvn -P dist clean package -pl :kroxylicious-docs
cp -r kroxylicious-docs/target/web/* ${SCRIPT_DIR}
cd ${SCRIPT_DIR}
exec ./run.sh
