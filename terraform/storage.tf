# ---------------------------------------------------------------------------
# Stockage S3 : sauvegardes et documents (contrats signés), chiffrés,
# versionnés et jamais publics.
# ---------------------------------------------------------------------------

# Les noms de bucket sont uniques sur tout AWS : le suffixe aléatoire évite
# toute collision, et reste stable car conservé dans le state.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# force_destroy permet au destroy de vider le bucket (objets et versions) :
# nécessaire pour supprimer le bucket sans le vider à la main, à ne pas
# reproduire en production.
resource "aws_s3_bucket" "backups" {
  bucket        = "${var.project}-backups-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = { Name = "${var.project}-backups" }
}

# Versioning : protège contre l'écrasement ou la suppression accidentels d'un
# contrat ou d'une sauvegarde, puisque les versions précédentes restent restaurables.
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement par défaut (SSE-S3, AES256) : tout objet est chiffré au repos
# même si l'application oublie de le demander.
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Blocage d'accès public au niveau du bucket : neutralise toute ACL ou policy
# publique, y compris celle qu'une erreur de configuration future pourrait ajouter.
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Rétention : sans règle, le versioning conserve indéfiniment les anciennes
# versions et le coût dérive. Elles sont supprimées après 90 jours, et les
# téléversements incomplets après 7 jours.
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "retention-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

data "aws_caller_identity" "current" {}

# Politique restrictive : deux refus explicites. Le premier impose TLS, donc
# aucun transfert en clair ; le second refuse tout principal extérieur au
# compte. Ainsi le bucket reste privé même si le blocage d'accès public était
# un jour retiré. La policy dépend du blocage pour être appliquée dans l'ordre.
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyAccessOutsideAccount"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
        Condition = {
          StringNotEquals = { "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.backups]
}
