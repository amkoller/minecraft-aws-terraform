output "instance_id" {
  description = "EC2 instance ID (null while hibernated)"
  value       = one(aws_instance.minecraft[*].id)
}

output "world_volume_id" {
  description = "World EBS volume ID (null while hibernated)"
  value       = one(aws_ebs_volume.world[*].id)
}

output "s3_backup_bucket" {
  description = "S3 backup bucket name"
  value       = aws_s3_bucket.backups.bucket
}

output "rcon_password" {
  description = "RCON password (sensitive)"
  value       = random_password.rcon.result
  sensitive   = true
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "ssh_user" {
  description = "SSH username for the instance"
  value       = "ec2-user"
}
