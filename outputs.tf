output "vpc" {
  description = "VPC created to hold Hasura resources"
  value = aws_vpc.hasura
}

output "private_subnets" {
  description = "Private subnets created for RDS within the VPC, each in a different AZ"
  value = aws_subnet.hasura_private
}

output "public_subnets" {
  description = "Public subnets created for Hasura within the VPC, each in a different AZ"
  value = aws_subnet.hasura_public
}

output "ecs_security_group" {
  description = "Security group controlling access to the ECS tasks"
  value = aws_security_group.hasura_ecs
}