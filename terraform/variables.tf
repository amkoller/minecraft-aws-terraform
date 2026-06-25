variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "paper_version" {
  description = "PaperMC Minecraft version (e.g. 1.21.1)"
  type        = string
  default     = "1.21.1"
}

variable "paper_build" {
  description = "PaperMC build number or 'latest'"
  type        = string
  default     = "latest"
}

variable "instance_type" {
  description = "EC2 instance type (ARM)"
  type        = string
  default     = "t4g.small"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to the instance (lock to your IP/32)"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/minecraft.pub"
}

variable "world_volume_size_gb" {
  description = "Size of the world EBS volume in GB"
  type        = number
  default     = 20
}

variable "idle_minutes" {
  description = "Minutes of zero players before auto-stop"
  type        = number
  default     = 15
}

variable "root_volume_size_gb" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 8
}

variable "allow_destroy" {
  description = "Set to true to allow terraform destroy to empty + delete the S3 backup bucket (including all object versions). Default false is the safety net. NOTE: the world EBS volume's prevent_destroy lifecycle block must still be removed manually — Terraform does not allow gating prevent_destroy on a variable."
  type        = bool
  default     = false
}
