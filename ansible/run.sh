#!/usr/bin/env bash
# Script de lancement : récupère l'endpoint RDS, le nom de base et le compte
# directement depuis les sorties Terraform et les passe à Ansible en
# extra-vars. Rien n'est recopié à la main, rien n'est écrit sur disque.
set -euo pipefail
cd "$(dirname "$0")"

TF_DIR="../terraform"
RDS_HOST="$(terraform -chdir="$TF_DIR" output -raw rds_address)"
DB_NAME="$(terraform -chdir="$TF_DIR" output -raw db_name)"
DB_USER="$(terraform -chdir="$TF_DIR" output -raw db_username)"

ansible-playbook site.yml \
  -e "rds_host=${RDS_HOST}" \
  -e "db_name=${DB_NAME}" \
  -e "db_user=${DB_USER}" \
  "$@"
