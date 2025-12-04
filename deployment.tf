terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

# --- VARIABLES DE ENTRADA (Auth0 y Configuración) ---
variable "key_name" {
  description = "Nombre de la llave SSH (sin .pem)"
  type        = string
  default     = "vockey" # Valor por defecto en AWS Academy
}

variable "auth0_domain" {
  description = "Dominio de Auth0"
  type        = string
}
variable "auth0_audience" {
  description = "Audience de la API (Inventario)"
  type        = string
}
variable "auth0_client_id" {
  description = "Client ID (Pedidos)"
  type        = string
}
variable "auth0_client_secret" {
  description = "Client Secret (Pedidos)"
  type        = string
  sensitive   = true
}

# --- GRUPO DE SEGURIDAD ---
# Necesario para que se vean entre ellos y desde internet
resource "aws_security_group" "microservices_sg" {
  name        = "msd-security-group-asr"
  description = "Permitir trafico para microservicios ASR"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
  }
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Kong
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Microservicios
  }
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Postgres
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 1. MANEJADOR DE PEDIDOS (Antes Variables) ---
# Base de Datos Pedidos
resource "aws_instance" "pedidos_db" {
  ami                    = "ami-051685736c7b35f95" # Amazon Linux 2023
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.microservices_sg.id]
  tags = {
    Name = "msd-pedidos-db"
    Role = "db-pedidos"
  }
  user_data = <<-EOF
    #!/bin/bash
    docker run --restart=always -d \
      -e POSTGRES_USER=pedidos_user \
      -e POSTGRES_DB=pedidos_db \
      -e POSTGRES_PASSWORD=isis2503 \
      -p 5432:5432 postgres
  EOF
}

# Microservicio Pedidos (Cliente)
resource "aws_instance" "manejador_pedidos" {
  ami                    = "ami-051685736c7b35f95"
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.microservices_sg.id]
  tags = {
    Name = "msd-manejador-pedidos"
    Role = "pedidos-ms"
  }
  
  # Inyectamos credenciales para SOLICITAR tokens
  user_data = <<-EOF
    #!/bin/bash
    echo "export AUTH0_DOMAIN='${var.auth0_domain}'" >> /etc/environment
    echo "export AUTH0_CLIENT_ID='${var.auth0_client_id}'" >> /etc/environment
    echo "export AUTH0_CLIENT_SECRET='${var.auth0_client_secret}'" >> /etc/environment
    
    sudo dnf install nano git docker -y
    sudo systemctl start docker
    sudo systemctl enable docker
    
    sudo mkdir /labs
    cd /labs
    sudo git clone https://github.com/ISIS2503/ISIS2503-Microservices-AppDjango.git
    cd ISIS2503-Microservices-AppDjango/variables
    
    # Construir y correr usando la DB de Pedidos
    docker build -t pedidos-app .
    docker run -d --name pedidos-ms -p 8080:8080 \
      -e AUTH0_DOMAIN='${var.auth0_domain}' \
      -e AUTH0_CLIENT_ID='${var.auth0_client_id}' \
      -e AUTH0_CLIENT_SECRET='${var.auth0_client_secret}' \
      -e VARIABLES_DB_HOST='${aws_instance.pedidos_db.private_ip}' \
      -e VARIABLES_DB_NAME='pedidos_db' \
      -e VARIABLES_DB_USER='pedidos_user' \
      pedidos-app
  EOF
}

# --- 2. MANEJADOR DE INVENTARIO (Antes Measurements) ---
# Base de Datos Inventario
resource "aws_instance" "inventario_db" {
  ami                    = "ami-051685736c7b35f95"
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.microservices_sg.id]
  tags = {
    Name = "msd-inventario-db"
    Role = "db-inventario"
  }
  user_data = <<-EOF
    #!/bin/bash
    docker run --restart=always -d \
      -e POSTGRES_USER=inventario_user \
      -e POSTGRES_DB=inventario_db \
      -e POSTGRES_PASSWORD=isis2503 \
      -p 5432:5432 postgres
  EOF
}

# Microservicio Inventario (Protegido)
resource "aws_instance" "manejador_inventario" {
  ami                    = "ami-0c1f44f890950b53c" # Ubuntu (según tu plan original)
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.microservices_sg.id]
  tags = {
    Name = "msd-manejador-inventario"
    Role = "inventario-ms"
  }

  # Inyectamos variables para VALIDAR tokens
  user_data = <<-EOF
    #!/bin/bash
    echo "export AUTH0_DOMAIN='${var.auth0_domain}'" >> /etc/environment
    echo "export AUTH0_AUDIENCE='${var.auth0_audience}'" >> /etc/environment
    
    sudo apt-get update
    sudo apt-get install -y docker.io git nano
    
    sudo mkdir /labs
    cd /labs
    sudo git clone https://github.com/ISIS2503/ISIS2503-Microservices-AppDjango.git
    cd ISIS2503-Microservices-AppDjango/measurements

    # Construir y correr apuntando a la DB de Inventario y sabiendo dónde están los Pedidos
    docker build -t inventario-app .
    docker run -d --name inventario-ms -p 8080:8080 \
      -e AUTH0_DOMAIN='${var.auth0_domain}' \
      -e AUTH0_AUDIENCE='${var.auth0_audience}' \
      -e MEASUREMENTS_DB_HOST='${aws_instance.inventario_db.private_ip}' \
      -e MEASUREMENTS_DB_NAME='inventario_db' \
      -e MEASUREMENTS_DB_USER='inventario_user' \
      -e VARIABLES_HOST='${aws_instance.manejador_pedidos.private_ip}' \
      inventario-app
  EOF
}

# --- 3. API GATEWAY (Kong) ---
resource "aws_instance" "kong" {
  ami                    = "ami-051685736c7b35f95"
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.microservices_sg.id]
  tags = {
    Name = "msd-kong-gateway"
    Role = "api-gateway"
  }

  # Configuración dinámica de Kong con las IPs de los NUEVOS recursos
  user_data = <<-EOF
    #!/bin/bash
    sudo dnf install nano git docker -y
    sudo systemctl start docker
    sudo systemctl enable docker

    sudo mkdir /labs
    cd /labs
    sudo git clone https://github.com/ISIS2503/ISIS2503-Microservices-AppDjango.git
    cd ISIS2503-Microservices-AppDjango
    
    # Reemplazamos las IPs en el archivo kong.yaml usando las variables de Terraform
    # VARIABLES_HOST -> IP del Manejador de Pedidos
    # MEASUREMENTS_HOST -> IP del Manejador de Inventario
    sudo sed -i "s/<VARIABLES_HOST>/${aws_instance.manejador_pedidos.private_ip}/g" kong.yaml
    sudo sed -i "s/<MEASUREMENTS_HOST>/${aws_instance.manejador_inventario.private_ip}/g" kong.yaml
    
    docker network create kong-net
    docker run -d --name kong --network=kong-net --restart=always \
      -v "$(pwd):/kong/declarative/" -e "KONG_DATABASE=off" \
      -e "KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yaml" \
      -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
      -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
      -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
      -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
      -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
      -p 8000:8000 \
      -p 8443:8443 \
      -p 127.0.0.1:8001:8001 \
      -p 127.0.0.1:8444:8444 \
      kong:latest
  EOF
}

# --- OUTPUTS (Para que sepas dónde conectarte) ---
output "kong_public_ip" {
  value = aws_instance.kong.public_ip
}
output "manejador_pedidos_ip" {
  value = aws_instance.manejador_pedidos.public_ip
}
output "manejador_inventario_ip" {
  value = aws_instance.manejador_inventario.public_ip
}
