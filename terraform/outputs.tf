output "kube_1_public_ip" {
  description = "Public IP of kube-1 (control plane)"
  value       = aws_instance.kube_1.public_ip
}

output "kube_2_public_ip" {
  description = "Public IP of kube-2 (worker)"
  value       = aws_instance.kube_2.public_ip
}

output "ingress_public_ip" {
  description = "Public IP of ingress node"
  value       = aws_instance.ingress.public_ip
}

output "monitoring_public_ip" {
  description = "Public IP of monitoring node"
  value       = aws_instance.monitoring.public_ip
}

output "kube_1_private_ip" {
  value = aws_instance.kube_1.private_ip
}

output "kube_2_private_ip" {
  value = aws_instance.kube_2.private_ip
}

output "ingress_private_ip" {
  value = aws_instance.ingress.private_ip
}

output "monitoring_private_ip" {
  value = aws_instance.monitoring.private_ip
}

output "ssh_commands" {
  description = "SSH commands to connect to each node"
  value = {
    kube_1     = "ssh ubuntu@${aws_instance.kube_1.public_ip}"
    kube_2     = "ssh ubuntu@${aws_instance.kube_2.public_ip}"
    ingress    = "ssh ubuntu@${aws_instance.ingress.public_ip}"
    monitoring = "ssh ubuntu@${aws_instance.monitoring.public_ip}"
  }
}
