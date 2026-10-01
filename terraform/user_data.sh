#!/bin/bash
# Amorçage minimal exécuté par cloud-init au premier démarrage.
# Objectif : que l'instance réponde 200 sur /health dès que possible, pour
# passer "healthy" dans le Target Group avant le passage d'Ansible.
# La configuration applicative réelle (vhost, PHP, accès base) est faite par
# Ansible, qui remplace ce site par défaut.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx

# Site par défaut volontairement trivial : /health pour l'ALB, et une page
# qui indique que l'instance n'est pas encore configurée.
cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    server_name _;

    location /health {
        default_type text/plain;
        return 200 "ok\n";
    }

    location / {
        default_type text/plain;
        return 200 "instance amorcee, configuration Ansible en attente\n";
    }
}
NGINX

systemctl enable nginx
systemctl restart nginx
