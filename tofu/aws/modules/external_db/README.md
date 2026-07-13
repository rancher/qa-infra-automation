# external_db

Provisions an AWS RDS database to use as an **external datastore** (kine) for
K3s / RKE2, instead of embedded etcd. It supports standalone PostgreSQL, MySQL,
and MariaDB instances as well as Aurora MySQL clusters. The module can also
create an RDS subnet group and a dedicated security group that allows access
from the cluster nodes, and it returns the database host and complete
`datastore-endpoint` connection string.

Calling this module always provisions an external database; omit the module
when using embedded etcd. Its behavior mirrors the legacy
distros-test-framework external-db provisioning.

## Engines

| `external_db` | Resource | Connection string emitted |
|---|---|---|
| `postgres` | `aws_db_instance` | `postgres://<user>:<pass>@<host>:5432/<db>` |
| `mysql` / `mariadb` | `aws_db_instance` | `mysql://<user>:<pass>@tcp(<host>:3306)/<db>` |
| `aurora-mysql` | `aws_rds_cluster` + instance | `mysql://<user>:<pass>@tcp(<host>:3306)/<db>` |

## Outputs

- `datastore_endpoint` — full connection string; pass to K3s/RKE2 as
  `datastore-endpoint` (via server flags or `rke2_additional_config`).
- `db_host` — raw RDS endpoint (`host:port`).

## Usage

```hcl
module "external_db" {
  source = "github.com/rancher/qa-infra-automation//tofu/aws/modules/external_db"

  aws_access_key = var.aws_access_key
  aws_secret_key = var.aws_secret_key
  aws_region     = var.aws_region
  resource_name  = "my-cluster"

  external_db        = "postgres"
  external_db_version = "16.3"
  db_group_name      = "default.postgres16"
  instance_class     = "db.t3.medium"
  db_username        = "adminuser"
  db_password        = var.db_password  # required — supply via tfvars / secret plumbing, never hardcode

  aws_security_group = [var.db_security_group]  # must allow 5432/3306 from cluster nodes
  db_subnet_ids      = var.db_subnet_ids        # >=2 AZs; omit to use the account default
}

# Feed the endpoint to the cluster module / ansible server flags:
# server_flags = "datastore-endpoint: ${module.external_db.datastore_endpoint}"
```

The consuming K3s/RKE2 config template renders `datastore-endpoint` and the
product switches to kine automatically — no explicit etcd-disable is required.

## Notes

- The security group must allow inbound on the DB port (5432 postgres, 3306
  mysql/mariadb/aurora) from the cluster nodes' security group / CIDR.
- RDS requires a subnet group spanning ≥2 AZs; pass `db_subnet_ids` in a
  non-default VPC. In the account default VPC the default subnet group is used.
- `db_password` is marked sensitive; the connection string output is also
  sensitive because it embeds the credentials.
