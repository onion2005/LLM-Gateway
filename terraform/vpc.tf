# ─── Security Groups ──────────────────────────────────────────────────────────

resource "aws_security_group" "lambda" {
  name        = "summariser-lambda"
  description = "Lambda functions: egress to AWS service endpoints only"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to AWS services via VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "summariser-vpc-endpoints"
  description = "VPC interface endpoints: accept HTTPS from Lambda"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from Lambda"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}

# ─── Gateway Endpoints (free) ─────────────────────────────────────────────────

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.vpc_route_table_id]
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.vpc_route_table_id]
}

# ─── Interface Endpoints (~$14/month each) ────────────────────────────────────

resource "aws_vpc_endpoint" "transcribe" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.transcribe"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.lambda_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "lambda" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.lambda"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.lambda_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}
