data "aws_iam_policy_document" "minecraft_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "minecraft" {
  name               = "minecraft-server"
  assume_role_policy = data.aws_iam_policy_document.minecraft_assume_role.json
}

data "aws_iam_policy_document" "minecraft_s3" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "minecraft_s3" {
  name   = "minecraft-s3-backup"
  role   = aws_iam_role.minecraft.id
  policy = data.aws_iam_policy_document.minecraft_s3.json
}

resource "aws_iam_instance_profile" "minecraft" {
  name = "minecraft-server"
  role = aws_iam_role.minecraft.name
}
