# create terraform.tfvars with the following variables [access_key, secret_key, region, availability_zone]
provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

variable "access_key" {
  type        = string
  description = "aws access key"
}

variable "secret_key" {
  type        = string
  description = "aws secret key"
}

variable "region" {
  type        = string
  description = "aws region"
}

variable "availability_zone" {
  type        = string
  description = "web server availability zone"
}

resource "aws_vpc" "dev-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "dev-vpc"
  }
}

resource "aws_internet_gateway" "dev-gw" {
  vpc_id = aws_vpc.dev-vpc.id
  tags = {
    Name = "dev-gw"
  }
}

resource "aws_route_table" "dev-route-table" {
  vpc_id = aws_vpc.dev-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev-gw.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.dev-gw.id
  }
  tags = {
    Name = "dev-route-table"
  }
}

resource "aws_subnet" "dev-subnet" {
  vpc_id            = aws_vpc.dev-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.availability_zone

  tags = {
    Name = "dev-subnet"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.dev-subnet.id
  route_table_id = aws_route_table.dev-route-table.id
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.dev-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.dev-subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.dev-gw]
}

resource "aws_instance" "web-server" {
  ami               = "ami-04505e74c0741db8d"
  instance_type     = "t2.micro"
  availability_zone = var.availability_zone
  key_name          = "tf"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  tags = {
    Name = "dev-server"
  }

  user_data = <<-EOF
              #!bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c "echo this is a web server! > /var/www/html/index.html"
              EOF
}

output "server_ec2_id" {
  value = aws_instance.web-server.id
}

output "server_ec2_vol" {
  value = aws_instance.web-server.root_block_device
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}