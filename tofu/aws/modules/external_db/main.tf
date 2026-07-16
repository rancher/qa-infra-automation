# External datastore RDS provisioning.

resource "random_id" "db" {
  byte_length = 4
}

locals {
  # Normalize the engine once so casing is consistent everywhere (validation
  # accepts mixed case; the module compares/uses lowercase throughout).
  external_db  = lower(var.external_db)
  is_aurora    = local.external_db == "aurora-mysql"
  is_standrds  = !local.is_aurora
  identifier   = "${var.resource_name}-${random_id.db.hex}-db"
  needs_subnet = length(var.db_subnet_ids) > 0
  db_port      = local.external_db == "postgres" ? 5432 : 3306
  # Prefer our dedicated SG (opens the DB port from the cluster nodes); fall back
  # to the caller-provided SG only if no VPC was given to create one.
  make_db_sg = var.aws_vpc != "" && length(var.aws_security_group) > 0
  rds_sg_ids = local.make_db_sg ? [aws_security_group.db[0].id] : (length(var.aws_security_group) > 0 ? var.aws_security_group : null)
}

# Dedicated per-run security group for the RDS, allowing the DB port only from
# the cluster nodes' security group. Kept separate from the shared cluster SG so
# concurrent runs don't collide on a self-referencing ingress rule.
resource "aws_security_group" "db" {
  count       = local.make_db_sg ? 1 : 0
  name        = "${local.identifier}-sg"
  description = "kine external datastore access for ${local.identifier}"
  vpc_id      = var.aws_vpc

  ingress {
    description     = "kine DB access from cluster nodes"
    from_port       = local.db_port
    to_port         = local.db_port
    protocol        = "tcp"
    security_groups = var.aws_security_group
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = var.environment
    Team        = var.resource_name
  }
}

# Dedicated subnet group when explicit subnets are provided; otherwise RDS uses
# the account's default subnet group.
resource "aws_db_subnet_group" "db" {
  count      = local.needs_subnet ? 1 : 0
  name       = "${local.identifier}-subnets"
  subnet_ids = var.db_subnet_ids
  tags = {
    Environment = var.environment
    Team        = var.resource_name
  }
}

# Standalone engines: postgres / mysql / mariadb.
resource "aws_db_instance" "db" {
  count                  = local.is_standrds ? 1 : 0
  identifier             = local.identifier
  storage_type           = "gp2"
  allocated_storage      = var.allocated_storage
  engine                 = local.external_db
  engine_version         = var.external_db_version
  instance_class         = var.instance_class
  name                   = var.db_name
  parameter_group_name   = var.db_group_name != "" ? var.db_group_name : null
  username               = var.db_username
  password               = var.db_password
  availability_zone      = var.availability_zone != "" ? var.availability_zone : null
  vpc_security_group_ids = local.rds_sg_ids
  db_subnet_group_name   = local.needs_subnet ? aws_db_subnet_group.db[0].name : null
  skip_final_snapshot    = true
  # Cluster nodes reach the DB privately within the VPC via the dedicated SG; no public exposure needed.
  publicly_accessible = false
  tags = {
    Environment = var.environment
    Team        = var.resource_name
  }
}

# Aurora MySQL cluster + a single instance.
resource "aws_rds_cluster" "db" {
  count                  = local.is_aurora ? 1 : 0
  cluster_identifier     = local.identifier
  engine                 = local.external_db
  engine_version         = var.external_db_version
  engine_mode            = var.engine_mode
  database_name          = var.db_name
  master_username        = var.db_username
  master_password        = var.db_password
  vpc_security_group_ids = local.rds_sg_ids
  db_subnet_group_name   = local.needs_subnet ? aws_db_subnet_group.db[0].name : null
  skip_final_snapshot    = true
  tags = {
    Environment = var.environment
    Team        = var.resource_name
  }
}

resource "aws_rds_cluster_instance" "db" {
  count              = local.is_aurora ? 1 : 0
  cluster_identifier = aws_rds_cluster.db[0].id
  identifier         = "${local.identifier}-instance1"
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.db[0].engine
  engine_version     = aws_rds_cluster.db[0].engine_version
}
