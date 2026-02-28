variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "with-context"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "phone-coding"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for EC2 access"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "ts_authkey" {
  description = "Tailscale auth key (tskey-auth-...)"
  type        = string
  sensitive   = true
}

variable "amp_api_key" {
  description = "Amp API key"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "use_spot" {
  description = "Use spot instance for cost savings"
  type        = bool
  default     = false
}
