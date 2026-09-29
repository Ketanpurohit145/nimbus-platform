output "public_ip" { # used by CI/CD deploy.sh to SSH/curl the instance
  value = aws_instance.app.public_ip
}

output "instance_id" {
  value = aws_instance.app.id
}
