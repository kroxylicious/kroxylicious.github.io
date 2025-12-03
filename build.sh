#!/bin/bash

# This script exists to run a production build of the code. Users can:
# * Supply a builder image with BUILD_IMAGE_SPEC, otherwise we build the image
# * Include additional configuration overrides with ${CONFIG_OVERRIDES}, additional
#   override files should be added to the project directory. Eg I add an _config-overrides.yml
#   and set CONFIG_OVERRIDES=_config-overrides.yml
# * Control their container engine binary by setting CONTAINER_ENGINE, for example to 'docker'.
# The output of the build will be emitted to a '_site' directory in the project directory
trap "exit" INT
set +euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd ${SCRIPT_DIR}
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
if [ -z "${BUILD_IMAGE_SPEC}" ]; then
  ${CONTAINER_ENGINE} build . -t kroxylicious-website
  export BUILD_IMAGE_SPEC=kroxylicious-website
fi
if [ -n "${CONFIG_OVERRIDES}" ]; then
  export CONFIG_OVERRIDES=",${CONFIG_OVERRIDES}"
else
  export CONFIG_OVERRIDES=""
fi
RUN_ARGS=()
if [ "$CONTAINER_ENGINE" = 'podman' ]; then
  RUN_ARGS+=(-v "$(pwd):/site/:Z")
else
  RUN_ARGS+=(-v "$(pwd):/site")
  RUN_ARGS+=(-u $(id -u):$(id -g))
fi
RUN_ARGS+=(-e JEKYLL_ENV="${JEKYLL_ENV:-production}" --rm "${BUILD_IMAGE_SPEC}")
BUILD_COMMAND='eval "$(rbenv init -)" && cp -r /css/_sass/bootstrap /site/_sass/ && bundle exec jekyll build --config=_config.yml'"${CONFIG_OVERRIDES}"
RUN_ARGS+=(bash -c "${BUILD_COMMAND}")
echo "${RUN_ARGS[@]}"
${CONTAINER_ENGINE} run "${RUN_ARGS[@]}"
./test.sh
