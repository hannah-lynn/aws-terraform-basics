# Configure the AWS Provide
# Assuming the AWS cli is installed run aws configure --profile=default and add the creds.

# Variables

variable "subnet_prefix" {
    description = "cidr block for the subnet"
    # default is the variable that terraform will pass if we don't give it one eg:
    # default = "10.0.3.0/50"
    # Type can be number, boolean, list, map, set, object, tuple or any etc
    type = list(string)
}

# Creating an EC2 instance

# resource "aws_instance" "first-terraform-ec2" {
#   ami           = "ami-007855ac798b5175e"
#   instance_type = "t2.micro"
#   tags = {
#     Name = "ubuntuServer"
#   }
# }

# Creating a VPC

# resource "aws_vpc" "first-terraform-vpc" {
#   cidr_block = "10.0.0.0/16"
#     tags = {
#     Name = "test"
#   }
# }

# Creating a subnet

# resource "aws_subnet" "subnet-1" {
#   vpc_id     = aws_vpc.first-terraform-vpc.id
#   cidr_block = "10.0.1.0/24"

#   tags = {
#     Name = "test-subnet"
#   }
# }


# Mini project steps:

# 1. Create VPC

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
    tags = {
    Name = "production"
  }
}

# 2. Create internet gateway

resource "aws_internet_gateway" "prod-gateway" {
  vpc_id = aws_vpc.prod-vpc.id
}

# 3. Create custom route table

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    # this is a default route send all traffic to the interet gateway
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod-gateway.id
  }

  route {
    # ::/0 is the same as above 0.0.0.0/0 but for ipv4
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.prod-gateway.id
  }

  tags = {
    Name = "production"
  }
}

# 4. Create subnet

resource "aws_subnet" "prod-subnet-1" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = var.subnet_prefix[0]
  availability_zone = "us-east-1a"

  tags = {
    Name = "production"
  }
}

# 5. Associate subnet with route table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.prod-subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# 6. Create security group allowing ports 22, 80, 443 (ssh, http, https)

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    # You can put a specific IP address here if you want, eg your own computer
    cidr_blocks      = ["0.0.0.0/0"]
  }

    ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    # You can put a specific IP address here if you want, eg your own computer
    cidr_blocks      = ["0.0.0.0/0"]
  }

    ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    # You can put a specific IP address here if you want, eg your own computer
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    # This is saying we are allowing all ports in the egress direction
    from_port        = 0
    to_port          = 0
    # -1 means any protocol
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7. Create a network interface with an IP in the subnet created in step 4

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.prod-subnet-1.id
  # This is the IP/s we want to give the server - any address within the subnet
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# 8. Assign an elastic IP to the network interface created in step 7

resource "aws_eip" "one" {
  # if it's in a VPC or not
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.prod-gateway]
}

# This will print the public IP address when you terraform apply
output "server_public_ip" {
  value = aws_eip.one.public_ip
}

# 9. Create a ubuntu server and install/enable Apache

resource "aws_instance" "web-server-instance" {
  ami           = "ami-007855ac798b5175e"
  instance_type = "t2.micro"
  # Important to set this to the same one as the subnet (if you don't hard code this amazon randomly picks one for you)
  availability_zone = "us-east-1a"
  key_name = "first-access-key"

  network_interface {
    # This is the first network interface associated with this device
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  # This is what tells aws to install apache
  user_data = <<EOF
    #! /bin/bash
    sudo apt-get update
    sudo apt-get install -y apache2
    sudo systemctl start apache2
    sudo systemctl enable apache2
    echo "<h1>Deployed via Terraform</h1>" | sudo tee /var/www/html/index.html
    EOF

  tags = {
    Name = "web-server"
  }
}
