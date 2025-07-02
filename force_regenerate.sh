#!/bin/bash
# Work around for the inability to utilise to Jekyll's incremental development
# when running the website with the ./run.sh script on a Mac.
# Edit the file as normal on the host then retrigger a rebuild:
# force_regenerate.sh [<file glob>]
# <file glob> defaults to *.markdown

NAME=${1:-*.markdown}
podman exec jekll_serve find  -type f  -name "${NAME}" -exec touch {} \;
