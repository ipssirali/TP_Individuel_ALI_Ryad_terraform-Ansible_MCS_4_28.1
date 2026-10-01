#!/usr/bin/env bash
# Crée group_vars/role_app/vault.yml chiffré avec Ansible Vault, à partir du
# mot de passe RDS déjà présent dans terraform.tfvars : une seule source de
# vérité pour le secret, jamais retapé ni affiché.
# Le mot de passe du coffre est généré une fois et stocké HORS du dépôt.
set -euo pipefail
cd "$(dirname "$0")"

VAULT_PASS="$HOME/.ansible/atlasbook_vault_pass"
TFVARS="../terraform/terraform.tfvars"
OUT="group_vars/role_app/vault.yml"

umask 077
mkdir -p "$HOME/.ansible"
[ -f "$VAULT_PASS" ] || openssl rand -base64 24 > "$VAULT_PASS"

DB_PASSWORD="$(sed -n 's/^db_password *= *"\(.*\)"/\1/p' "$TFVARS")"
[ -n "$DB_PASSWORD" ] || { echo "db_password introuvable dans $TFVARS" >&2; exit 1; }

TMP="$(mktemp)"
trap 'shred -u "$TMP" 2>/dev/null || rm -f "$TMP"' EXIT
printf 'vault_db_password: "%s"\n' "$DB_PASSWORD" > "$TMP"

# Le fichier de mot de passe est déjà déclaré dans ansible.cfg : le repasser en
# ligne de commande créerait deux identités de coffre identiques.
ansible-vault encrypt --output "$OUT" "$TMP" >/dev/null
echo "Coffre chiffré écrit dans $OUT"
