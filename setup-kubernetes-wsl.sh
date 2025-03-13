#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Preparando ambiente Kubernetes no WSL com Ubuntu...${NC}"

# Atualizar pacotes
echo -e "${YELLOW}Atualizando pacotes...${NC}"
sudo apt-get update
sudo apt-get upgrade -y

# Instalar dependências
echo -e "${YELLOW}Instalando dependências...${NC}"
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Instalar Docker se não estiver instalado
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Instalando Docker...${NC}"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Configurar Docker para ser usado sem sudo
    sudo groupadd docker || true
    sudo usermod -aG docker $USER
    
    echo -e "${GREEN}Docker instalado. Você pode precisar reiniciar o WSL para usar Docker sem sudo.${NC}"
    echo -e "${YELLOW}Execute 'wsl --shutdown' no PowerShell e reabra o terminal WSL${NC}"
else
    echo -e "${GREEN}Docker já está instalado.${NC}"
fi

# Instalar kubectl
echo -e "${YELLOW}Instalando kubectl...${NC}"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Instalar Minikube
echo -e "${YELLOW}Instalando Minikube...${NC}"
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

# Verificar instalações
echo -e "${YELLOW}Verificando versões instaladas:${NC}"
echo -e "${GREEN}Docker:${NC} $(docker --version)"
echo -e "${GREEN}kubectl:${NC} $(kubectl version --client --output=yaml | grep gitVersion)"
echo -e "${GREEN}Minikube:${NC} $(minikube version)"

echo -e "\n${YELLOW}Para iniciar o cluster Minikube:${NC}"
echo -e "minikube start --driver=docker"
echo -e "\n${YELLOW}Para verificar o status:${NC}"
echo -e "minikube status"
echo -e "\n${YELLOW}Para acessar o dashboard:${NC}"
echo -e "minikube dashboard"
