# ── Gateway Security Group ─────────────────────────────────────────────────────
resource "aws_security_group" "gateway" {
  name        = "${var.project_name}-gateway-sg"
  description = "Gateway VM - only port 80 public, engine WS internal only"
  vpc_id      = aws_vpc.main.id

  # HTTP from internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # iii engine WebSocket - only from private subnet
  ingress {
    description = "iii engine WS from private subnet only"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  # All outbound allowed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-gateway-sg"
  }
}

# ── Inference Worker Security Group ───────────────────────────────────────────
resource "aws_security_group" "inference" {
  name        = "${var.project_name}-inference-sg"
  description = "Inference worker VM - no inbound from internet at all"
  vpc_id      = aws_vpc.main.id

  # All outbound allowed
  # NAT Gateway handles routing - needed for pip install + model download
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-inference-sg"
  }
}