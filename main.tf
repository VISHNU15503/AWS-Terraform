terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = <your_region>
  access_key = <your-access_key>
  secret_key = <your_secret_key>
}

# 1. Create a VPC.
resource "aws_vpc" "prod" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Production VPC"
  }
}

# 2. Create an Internet Gateway.
resource "aws_internet_gateway" "gate-1" {
  vpc_id = aws_vpc.prod.id
  tags = {
    Name = "Production gate 1"
  }
}

# 3. Create a custom Route table.
resource "aws_route_table" "table-1" {
  vpc_id = aws_vpc.prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gate-1.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gate-1.id
  }

  tags = {
    Name = "Production route table"
  }
}

# 4. Create a subnet.
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-north-1a"
  tags = {
    Name = "Procuction Subnet"
  }
}

# 5. Associate our subnet to the route table.
resource "aws_route_table_association" "association-1" {
  subnet_id = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.table-1.id
}

# 6. Create the security group to allow port 22,80,443.
resource "aws_security_group" "web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod.id

  ingress {
    description      = "HTTPS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTP from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "SSH from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7. Create a network interface with an ip in the subnet that is created in step 4.
resource "aws_network_interface" "test" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.web.id]
}

# 8. Assign an elastic IP to the network interface created in step 7.
resource "aws_eip" "one" {
  vpc                    = true
  instance = aws_instance.web-server.id
  network_interface         = aws_network_interface.test.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [ aws_internet_gateway.gate-1 ]
}

output "PublicIP" {
  value = aws_eip.one.public_ip
}

# 9. Create an Ubuntu server ans enable/install apache2.
resource "aws_instance" "web-server" {
  ami = "ami-0989fb15ce71ba39e"
  instance_type = "t3.micro"
  availability_zone = "eu-north-1a"
  key_name = "web-1"
  network_interface {
    network_interface_id = aws_network_interface.test.id
    device_index         = 0
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo your very first web server > /var/www/html/index.html'
              EOF
  
  tags = {
    Name : "Ubuntu Server"
  }
}