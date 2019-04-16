# Hasura on AWS

Terraform module to deploy Hausra graphql engine on AWS. This will deploy
across multiple Availability Zones (AZ) with the following components:

-   Postgres RDS Database deployed in multiple AZ
-   Hasura graphql engine in Fargate across multiple AZ
-   ALB for load balancing between the hasura tasks
-   Certificate issued by ACM for securing traffic to ALB
-   Logging for RDS, ECS, and ALB into Cloudwatch Logs

## Requirements

-   AWS account
    -   IAM user
    -   domain with Route53
-   Terraform

## License

MIT
