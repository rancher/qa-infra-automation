# datastore_endpoint is the full kine connection string that K3s/RKE2 consume as
# `datastore-endpoint`. Format mirrors the legacy distros-test-framework
# rendering so downstream parsing is unchanged.
locals {
  db_host = local.is_aurora ? "${aws_rds_cluster.db[0].endpoint}:${aws_rds_cluster.db[0].port}" : aws_db_instance.db[0].endpoint

  datastore_endpoint = (
    local.external_db == "postgres" ?
    "postgres://${var.db_username}:${var.db_password}@${local.db_host}/${var.db_name}" :
    "mysql://${var.db_username}:${var.db_password}@tcp(${local.db_host})/${var.db_name}"
  )
}

output "datastore_endpoint" {
  description = "Full connection string for K3s/RKE2 datastore-endpoint."
  value       = local.datastore_endpoint
  sensitive   = true
}

output "db_host" {
  description = "Raw RDS endpoint (host:port)."
  value       = local.db_host
}
