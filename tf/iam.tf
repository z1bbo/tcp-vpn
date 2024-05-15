resource "aws_iam_instance_profile" "eip_association" {
  name = "eip_association_profile"
  role = aws_iam_role.eip_association.name
}

resource "aws_iam_role" "eip_association" {
  name = "eip_association_role"

  assume_role_policy = jsonencode({
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ],
    Version = "2012-10-17"
  })

  inline_policy {
    name = "eip_association_policy"
    policy = jsonencode({
      Statement = [
        {
          Action = [
            "ec2:AssociateAddress",
            "ec2:DescribeInstances",
            "secretsmanager:CreateSecret",
            "secretsmanager:DescribeSecret",
            "secretsmanager:GetSecretValue"
          ],
          Effect   = "Allow",
          Resource = "*"
        }
      ],
      Version = "2012-10-17"
    })
  }
}

