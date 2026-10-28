# No prevent_destroy: `./mc hibernate` destroys this volume after snapshotting it.
resource "aws_ebs_volume" "world" {
  count = var.server_enabled ? 1 : 0

  availability_zone = data.aws_subnet.primary.availability_zone
  size              = var.world_volume_size_gb
  type              = "gp3"
  snapshot_id       = var.world_snapshot_id

  tags = {
    Name = "minecraft-world"
  }

  lifecycle {
    # snapshot_id only matters at creation; changing it must not replace a live volume.
    ignore_changes = [snapshot_id]
  }
}

moved {
  from = aws_ebs_volume.world
  to   = aws_ebs_volume.world[0]
}

resource "aws_s3_bucket" "backups" {
  bucket        = "minecraft-backups-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.allow_destroy

  tags = {
    Name = "minecraft-backups"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "world-backups"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 180
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
