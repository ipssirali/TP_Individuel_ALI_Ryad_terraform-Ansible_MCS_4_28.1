# Toutes les valeurs d'adressage sont des variables : on peut changer de plan
# d'adressage sans toucher au code des ressources (et le justifier dans le
# rapport sans relire main.tf).

variable "region" {
  description = "Région AWS unique du projet"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nom du projet : préfixe des ressources et valeur du tag Project (filtre d'inventaire Ansible)"
  type        = string
  default     = "atlasbook"
}

variable "vpc_cidr" {
  description = "Bloc du VPC : un /16 laisse la place de découper des /24 par couche et par zone"
  type        = string
  default     = "10.10.0.0/16"
}

# Un CIDR par zone de disponibilité dans chaque liste : l'index 0 va en
# zone a, l'index 1 en zone b. Plages séparées par couche (1-2 / 11-12 /
# 21-22) pour lire la couche d'une adresse au premier coup d'oeil.
variable "public_subnet_cidrs" {
  description = "Subnets publics (ALB, NAT, bastion), un par zone"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "app_subnet_cidrs" {
  description = "Subnets privés applicatifs (instances de l'ASG), un par zone"
  type        = list(string)
  default     = ["10.10.11.0/24", "10.10.12.0/24"]
}

variable "data_subnet_cidrs" {
  description = "Subnets privés données (RDS), un par zone"
  type        = list(string)
  default     = ["10.10.21.0/24", "10.10.22.0/24"]
}

# --- Accès et calcul ---------------------------------------------------------

variable "admin_cidr" {
  description = "IP publique de l'administrateur en /32 : seule source autorisée sur le SSH du bastion (valeur dans terraform.tfvars)"
  type        = string
}

variable "key_name" {
  description = "Paire de clés SSH déjà importée dans AWS, utilisée par le bastion et les instances de l'ASG"
  type        = string
  default     = "tp-ryad-galaktus-key"
}

variable "instance_type" {
  description = "Taille des instances : t3.micro suffit à la charge de préproduction et tient dans le quota vCPU du compte"
  type        = string
  default     = "t3.micro"
}

variable "instance_profile_name" {
  description = "Instance profile déjà présent dans le compte (aucune ressource IAM n'est créée ici) : donne aux instances l'accès à S3"
  type        = string
  default     = "LabInstanceProfile"
}

# --- Auto Scaling Group --------------------------------------------------------

# Minimum 2 = une instance par zone : la panne d'une zone ne coupe pas le
# service. Maximum 3 = marge de montée en charge sans dépasser le quota vCPU
# du compte.
variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 3
}

# --- Base de données -----------------------------------------------------------

variable "db_engine_version" {
  description = "Version de PostgreSQL, vérifiée disponible en db.t3.micro dans la région"
  type        = string
  default     = "16.15"
}

variable "db_name" {
  description = "Nom de la base applicative créée au démarrage de l'instance"
  type        = string
  default     = "atlasbook"
}

variable "db_username" {
  description = "Compte administrateur de la base"
  type        = string
  default     = "atlas_admin"
}

# Pas de valeur par défaut volontairement : le mot de passe ne doit exister
# dans aucun fichier .tf. sensitive = true masque la valeur dans le plan, les
# sorties et les journaux Terraform.
variable "db_password" {
  description = "Mot de passe administrateur RDS, fourni par terraform.tfvars (non versionné)"
  type        = string
  sensitive   = true
}
