terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
    region = var.region
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = var.my_vpc

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/12"]
  }
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.cidr, "172.16.0.0/12"]
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks = ["10.12.20.0/22"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_security_group" "rds" {
  name        = "terraform_rds_security_group"
  description = "Terraform example RDS MySQL server"
  vpc_id      = var.my_vpc
  # Keep the instance private by only allowing traffic from the web server.
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks = ["10.12.20.0/22", "172.16.0.0/12"]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks = ["10.12.20.0/22", "172.16.0.0/12"]
  }
  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}

resource "aws_security_group" "alb" {
  name        = "terraform_alb_security_group"
  description = "Terraform load balancer security group"
  vpc_id      = var.my_vpc

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.cidr, "172.16.0.0/12"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}

resource "random_pet" "name" {}

resource "aws_instance" "webBoxAZa" {
  ami           = "ami-0b036c70cad103a4a"
  instance_type = var.my_instance_type
  subnet_id     = var.subnetAppA
  count = 2
  key_name = "Joes_legendary_keyPair"
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  tags = {
    Name = "${random_pet.name.id} AZa-${count.index}"
    Owner = var.owner
  }
  credit_specification {
    cpu_credits = "standard"
  }
}
 
 resource "aws_instance" "webBoxAZb" {
  ami           = "ami-0b036c70cad103a4a"
  instance_type = var.my_instance_type
  subnet_id     = var.subnetAppB
  count = 2
  key_name = "Joes_legendary_keyPair"
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  tags = {
    Name = "${random_pet.name.id} AZb-${count.index}"
    Owner = var.owner
  }
  credit_specification {
    cpu_credits = "standard"
  }
}

resource "aws_lb" "alb" {
  name = "j-webBox-alb"
  internal = true
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb.id]
  subnets = [var.subnetAppA, var.subnetAppB]
 
  tags = {
      Owner = var.owner
  }
}

resource "aws_lb_target_group" "alb_tgroup" {
  name = "j-alb-webBox-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = var.my_vpc
}

resource "aws_lb_target_group_attachment" "alb-tg-attchA" {
  target_group_arn = aws_lb_target_group.alb_tgroup.arn
  count = 2
  target_id = aws_instance.webBoxAZa[count.index].id
  port = 80
}

resource "aws_lb_target_group_attachment" "alb-tg-attchB" {
  target_group_arn = aws_lb_target_group.alb_tgroup.arn
  count = 2
  target_id = aws_instance.webBoxAZb[count.index].id
  port = 80
}

resource "aws_alb_listener" "listener_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.alb_tgroup.arn
    type             = "forward"
  }
}

resource "aws_rds_cluster" "postgresql" {
  cluster_identifier      = "${random_pet.name.id}-aurora-cluster"
  engine                  = "aurora-postgresql"
  availability_zones      = ["ap-southeast-2a", "ap-southeast-2b"]
  database_name           = "JoesTestDB"
  master_username         = "joe"
  master_password         = "gbst1234"
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  db_subnet_group_name    = aws_db_subnet_group.default.id
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.rds.id]
}

resource "aws_rds_cluster_instance" "cluster_instances" {
  count              = 2
  identifier         = "${random_pet.name.id}rds-cluster-${count.index}"
  cluster_identifier = aws_rds_cluster.postgresql.id
  instance_class     = "db.r4.large"
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
  db_subnet_group_name    = aws_db_subnet_group.default.id
}

resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = [var.db_subnet_a, var.db_subnet_b]

  tags = {
    Name = "Joe DB subnet group"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "epic-logholding-super-bucket-ayyy"
  acl    = "private"

  tags = {
    Name        = "Log bucket"
    Environment = "Dev"
  }
}

output testA {
  value = aws_instance.webBoxAZa.*.private_ip
}

output testB {
  value = aws_instance.webBoxAZb.*.private_ip
}

