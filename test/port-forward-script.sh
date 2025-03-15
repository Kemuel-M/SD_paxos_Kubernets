#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Funções para port-forwarding
declare -A PIDS

# Função para iniciar port-forward para um serviço
start_port_forward() {
    local component=$1
    local port=$2
    local local_port=$3
    
    if [ -z "$local_port" ]; then
        local_port=$port
    fi
    
    local pod=$(kubectl get pods -n paxos -l app=$component -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ -z "$pod" ]; then
        echo -e "${RED}Pod para $component não encontrado${NC}"
        return 1
    fi
    
    # Verificar se já existe um port-forward para este serviço
    if [ ! -z "${PIDS[$component]}" ]; then
        local pid=${PIDS[$component]}
        if ps -p $pid > /dev/null; then
            echo -e "${YELLOW}Port-forward para $component já está ativo (PID: $pid)${NC}"
            return 0
        fi
    fi
    
    echo -e "${GREEN}Iniciando port-forward para $component: localhost:$local_port -> $pod:$port${NC}"
    kubectl port-forward -n paxos $pod $local_port:$port > /dev/null 2>&1 &
    PIDS[$component]=$!
    
    # Verificar se o port-forward foi iniciado com sucesso
    sleep 2
    if ! ps -p ${PIDS[$component]} > /dev/null; then
        echo -e "${RED}Falha ao iniciar port-forward para $component${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Port-forward para $component iniciado com sucesso (PID: ${PIDS[$component]})${NC}"
    return 0
}

# Função para parar port-forward para um serviço
stop_port_forward() {
    local component=$1
    
    if [ ! -z "${PIDS[$component]}" ]; then
        local pid=${PIDS[$component]}
        if ps -p $pid > /dev/null; then
            echo -e "${YELLOW}Parando port-forward para $component (PID: $pid)...${NC}"
            kill $pid
            unset PIDS[$component]
            return 0
        else
            echo -e "${YELLOW}Port-forward para $component não está mais ativo${NC}"
            unset PIDS[$component]
            return 1
        fi
    else
        echo -e "${YELLOW}Nenhum port-forward ativo para $component${NC}"
        return 1
    fi
}

# Função para parar todos os port-forwards
stop_all_port_forwards() {
    echo -e "${YELLOW}Parando todos os port-forwards...${NC}"
    for component in "${!PIDS[@]}"; do
        stop_port_forward $component
    done
}

# Função para listar port-forwards ativos
list_port_forwards() {
    echo -e "${BLUE}Port-forwards ativos:${NC}"
    
    if [ ${#PIDS[@]} -eq 0 ]; then
        echo -e "${YELLOW}Nenhum port-forward ativo${NC}"
        return
    fi
    
    for component in "${!PIDS[@]}"; do
        local pid=${PIDS[$component]}
        if ps -p $pid > /dev/null; then
            echo -e "${GREEN}$component (PID: $pid) - ATIVO${NC}"
        else
            echo -e "${RED}$component (PID: $pid) - INATIVO${NC}"
            unset PIDS[$component]
        fi
    done
}

# Configura para limpar port-forwards na saída
trap stop_all_port_forwards EXIT

# Menu principal
show_menu() {
    clear
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}              SISTEMA PAXOS - GERENCIADOR DE ACESSOS             ${NC}"
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Status atual:${NC}"
    list_port_forwards
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    echo -e "1) Iniciar port-forward para Proposer1 (3001)"
    echo -e "2) Iniciar port-forward para Proposer2 (3002)"
    echo -e "3) Iniciar port-forward para Proposer3 (3003)"
    echo -e "4) Iniciar port-forward para Client1 (6001)"
    echo -e "5) Iniciar port-forward para Client2 (6002)"
    echo -e "6) Iniciar port-forward para Learner1 (5001)"
    echo -e "7) Iniciar port-forward para todos os componentes principais"
    echo -e "8) Forçar eleição de líder"
    echo -e "9) Listar port-forwards ativos"
    echo -e "0) Parar todos os port-forwards e sair"
    echo -e "q) Sair (mantém port-forwards ativos)"
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Escolha uma opção:${NC}"
}

# Função para forçar eleição de líder
force_leader_election() {
    echo -e "${YELLOW}Forçando eleição de líder...${NC}"
    
    # Verificar se há port-forward para proposer1
    if [ -z "${PIDS[proposer1]}" ] || ! ps -p ${PIDS[proposer1]} > /dev/null; then
        echo -e "${YELLOW}Iniciando port-forward para proposer1...${NC}"
        start_port_forward "proposer1" "3001"
    fi
    
    # Enviar proposta para iniciar eleição
    echo -e "${YELLOW}Enviando proposta para iniciar eleição...${NC}"
    curl -s -X POST http://localhost:3001/propose -H 'Content-Type: application/json' -d '{"value":"force_election","client_id":9}'
    
    # Aguardar eleição
    echo -e "${YELLOW}Aguardando 5 segundos para eleição de líder...${NC}"
    sleep 5
    
    # Verificar se há um líder eleito
    leader_info=$(curl -s http://localhost:3001/view-logs)
    current_leader=$(echo $leader_info | grep -o '"current_leader":[^,}]*' | cut -d':' -f2 | tr -d '"' 2>/dev/null)
    
    if [ -z "$current_leader" ] || [ "$current_leader" = "null" ]; then
        echo -e "${RED}[AVISO] Não foi possível eleger um líder usando proposer1.${NC}"
        
        # Tentar com proposer2
        if [ -z "${PIDS[proposer2]}" ] || ! ps -p ${PIDS[proposer2]} > /dev/null; then
            echo -e "${YELLOW}Iniciando port-forward para proposer2...${NC}"
            start_port_forward "proposer2" "3002"
        fi
        
        echo -e "${YELLOW}Tentando com proposer2...${NC}"
        curl -s -X POST http://localhost:3002/propose -H 'Content-Type: application/json' -d '{"value":"force_election2","client_id":9}'
        
        sleep 5
        leader_info=$(curl -s http://localhost:3002/view-logs)
        current_leader=$(echo $leader_info | grep -o '"current_leader":[^,}]*' | cut -d':' -f2 | tr -d '"' 2>/dev/null)
        
        if [ -z "$current_leader" ] || [ "$current_leader" = "null" ]; then
            echo -e "${RED}[AVISO] Ainda não foi possível eleger um líder.${NC}"
        else
            echo -e "${GREEN}Líder eleito: Proposer $current_leader${NC}"
        fi
    else
        echo -e "${GREEN}Líder eleito: Proposer $current_leader${NC}"
    fi
    
    echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
    read
}

# Função para iniciar todos os port-forwards importantes
start_all_port_forwards() {
    echo -e "${YELLOW}Iniciando port-forwards para todos os componentes principais...${NC}"
    
    # Iniciar para proposers
    start_port_forward "proposer1" "3001"
    start_port_forward "proposer2" "3002"
    start_port_forward "proposer3" "3003"
    
    # Iniciar para client1
    start_port_forward "client1" "6001"
    
    # Iniciar para learner1
    start_port_forward "learner1" "5001"
    
    echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
    read
}

# Loop principal
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            start_port_forward "proposer1" "3001"
            echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
            read
            ;;
        2)
            start_port_forward "proposer2" "3002"
            echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
            read
            ;;
        3)
            start_port_forward "proposer3" "3003"
            echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
            read
            ;;
        4)
            start_port_forward "client1" "6001"
            echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
            read
            ;;
        5)
            start_port_forward "client2" "6002"
            echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
            read
            ;;
        6)
            start_port_forward "learner1" "5001"
            echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
            read
            ;;
        7)
            start_all_port_forwards
            ;;
        8)
            force_leader_election
            ;;
        9)
            list_port_forwards
            echo -e "${YELLOW}Pressione ENTER para continuar...${NC}"
            read
            ;;
        0)
            stop_all_port_forwards
            echo -e "${GREEN}Todos os port-forwards foram encerrados. Saindo...${NC}"
            exit 0
            ;;
        q|Q)
            echo -e "${YELLOW}Saindo sem parar port-forwards ativos...${NC}"
            # Desativar o trap
            trap - EXIT
            exit 0
            ;;
        *)
            echo -e "${RED}Opção inválida!${NC}"
            sleep 1
            ;;
    esac
done
