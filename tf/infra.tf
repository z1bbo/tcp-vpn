resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.r.id
}

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "ssh_key"
  public_key = file("~/.ssh/id_ed25519.pub")
}

resource "aws_autoscaling_group" "vpn_asg" {
  launch_configuration = aws_launch_configuration.vpn_launch_config.name
  min_size             = 1
  max_size             = 1
  desired_capacity     = 1
  vpc_zone_identifier  = [aws_subnet.subnet.id]
}

resource "aws_launch_configuration" "vpn_launch_config" {
  image_id             = "ami-08fad42036d22d32d" # 22.04 LTS https://cloud-images.ubuntu.com/locator/ec2/
  instance_type        = "t2.micro"
  key_name             = aws_key_pair.ssh_key.key_name
  security_groups      = [aws_security_group.sg.id]
  iam_instance_profile = aws_iam_instance_profile.eip_association.name

  user_data = templatefile("${path.module}/user_data.tpl", {
    aws_region = local.aws_region,
    eip_public_ip = aws_eip.vpn_eip.public_ip
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eip" "vpn_eip" {
  domain = "vpc"
}

output "vpn_server_ip" {
  value = aws_eip.vpn_eip.public_ip
}

