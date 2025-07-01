#!/bin/bash
OS=$(uname)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd ${SCRIPT_DIR}
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}

RUN_ARGS=()
if [ "$OS" = 'Darwin' ]; then
   RUN_ARGS+=(--env JEKYLL_SERVE_BIND=0.0.0.0 --publish 4000:4000)
elif [ "$CONTAINER_ENGINE" = 'podman' ]; then
   RUN_ARGS+=(--net host -v $(pwd):/site/:Z)
else
   RUN_ARGS+=(--net host)
fi
RUN_ARGS+=(--rm -it kroxylicious-website)

${CONTAINER_ENGINE} build . -t kroxylicious-website 

${CONTAINER_ENGINE} run "${RUN_ARGS[@]}"
