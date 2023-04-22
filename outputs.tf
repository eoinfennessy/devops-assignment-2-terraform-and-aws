output "private_key_pem" {
  description = "Private key data in PEM (RFC 1421) format"
  value       = module.key_pair.private_key_pem
  sensitive   = true
}

resource "local_file" "private_key" {
  content  = module.key_pair.private_key_pem
  filename = "${module.key_pair.key_pair_name}.pem"
  file_permission = 600
}
