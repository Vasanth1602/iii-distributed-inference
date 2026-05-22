# ── Fetch latest Ubuntu 22.04 AMI automatically ───────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical official

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Gateway VM ────────────────────────────────────────────────────────────────
resource "aws_instance" "gateway" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.gateway_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.gateway.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  associate_public_ip_address = true

  # Fixed private IP so inference worker always knows where engine is
  private_ip = var.gateway_private_ip

  root_block_device {
    volume_size = var.gateway_disk_gb
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/../scripts/gateway_userdata.sh", {
    github_repo  = var.github_repo
    project_name = var.project_name
  })

  tags = {
    Name = "${var.project_name}-gateway"
  }
}

# ── Inference Worker VM ───────────────────────────────────────────────────────
resource "aws_instance" "inference_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.inference_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.inference.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  # No public IP - private subnet only
  associate_public_ip_address = false

  root_block_device {
    volume_size = var.inference_disk_gb
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/../scripts/inference_userdata.sh", {
    github_repo        = var.github_repo
    gateway_private_ip = var.gateway_private_ip
  })

  tags = {
    Name = "${var.project_name}-inference-worker"
  }

  # Gateway must exist before inference worker starts
  depends_on = [
    aws_instance.gateway,
    aws_route_table_association.private
  ]
}