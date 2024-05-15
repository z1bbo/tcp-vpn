resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket
}

