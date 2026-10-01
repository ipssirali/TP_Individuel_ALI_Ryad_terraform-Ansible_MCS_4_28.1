# ---------------------------------------------------------------------------
# Security Groups en cascade : chaque couche n'accepte que la couche
# immédiatement en amont, référencée par son Security Group et non par une
# plage d'adresses. Internet -> ALB -> instances -> RDS, et
# poste admin -> bastion -> instances pour l'administration.
# ---------------------------------------------------------------------------

# SG de l'ALB : seule ressource ouverte à tout Internet, et uniquement en HTTP.
# La sortie est limitée aux subnets applicatifs : l'ALB ne parle qu'à ses cibles.
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "ALB : HTTP depuis Internet, sortie vers les subnets applicatifs"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP depuis Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP vers les instances applicatives"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.app_subnet_cidrs
  }

  tags = { Name = "${var.project}-alb-sg" }
}

# SG du bastion : le SSH n'est ouvert qu'à l'IP de l'administrateur (/32), ce
# qui supprime l'exposition du port 22 au reste d'Internet. En sortie il ne
# peut joindre en SSH que les subnets applicatifs, pas Internet.
resource "aws_security_group" "bastion" {
  name        = "${var.project}-bastion-sg"
  description = "Bastion : SSH depuis l IP admin uniquement"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH depuis l IP publique de l administrateur"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "SSH vers les instances applicatives"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.app_subnet_cidrs
  }

  tags = { Name = "${var.project}-bastion-sg" }
}

# SG applicatif : le port 80 n'est joignable QUE depuis le SG de l'ALB, de
# sorte qu'aucune requête ne peut atteindre directement une instance même si
# son adresse était connue (moindre exposition). Le SSH n'est accepté que
# depuis le SG du bastion. Les sorties sont restreintes aux besoins réels :
# paquets et S3 (80/443, via NAT et endpoint) et la base (5432, subnets
# données seulement).
resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "Instances applicatives : HTTP depuis l ALB, SSH depuis le bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP depuis le SG de l ALB uniquement"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH depuis le SG du bastion uniquement"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "HTTP pour apt"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS pour apt et S3"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "PostgreSQL vers les subnets donnees"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.data_subnet_cidrs
  }

  tags = { Name = "${var.project}-app-sg" }
}

# SG de RDS : le port 5432 n'accepte que le SG applicatif. Aucune règle de
# sortie : une base managée n'initie aucune connexion, donc la supprimer
# retire toute possibilité d'exfiltration depuis la couche données.
resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "RDS : PostgreSQL depuis le SG applicatif uniquement"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL depuis le SG applicatif uniquement"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "${var.project}-rds-sg" }
}
