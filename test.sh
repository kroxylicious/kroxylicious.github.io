#!/bin/bash
# Checks the output of build.sh (which is the production build deployed to pages)
set -euo pipefail

LATEST_RELEASE=$(grep "latestRelease:" _data/kroxylicious.yml | awk '{print $2}')

LATEST_RELEASE_QUICKSTART="_site/documentation/${LATEST_RELEASE}/html/proxy-quick-start/index.html"
PERMANENT_QUICKSTART_REDIRECT="_site/get-started.html"
EXPECTED_REDIRECT_STRING="<meta http-equiv=\"refresh\" content=\"1; url=https://kroxylicious.io/documentation/${LATEST_RELEASE}/html/proxy-quick-start/\">"

check_file_exists() {
  local file_path="$1"
  local file_description="$2"
  if [ -f "${file_path}" ]; then
    echo "SUCCESS: ${file_description} file found at ${file_path}"
  else
    echo "ERROR: ${file_description} file not found at ${file_path}" >&2
    exit 1
  fi
}

echo "Expect /get-started to HTML redirect to the latest quickstart"
check_file_exists "${LATEST_RELEASE_QUICKSTART}" "Latest release quickstart"
check_file_exists "${PERMANENT_QUICKSTART_REDIRECT}" "Permanent quickstart redirect"

if grep -qF "${EXPECTED_REDIRECT_STRING}" "${PERMANENT_QUICKSTART_REDIRECT}"; then
  echo "SUCCESS: Expected redirect string found in ${PERMANENT_QUICKSTART_REDIRECT}"
else
  echo "ERROR: Expected redirect string '${EXPECTED_REDIRECT_STRING}' not found in ${PERMANENT_QUICKSTART_REDIRECT}"
  exit 1
fi
echo "All checks succeeded!"
exit 0
