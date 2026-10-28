resource "aws_key_pair" "minecraft" {
  key_name   = "minecraft-server"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "random_password" "rcon" {
  length  = 32
  special = false
}

locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    paper_version  = var.paper_version
    paper_build    = var.paper_build
    rcon_password  = random_password.rcon.result
    s3_bucket      = aws_s3_bucket.backups.bucket
    idle_minutes   = var.idle_minutes
    aws_region     = var.aws_region
  })
}

resource "aws_instance" "minecraft" {
  count = var.server_enabled ? 1 : 0

  ami                         = data.aws_ami.al2023_arm.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.minecraft.key_name
  subnet_id                   = data.aws_subnet.primary.id
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  iam_instance_profile        = aws_iam_instance_profile.minecraft.name
  associate_public_ip_address = true

  instance_initiated_shutdown_behavior = "stop"

  user_data                = local.user_data
  user_data_replace_on_change = false

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  tags = {
    Name = "minecraft-server"
  }

  lifecycle {
    # A stopped instance reports no public IP, which would otherwise force replacement.
    ignore_changes = [ami, associate_public_ip_address]
  }
}

resource "aws_volume_attachment" "world" {
  count = var.server_enabled ? 1 : 0

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.world[0].id
  instance_id = aws_instance.minecraft[0].id
}

moved {
  from = aws_instance.minecraft
  to   = aws_instance.minecraft[0]
}

moved {
  from = aws_volume_attachment.world
  to   = aws_volume_attachment.world[0]
}
