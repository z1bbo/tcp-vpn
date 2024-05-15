terraform {
  backend "s3" {
    bucket  = "ctfstate"
    key     = "terraform.tfstate"
    region  = "ap-southeast-1"
    encrypt = true
  }
}

provider "aws" {
  region = local.aws_region
}

