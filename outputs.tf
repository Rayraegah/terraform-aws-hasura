output "vpc" {
  value = aws_vpc.hasura
}

output "private_subnets" {
  value = aws_subnet.hasura_private
}

output "public_subnets" {
  value = aws_subnet.hasura_public
}

output "ecs_security_group" {
  value = aws_security_group.hasura_ecs
}