#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

"${SCRIPT_DIRECTORY}/build-images.sh"
"${SCRIPT_DIRECTORY}/load-images.sh"

echo
echo "Application images were built and loaded into Minikube."