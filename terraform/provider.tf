# Versions bornées : le code doit rester reproductible et auditable. Le fichier
# .terraform.lock.hcl fige la version exacte installée. Le provider AWS reste
# en 5.x parce que c'est avec lui que tout le projet a été validé ; la 6.x n'a
# pas été testée sur ce code.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # random sert uniquement à rendre unique le nom du bucket S3 (les noms
    # de bucket sont globaux à tout AWS).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Région unique : tout le projet vit dans une seule région, ce qui garde les
# coûts, l'inventaire et le nettoyage simples (aucune ressource oubliée ailleurs).
# default_tags pose Project et ManagedBy sur les ressources créées directement
# (VPC, bastion, ALB, RDS...) : un auditeur sait d'où vient chaque ressource, et
# l'inventaire Ansible peut filtrer sur Project. Les instances de l'ASG ne
# reçoivent pas ces tags par ce biais : ils sont posés explicitement dans
# compute.tf (propagate_at_launch).
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
