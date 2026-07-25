# ─── VPC & NETWORK INFRASTRUCTURE ─────────────────────────────────────────────
resource "aws_vpc" "syncwrite_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "syncwrite-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.syncwrite_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "syncwrite-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.syncwrite_vpc.id

  tags = {
    Name = "syncwrite-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.syncwrite_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "syncwrite-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ─── SECURITY GROUP ─────────────────────────────────────────────────────────
resource "aws_security_group" "syncwrite_sg" {
  name        = "syncwrite-security-group"
  description = "Security group for SyncWrite web app and API cluster"
  vpc_id      = aws_vpc.syncwrite_vpc.id

  # SSH Access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    description = "HTTP Web Access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS Secure Web Access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Backend Socket API (direct access if needed)
  ingress {
    description = "Backend Socket API Port"
    from_port   = 3005
    to_port     = 3005
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound All Traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "syncwrite-sg"
  }
}

# ─── SSH KEY PAIR ─────────────────────────────────────────────────────────────
resource "aws_key_pair" "deployer_key" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

# ─── AMIS & EC2 INSTANCE ─────────────────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "syncwrite_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.syncwrite_sg.id]
  key_name               = aws_key_pair.deployer_key.key_name

  root_block_device {
    volume_size           = 25
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "syncwrite-app-server"
  }
}

# ─── ELASTIC IP ASSIGNMENT ────────────────────────────────────────────────────
resource "aws_eip" "syncwrite_eip" {
  instance = aws_instance.syncwrite_server.id
  domain   = "vpc"

  tags = {
    Name = "syncwrite-eip"
  }
}
