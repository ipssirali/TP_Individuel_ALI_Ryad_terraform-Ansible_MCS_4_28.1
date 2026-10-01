# ---------------------------------------------------------------------------
# Couche réseau : VPC, trois familles de subnets sur deux zones, passerelles
# et routage. Tout le cloisonnement du projet repose sur ce découpage.
# ---------------------------------------------------------------------------

# Zones récupérées dynamiquement : le code ne suppose pas que "us-east-1a"
# existe ou soit disponible sur le compte, et reste valable dans une autre
# région sans modification.
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC dédié au projet : isole totalement l'infrastructure des autres
# déploiements qui partagent le même compte. Les noms DNS sont activés car RDS
# s'adresse par son nom d'endpoint, qui doit se résoudre depuis les instances.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

# Seule porte vers Internet du VPC. Elle n'a d'effet que pour les subnets
# dont la table de routage la référence (les subnets publics uniquement).
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project}-igw" }
}

# --- Subnets -----------------------------------------------------------------

# Subnets publics : hébergent l'ALB (qui doit être joignable d'Internet), la
# NAT et le bastion. L'IP publique automatique est inutile ici : l'ALB n'en
# a pas besoin (il a un nom DNS), et le bastion reçoit son IP explicitement.
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-public-${count.index + 1}", Tier = "public" }
}

# Subnets applicatifs : les instances de l'ASG y vivent sans IP publique,
# donc injoignables d'Internet même si un Security Group était mal configuré.
resource "aws_subnet" "app" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.app_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-app-${count.index + 1}", Tier = "app" }
}

# Subnets données : réservés à RDS. Deux zones sont exigées par le groupe de
# sous-réseaux RDS, même si l'instance n'est pas Multi-AZ.
resource "aws_subnet" "data" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.data_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-data-${count.index + 1}", Tier = "data" }
}

# --- Sortie des instances privées -------------------------------------------

# Adresse fixe de sortie de la NAT. domain = "vpc" car l'EIP sert dans un VPC.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.project}-nat-eip" }

  # L'IGW doit exister avant l'EIP, sinon AWS peut refuser l'association.
  depends_on = [aws_internet_gateway.main]
}

# Les instances applicatives n'ont pas d'IP publique mais doivent installer
# leurs paquets : elles sortent par cette NAT. Une seule NAT (en zone a) :
# choix de coût assumé, au prix d'un point de défaillance unique pour la
# SORTIE uniquement (l'entrée, via l'ALB, reste multi-AZ).
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = "${var.project}-nat" }

  depends_on = [aws_internet_gateway.main]
}

# --- Routage -----------------------------------------------------------------

# Table publique : c'est la route par défaut vers l'IGW qui rend un subnet
# "public". Elle n'est associée qu'aux subnets publics (voir ci-dessous).
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Table privée applicative : sortie Internet via la NAT uniquement (pas
# d'entrée possible, une NAT ne route que les connexions initiées de l'intérieur).
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project}-rt-app" }
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# Les subnets données n'ont volontairement AUCUNE association : ils restent
# sur la table principale du VPC, qui ne contient que la route locale. La base
# n'a donc aucun chemin vers Internet, ni dans un sens ni dans l'autre.

# Endpoint S3 de type gateway : ajoute à la table applicative une route vers le
# préfixe S3 de la région. Le trafic instances vers S3 reste dans le réseau AWS
# (donc ne passe ni par la NAT ni par Internet) et n'est pas facturé au volume
# NAT. Il n'est rattaché qu'à la table applicative : seule la couche
# applicative a besoin de S3, les données restent totalement fermées.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id]

  tags = { Name = "${var.project}-s3-endpoint" }
}
