#!/usr/bin/env bash
# Applique la configuration en contournant une limite du Learner Lab.
#
# Le provider AWS lit la configuration Object Lock d'un bucket juste après sa
# création ; le lab l'interdit par une politique organisationnelle (SCP), donc
# la ressource S3 est marquée en échec alors que le bucket existe bel et bien.
# En cas d'échec, on retire cette marque puis on réapplique sans relire l'état
# distant (-refresh=false), ce qui crée le reste des ressources S3.
set -uo pipefail
cd "$(dirname "$0")"

if ! terraform apply -var-file=terraform.tfvars "$@"; then
  echo ">> Echec du premier passage : tentative de contournement S3 (Object Lock)"
  terraform untaint aws_s3_bucket.backups || true
  terraform apply -refresh=false -var-file=terraform.tfvars "$@"
fi
