provider "aws" {
  region     = "${var.region}"
}
### VPC

# Fetch AZs in the current region
data "aws_availability_zones" "available" {}

resource "aws_vpc" "datastore" {
  cidr_block = "172.17.0.0/16"
}

# Create var.az_count private subnets for RDS, each in a different AZ
resource "aws_subnet" "datastore_rds" {
  count             = "${var.az_count}"
  cidr_block        = "${cidrsubnet(aws_vpc.datastore.cidr_block, 8, count.index)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id            = "${aws_vpc.datastore.id}"
}

# Create var.az_count public subnets for Hasura, each in a different AZ
resource "aws_subnet" "datastore_ecs" {
  count                   = "${var.az_count}"
  cidr_block              = "${cidrsubnet(aws_vpc.datastore.cidr_block, 8, var.az_count + count.index)}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id                  = "${aws_vpc.datastore.id}"
  map_public_ip_on_launch = true
}

# IGW for the public subnet
resource "aws_internet_gateway" "datastore" {
  vpc_id = "${aws_vpc.datastore.id}"
}

# Route the public subnet traffic through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.datastore.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.datastore.id}"
}


### ALB

resource "aws_alb" "datastore" {
  name            = "datastore-alb-${var.environment}"
  subnets         = ["${aws_subnet.datastore_ecs.*.id}"]
  security_groups = ["${aws_security_group.datastore_alb.id}"]
}

resource "aws_alb_target_group" "datastore_hasura" {
  name        = "datastore-alb-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = "${aws_vpc.datastore.id}"
  target_type = "ip"
  health_check {
    path = "/"
    matcher = "302"
  }
}

resource "aws_alb_listener" "datastore" {
  load_balancer_arn = "${aws_alb.datastore.id}"
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = "${data.aws_acm_certificate.datastore.arn}"

  default_action {
    target_group_arn = "${aws_alb_target_group.datastore_hasura.id}"
    type             = "forward"
  }
}

resource "aws_security_group" "datastore_alb" {
  name        = "datastore-alb-${var.environment}"
  description = "Allow access on port 80 only to ALB"
  vpc_id      = "${aws_vpc.datastore.id}"

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_route53_zone" "datastore" {
  name         = "${var.domain}."
}
resource "aws_route53_record" "datastore" {
  zone_id = "${data.aws_route53_zone.datastore.zone_id}"
  name    = "datastore.${var.environment}.${var.domain}"
  type    = "A"

  alias {
    name                   = "${aws_alb.datastore.dns_name}"
    zone_id                = "${aws_alb.datastore.zone_id}"
    evaluate_target_health = true
  }
}

data "aws_acm_certificate" "datastore" {
  domain   = "datastore.${var.environment}.${var.domain}"
  types       = ["AMAZON_ISSUED"] 
  most_recent = true
  statuses = ["ISSUED"]
}


### ECS
resource "aws_ecs_cluster" "datastore" {
  name = "datastore-cluster-${var.environment}"
}

resource "aws_ecs_task_definition" "datastore_hasura" {
  family                   = "hasura-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "${aws_iam_role.datastore_hasura_role.arn}"

  container_definitions = <<DEFINITION
    [
      {
        "cpu": 250,
        "image": "hasura/graphql-engine:v1.0.0-alpha31",
        "memory": 512,
        "name": "hasura",
        "networkMode": "awsvpc",
        "portMappings": [
          {
            "containerPort": 8080,
            "hostPort": 8080
          }
        ],
        "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
            "awslogs-group": "/ecs/datastore-hasura-${var.environment}",
            "awslogs-region": "${var.region}",
            "awslogs-stream-prefix": "ecs"
          }
        },
        "environment": [
          {
            "name": "HASURA_GRAPHQL_ACCESS_KEY",
            "value": "${var.hasura_access_key}"
          },
          {
            "name": "HASURA_GRAPHQL_DATABASE_URL",
            "value": "postgres://${var.rds_username}:${var.rds_password}@${aws_db_instance.datastore.endpoint}/${var.environment}"
          },
          {
            "name": "HASURA_GRAPHQL_ENABLE_CONSOLE",
            "value": "true"
          },
          {
            "name": "HASURA_GRAPHQL_JWT_SECRET",
            "value": "{\"type\":\"HS256\", \"key\": \"${var.hasura_jwt_secret}\"}"
          }
        ]
      }
    ]
DEFINITION
}

resource "aws_ecs_service" "datastore_hasura" {
  depends_on      = ["aws_ecs_task_definition.datastore_hasura", "aws_cloudwatch_log_group.datastore_hasura"]
  name            = "datastore-service-${var.environment}"
  cluster         = "${aws_ecs_cluster.datastore.id}"
  task_definition = "${aws_ecs_task_definition.datastore_hasura.arn}"
  desired_count   = "2"
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip  = true
    security_groups   = ["${aws_security_group.datastore_ecs_hasura.id}"]
    subnets           = ["${aws_subnet.datastore_ecs.*.id}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.datastore_hasura.id}"
    container_name   = "hasura"
    container_port   = "8080"
  }

  depends_on = [
    "aws_alb_listener.datastore",
  ]
}

resource "aws_cloudwatch_log_group" "datastore_hasura" {
  name = "/ecs/datastore-hasura-${var.environment}"
}

data "aws_iam_policy_document" "datastore_hasura_log_publishing" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutLogEventsBatch",
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/ecs/datastore-hasura-${var.environment}:*"]
  }
}

resource "aws_iam_policy" "datastore_hasura_log_publishing" {
  name        = "datastore-hasura-log-pub-${var.environment}"
  path        = "/"
  description = "Allow publishing to cloudwach"

  policy = "${data.aws_iam_policy_document.datastore_hasura_log_publishing.json}"
}

data "aws_iam_policy_document" "datastore_hasura_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "datastore_hasura_role" {
  name               = "datastore-hasura-role-${var.environment}"
  path               = "/system/"
  assume_role_policy = "${data.aws_iam_policy_document.datastore_hasura_assume_role_policy.json}"
}


resource "aws_iam_role_policy_attachment" "datastore_hasura_role_log_publishing" {
  role = "${aws_iam_role.datastore_hasura_role.name}"
  policy_arn = "${aws_iam_policy.datastore_hasura_log_publishing.arn}"
}

resource "aws_security_group" "datastore_ecs_hasura" {
  name        = "datastore-tasks-${var.environment}"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${aws_vpc.datastore.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "8080"
    to_port         = "8080"
    security_groups = ["${aws_security_group.datastore_alb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS
resource "aws_db_instance" "datastore" {
    name                        = "${var.environment}"
    identifier                  = "datastore-${var.environment}"
    username                    = "${var.rds_username}"
    password                    = "${var.rds_password}"
    port                        = "5432"
    engine                      = "postgres"
    engine_version              = "10.5"
    instance_class              = "db.t2.micro"
    allocated_storage           = "10"
    storage_encrypted           = false
    vpc_security_group_ids      = ["${aws_security_group.datastore_rds.id}"]
    db_subnet_group_name        = "${aws_db_subnet_group.datastore.name}"
    parameter_group_name        = "default.postgres10"
    multi_az                    = true
    storage_type                = "gp2"
    publicly_accessible         = false
    # snapshot_identifier         = "datastore-${var.environment}"
    allow_major_version_upgrade = false
    auto_minor_version_upgrade  = false
    apply_immediately           = true
    maintenance_window          = "sun:02:00-sun:04:00"
    skip_final_snapshot         = false
    # copy_tags_to_snapshot       = "${var.copy_tags_to_snapshot}"
    backup_retention_period     = 7
    backup_window               = "04:00-06:00"
    # tags                        = "${module.label.tags}"
    final_snapshot_identifier   = "datastore-${var.environment}"
  }
  

resource "aws_security_group" "datastore_rds" {
  name        = "datastore-rds-${var.environment}"
  description = "allow inbound access from the hasura tasks only"
  vpc_id      = "${aws_vpc.datastore.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "5432"
    to_port         = "5432"
    security_groups = ["${aws_security_group.datastore_ecs_hasura.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_subnet_group" "datastore" {
  name       = "datastore-${var.environment}"
  subnet_ids = ["${aws_subnet.datastore_rds.*.id}"]
}
