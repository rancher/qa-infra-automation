# datastore_endpoint is the full kine connection string that K3s/RKE2 consume as
# `datastore-endpoint`. Empty for embedded etcd. Format mirrors the legacy
# distros-test-framework rendering so downstream parsing is unchanged.
locals {
  _pg_endpoint     = local.is_standrds && var.external_db == "postgres" ? aws_db_instance.db[0].endpoint : ""
  _mysql_endpoint  = local.is_standrds && var.external_db != "postgres" ? aws_db_instance.db[0].endpoint : ""
  _aurora_endpoint = local.is_aurora ? aws_rds_cluster.db[0].endpoint : ""

  datastore_endpoint = (
    var.external_db == "postgres" && local._pg_endpoint != "" ?
    "postgres://${var.db_username}:${var.db_password}@${local._pg_endpoint}/${var.db_name}" :
    (
      local.is_aurora ?
      "mysql://${var.db_username}:${var.db_password}@tcp(${local._aurora_endpoint})/${var.db_name}" :
      (
        local._mysql_endpoint != "" ?
        "mysql://${var.db_username}:${var.db_password}@tcp(${local._mysql_endpoint})/${var.db_name}" :
        ""
      )
    )
  )

  db_host = coalesce(local._pg_endpoint, local._mysql_endpoint, local._aurora_endpoint, "")
}

output "datastore_endpoint" {
  description = "Full connection string for K3s/RKE2 datastore-endpoint; empty for etcd."
  value       = local.datastore_endpoint
  sensitive   = true
}

output "db_host" {
  description = "Raw RDS endpoint (host:port); empty for etcd."
  value       = local.db_host
}

output "datastore_type" {
  description = "Echoes the requested datastore type (etcd | external)."
  value       = var.datastore_type
}
