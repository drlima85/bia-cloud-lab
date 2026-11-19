#!/bin/bash
# User Data: user_data_ec2_zona_a.sh
# Finalidade: Bootstrap automatizado da instância EC2 BIA Dev (Docker, Compose, Node.js, AWS CLI, uv/MCP)
# Referência: Formação AWS (Henrylle Maia) | Adaptações: BIA Cloud Lab (Danilo Lima)

set -e

# Configurações de versões parametrizáveis (com padrões do laboratório)
DOCKER_COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-v2.23.3}"
NODE_MAJOR="${NODE_MAJOR:-22}"

# 1. Atualização do sistema e instalação de pacotes essenciais
sudo yum update -y
sudo yum install -y git docker jq unzip

# 2. Instalação do AWS CLI v2
if ! command -v aws >/dev/null 2>&1; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
fi

# 3. Configuração de permissões de grupo do Docker para ec2-user e ssm-user
sudo usermod -a -G docker ec2-user || true
if id ssm-user >/dev/null 2>&1; then
    sudo usermod -a -G docker ssm-user || true
fi

# 4. Habilitação e inicialização do serviço Docker
sudo systemctl enable docker.service
sudo systemctl start docker.service

# 5. Instalação do Docker Compose v2 como plugin de CLI
sudo mkdir -p /usr/local/lib/docker/cli-plugins
if [ ! -f /usr/local/lib/docker/cli-plugins/docker-compose ]; then
    sudo curl -fsSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# 6. Configuração de Swapfile (4 GB) para estabilidade de compilações
if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=128M count=32
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
    fi
fi

# 7. Instalação do Node.js LTS e npm
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | sudo bash -
    sudo yum install -y nodejs
fi

# 8. Configuração de Python 3.11 e Astral uv para ferramentas MCP
if ! command -v python3.11 >/dev/null 2>&1; then
    sudo dnf install -y python3.11 || sudo yum install -y python3.11 || true
fi

if [ -f /usr/bin/python3.11 ]; then
    sudo ln -sf /usr/bin/python3.11 /usr/bin/python3
fi

# Instalação do Astral uv para o usuário ec2-user
if [ -d /home/ec2-user ]; then
    sudo -u ec2-user bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || true
    if ! grep -q '.local/bin' /home/ec2-user/.bashrc; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/ec2-user/.bashrc
    fi
fi
