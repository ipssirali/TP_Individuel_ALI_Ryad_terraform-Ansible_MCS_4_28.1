#!/usr/bin/env bash
# Détruit l'infrastructure. -refresh=false évite la relecture de l'Object Lock
# du bucket, interdit (voir apply.sh) : sans lui, la
# destruction échouerait avant de commencer.
set -euo pipefail
cd "$(dirname "$0")"

terraform destroy -refresh=false -var-file=terraform.tfvars "$@"
