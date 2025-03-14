#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              PREPARAÇÃO DE AMBIENTE KUBERNETES NO WSL           ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}Verificando sistema operacional...${NC}"
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[ERRO] Arquivo /etc/os-release não encontrado. Este script é compatível apenas com WSL Ubuntu.${NC}"
    exit 1
fi

source /etc/os-release
if [[ "$NAME" != *"Ubuntu"* ]]; then
    echo -e "${RED}[ERRO] Este script foi projetado para Ubuntu no WSL. Sistema detectado: $NAME${NC}"
    exit 1
fi

echo -e "${GREEN}Sistema operacional: $NAME $VERSION_ID${NC}"

# Atualizar pacotes
echo -e "\n${YELLOW}Atualizando pacotes...${NC}"
sudo apt-get update -qq || {
    echo -e "${RED}[ERRO] Falha ao atualizar pacotes. Verifique sua conexão com a internet.${NC}"
    exit 1
}

echo -e "\n${YELLOW}Instalando dependências essenciais...${NC}"
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2 || {
    echo -e "${RED}[ERRO] Falha ao instalar dependências.${NC}"
    exit 1
}

# Instalar Docker se não estiver instalado
if ! command -v docker &> /dev/null; then
    echo -e "\n${YELLOW}Instalando Docker...${NC}"
    
    # Remover versões antigas (se existirem)
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
    
    # Adicionar repositório Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    
    # Instalar Docker
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Configurar Docker para ser usado sem sudo
    sudo groupadd docker 2>/dev/null || true
    sudo usermod -aG docker $USER
    
    echo -e "${GREEN}Docker instalado com sucesso!${NC}"
    echo -e "${YELLOW}Para usar Docker sem sudo, você precisará reiniciar o WSL.${NC}"
    echo -e "${YELLOW}Após concluir este script, execute 'wsl --shutdown' no PowerShell e reabra o terminal WSL.${NC}"
else
    echo -e "${GREEN}Docker já está instalado: $(docker --version)${NC}"
    
    # Verificar se o usuário está no grupo docker
    if ! groups | grep -q docker; then
        echo -e "${YELLOW}Adicionando usuário ao grupo docker...${NC}"
        sudo groupadd docker 2>/dev/null || true
        sudo usermod -aG docker $USER
        echo -e "${YELLOW}Para aplicar as alterações, você precisará reiniciar o WSL.${NC}"
    fi
fi

# Iniciar serviço Docker
echo -e "\n${YELLOW}Iniciando serviço Docker...${NC}"
if ! sudo service docker status >/dev/null 2>&1; then
    sudo service docker start || {
        echo -e "${RED}[AVISO] Não foi possível iniciar o serviço Docker.${NC}"
        echo -e "${YELLOW}Após concluir este script, reinicie o WSL e execute: sudo service docker start${NC}"
    }
fi

# Instalar kubectl usando download direto (sem repositório)
if ! command -v kubectl &> /dev/null; then
    echo -e "\n${YELLOW}Instalando kubectl via download direto...${NC}"
    
    # Baixar a versão mais recente do kubectl
    echo -e "${YELLOW}Baixando kubectl...${NC}"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    
    # Tornar o arquivo executável
    chmod +x kubectl
    
    # Mover para o diretório bin
    echo -e "${YELLOW}Instalando kubectl em /usr/local/bin...${NC}"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Limpar arquivo baixado
    rm kubectl
    
    echo -e "${GREEN}kubectl instalado com sucesso!${NC}"
else
    echo -e "${GREEN}kubectl já está instalado: $(kubectl version --client --short 2>/dev/null || echo 'versão não disponível')${NC}"
fi

# Instalar Minikube
if ! command -v minikube &> /dev/null; then
    echo -e "\n${YELLOW}Instalando Minikube...${NC}"
    
    # Baixar e instalar Minikube
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
    
    echo -e "${GREEN}Minikube instalado com sucesso!${NC}"
else
    echo -e "${GREEN}Minikube já está instalado: $(minikube version --short 2>/dev/null || echo 'versão não disponível')${NC}"
fi

# Verificar e instalar socat (necessário para serviços NodePort no WSL)
if ! command -v socat &> /dev/null; then
    echo -e "\n${YELLOW}Instalando socat (necessário para encaminhamento de portas)...${NC}"
    sudo apt-get install -y socat
    echo -e "${GREEN}socat instalado com sucesso!${NC}"
else
    echo -e "${GREEN}socat já está instalado.${NC}"
fi

# Instalar Python3 e pip (necessário para os scripts)
if ! command -v python3 &> /dev/null; then
    echo -e "\n${YELLOW}Instalando Python3 e pip...${NC}"
    sudo apt-get install -y python3 python3-pip
    echo -e "${GREEN}Python3 instalado com sucesso!${NC}"
else
    echo -e "${GREEN}Python3 já está instalado: $(python3 --version)${NC}"
fi

# Testar Docker
echo -e "\n${YELLOW}Testando Docker...${NC}"
if docker run --rm hello-world &>/dev/null; then
    echo -e "${GREEN}Docker está funcionando corretamente!${NC}"
else
    echo -e "${RED}[AVISO] Teste do Docker falhou. Verifique se o serviço está em execução.${NC}"
    echo -e "${YELLOW}Execute 'sudo service docker start' após reiniciar o WSL.${NC}"
fi

echo -e "\n${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Ambiente Kubernetes preparado com sucesso!${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}Próximos passos:${NC}"
echo -e "1. Reinicie o WSL para aplicar todas as alterações:"
echo -e "   - No PowerShell do Windows, execute: ${CYAN}wsl --shutdown${NC}"
echo -e "   - Reabra seu terminal WSL"
echo -e ""
echo -e "2. Inicie o cluster Minikube:"
echo -e "   ${CYAN}minikube start --driver=docker${NC}"
echo -e ""
echo -e "3. Verifique o status do cluster:"
echo -e "   ${CYAN}minikube status${NC}"
echo -e ""
echo -e "4. Implante o sistema Paxos:"
echo -e "   ${CYAN}./deploy-paxos-k8s.sh${NC}"
echo -e ""
echo -e "5. Inicie o sistema Paxos:"
echo -e "   ${CYAN}./run.sh${NC}"
echo -e ""
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"