#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        INSTALAÇÃO DE DEPENDÊNCIAS PARA SISTEMA PAXOS            ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Verificar permissões de sudo
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}Este script precisa ser executado com permissões de superusuário.${NC}"
    echo -e "${YELLOW}Solicitando senha sudo...${NC}"
    if ! sudo -v; then
        echo -e "${RED}Falha ao obter permissões de sudo. Execute o script como superusuário ou use sudo.${NC}"
        exit 1
    fi
fi

# Função para verificar se um comando está instalado
command_exists() {
    command -v "$1" &> /dev/null
}

# Função para instalar um pacote
install_package() {
    local package=$1
    echo -e "${YELLOW}Instalando $package...${NC}"
    sudo apt-get install -y $package
    if command_exists $package; then
        echo -e "${GREEN}$package instalado com sucesso!${NC}"
    else
        echo -e "${RED}Falha ao instalar $package. Verifique os logs acima.${NC}"
    fi
}

# Atualizar lista de pacotes
echo -e "${YELLOW}Atualizando lista de pacotes...${NC}"
sudo apt-get update

# Instalar dependências essenciais
echo -e "\n${YELLOW}Instalando dependências essenciais...${NC}"
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2

# Instalar ferramentas de processamento
echo -e "\n${YELLOW}Instalando ferramentas de processamento (jq, curl)...${NC}"
install_package "jq"
install_package "curl"

# Instalar utilitários de rede
echo -e "\n${YELLOW}Instalando utilitários de rede...${NC}"
install_package "net-tools"
install_package "dnsutils"
install_package "iputils-ping"
install_package "socat"  # Necessário para port-forward

# Instalar Python e pacotes necessários
echo -e "\n${YELLOW}Instalando Python e pacotes necessários...${NC}"
install_package "python3"
install_package "python3-pip"

echo -e "${YELLOW}Instalando pacotes Python para o sistema Paxos...${NC}"
pip3 install requests flask werkzeug --user

# Resumo de instalação
echo -e "\n${BLUE}═════════════════════ RESUMO DE INSTALAÇÃO ═════════════════════${NC}"
echo -e "Ferramentas de processamento: ${command_exists jq && echo "${GREEN}jq ✓${NC}" || echo "${RED}jq ✗${NC}"}, ${command_exists curl && echo "${GREEN}curl ✓${NC}" || echo "${RED}curl ✗${NC}"}"
echo -e "Utilitários de rede: ${command_exists ping && echo "${GREEN}ping ✓${NC}" || echo "${RED}ping ✗${NC}"}, ${command_exists netstat && echo "${GREEN}net-tools ✓${NC}" || echo "${RED}net-tools ✗${NC}"}, ${command_exists nslookup && echo "${GREEN}dnsutils ✓${NC}" || echo "${RED}dnsutils ✗${NC}"}, ${command_exists socat && echo "${GREEN}socat ✓${NC}" || echo "${RED}socat ✗${NC}"}"
echo -e "Programação: ${command_exists python3 && echo "${GREEN}python3 ✓${NC}" || echo "${RED}python3 ✗${NC}"}, ${command_exists pip3 && echo "${GREEN}pip3 ✓${NC}" || echo "${RED}pip3 ✗${NC}"}"

# Próximos passos
echo -e "\n${BLUE}════════════════════════ PRÓXIMOS PASSOS ════════════════════════${NC}"
echo -e "1. Execute o script para configurar o ambiente Kubernetes no WSL:"
echo -e "   ${CYAN}./setup-kubernetes-wsl.sh${NC}"
echo -e "2. Após configurar o Kubernetes, implante o sistema Paxos:"
echo -e "   ${CYAN}./deploy-paxos-k8s.sh${NC}"

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Instalação de dependências básicas concluída!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
