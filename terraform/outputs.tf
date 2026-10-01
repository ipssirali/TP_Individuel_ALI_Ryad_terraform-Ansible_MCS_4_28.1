# Sorties consommées par l'utilisateur (test de l'ALB) et par le script de
# lancement d'Ansible (endpoint RDS, nom de base). Aucune ne contient de secret.

output "alb_dns_name" {
  description = "Nom DNS public de l'ALB, à utiliser pour tester le service"
  value       = aws_lb.app.dns_name
}

output "rds_endpoint" {
  description = "Endpoint RDS complet (hôte:port)"
  value       = aws_db_instance.main.endpoint
}

# Ansible a besoin de l'hôte seul, sans le port : le port est une variable à part.
output "rds_address" {
  description = "Nom d'hôte de RDS sans le port"
  value       = aws_db_instance.main.address
}

output "db_name" {
  description = "Nom de la base applicative"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Compte administrateur de la base (le mot de passe n'est jamais exposé)"
  value       = aws_db_instance.main.username
}

output "bastion_public_ip" {
  description = "IP publique du bastion"
  value       = aws_instance.bastion.public_ip
}

output "backup_bucket" {
  description = "Nom du bucket S3 de sauvegardes"
  value       = aws_s3_bucket.backups.id
}
