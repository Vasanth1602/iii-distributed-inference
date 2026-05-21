# ── Gateway Public IP ─────────────────────────────────────────────────────────
output "gateway_public_ip" {
  description = "Public IP of the gateway VM - use this to call the API"
  value       = aws_instance.gateway.public_ip
}

# ── Instance IDs for SSM access ───────────────────────────────────────────────
output "gateway_instance_id" {
  description = "Use this to SSM into the gateway VM"
  value       = aws_instance.gateway.id
}

output "inference_instance_id" {
  description = "Use this to SSM into the inference worker VM"
  value       = aws_instance.inference_worker.id
}

# ── Ready-made curl command ───────────────────────────────────────────────────
output "curl_command" {
  description = "Run this to test the API after deployment"
  value       = <<-EOT

    curl -X POST http://${aws_instance.gateway.public_ip}/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{"messages": [{"role": "user", "content": "What is 2+2?"}]}'

  EOT
}

# ── SSM commands ──────────────────────────────────────────────────────────────
output "ssm_commands" {
  description = "Commands to shell into each VM"
  value       = <<-EOT

    # Shell into gateway VM:
    aws ssm start-session --target ${aws_instance.gateway.id} --region ${var.aws_region}

    # Shell into inference worker VM:
    aws ssm start-session --target ${aws_instance.inference_worker.id} --region ${var.aws_region}

  EOT
}