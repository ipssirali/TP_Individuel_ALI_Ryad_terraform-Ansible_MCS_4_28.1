# ---------------------------------------------------------------------------
# Couche applicative : bastion d'administration, puis ALB, Target Group,
# Launch Template et Auto Scaling Group.
# ---------------------------------------------------------------------------

# AMI résolue dynamiquement chez Canonical : les identifiants d'AMI changent
# selon la région et les mises à jour, un ID codé en dur casserait vite.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Bastion : unique porte d'entrée d'administration. Il est en subnet public
# avec une IP publique, mais son SG ne laisse passer que l'IP de l'admin. Le
# tag Role permet à l'inventaire Ansible de le retrouver pour le rebond SSH.
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  # IMDSv2 obligatoire : empêche qu'une faille SSRF lise les métadonnées.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "${var.project}-bastion", Role = "bastion" }
}

# --- Répartition de charge -----------------------------------------------------

# Cible de l'ALB. Le health check interroge /health plutôt que la page
# d'accueil : ce chemin ne dépend ni de PHP ni de la base, donc une panne de
# RDS ne fait pas retirer toutes les instances du service. Intervalle de 15 s
# et 2 succès pour déclarer une instance saine en 30 s ; 3 échecs (45 s) avant
# de la retirer, pour ne pas réagir à un incident très bref.
resource "aws_lb_target_group" "app" {
  name     = "${var.project}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Une désinscription rapide accélère les remplacements d'instance et le destroy.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project}-tg" }
}

# ALB public réparti sur les deux subnets publics : point d'entrée unique du
# trafic web, il survit à la perte d'une zone. Le depends_on garantit que la
# passerelle Internet existe avant qu'il tente de s'exposer.
resource "aws_lb" "app" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${var.project}-alb" }

  depends_on = [aws_internet_gateway.main]
}

# Le listener fait le lien entre le port exposé par l'ALB et le Target Group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --- Instances applicatives ------------------------------------------------------

# Modèle d'instance de l'ASG. Le user_data ne fait que le strict minimum
# (nginx + /health) pour que l'instance passe saine tout de suite et ne soit
# pas remplacée en boucle ; la vraie configuration est appliquée par Ansible.
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-app-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.app.id]

  # Profil déjà présent dans le compte : donne accès à S3 sans créer de ressource IAM.
  iam_instance_profile {
    name = var.instance_profile_name
  }

  # Chargé depuis un fichier pour garder le script lisible et testable à part ;
  # base64encode car le Launch Template attend le user_data déjà encodé.
  user_data = base64encode(file("${path.module}/user_data.sh"))

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}

# ASG réparti sur les subnets applicatifs (donc sur deux zones). Il est
# rattaché au Target Group et son health check est de type ELB : une instance
# jugée défaillante par l'ALB est remplacée, pas seulement une instance arrêtée.
resource "aws_autoscaling_group" "app" {
  name                      = "${var.project}-asg"
  min_size                  = var.asg_min_size
  desired_capacity          = var.asg_desired_capacity
  max_size                  = var.asg_max_size
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Ces tags sont propagés aux instances : c'est sur eux (Project et Role)
  # que l'inventaire dynamique Ansible filtre pour trouver les machines.
  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }

  # Sans route vers la NAT au premier démarrage, apt échouerait dans le
  # user_data : l'ASG attend donc que les subnets applicatifs soient routés.
  depends_on = [aws_route_table_association.app]
}
