# ---------------------------------------------------------------------------
# Couche données : instance RDS PostgreSQL privée.
# ---------------------------------------------------------------------------

# RDS exige un groupe de sous-réseaux couvrant au moins deux zones, même pour
# une instance mono-zone : il lui permet d'être relocalisée en cas de panne.
# On n'y met que les subnets données, qui n'ont aucune route vers l'extérieur.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnets"
  subnet_ids = aws_subnet.data[*].id

  tags = { Name = "${var.project}-db-subnets" }
}

# Base applicative. publicly_accessible = false : aucune IP publique, et le
# SG ne laisse entrer que les instances applicatives. Le mot de passe vient
# exclusivement de la variable sensible (jamais écrit dans un .tf). Pas de
# snapshot final ni de rétention : environnement de préproduction jetable ;
# à inverser en production.
resource "aws_db_instance" "main" {
  identifier        = "${var.project}-db"
  engine            = "postgres"
  engine_version    = var.db_engine_version
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Zone fixée à la première zone : sans cela AWS choisit parmi les deux du
  # groupe de sous-réseaux, et l'instance pourrait ne pas être là où le schéma
  # d'architecture la place. L'infrastructure décrite et déployée coïncident.
  availability_zone = data.aws_availability_zones.available.names[0]

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  skip_final_snapshot = true

  tags = { Name = "${var.project}-db" }
}
