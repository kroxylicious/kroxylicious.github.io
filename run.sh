#!/bin/bash
# Runs the Kroxylicious website locally, for development purposes, within a container.
# Point your browser at http://localhost:4000
#
# Jekyll is run on incremental mode so changes made to the host filesystem should be soon visible in your browser. Note however incremental mode won't work on Mac OS X (owing to http://github.com/containers/podman/issues/22343). Use the force_regenerate.sh to trigger the incremental reload after the edit is made on the host.
OS=$(uname)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd ${SCRIPT_DIR}
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}

RUN_ARGS=()
if [ "$OS" = 'Darwin' ]; then
   RUN_ARGS+=(--env JEKYLL_SERVE_BIND=0.0.0.0 --publish 4000:4000)
else
   RUN_ARGS+=(--net host)
fi

if [ "$CONTAINER_ENGINE" = 'podman' ]; then
   RUN_ARGS+=(-v $(pwd):/site/:Z)
fi

RUN_ARGS+=(--rm --name jekll_serve -it kroxylicious-website)

${CONTAINER_ENGINE} build . -t kroxylicious-website 

${CONTAINER_ENGINE} run "${RUN_ARGS[@]}"
