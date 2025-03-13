#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Parâmetro para escolher o cliente (padrão: client1)
CLIENT=${CLIENT:-"client1"}
CLIENT_ID=${CLIENT_ID:-"9"}  # client1=9, client2=10

# Função para enviar um valor para o sistema
write_value() {
    local value="$1"
    echo -e "${YELLOW}Enviando valor '$value' para o sistema Paxos usando $CLIENT...${NC}"
    
    # Obter o pod do cliente
    local client_pod=$(kubectl get pods -n paxos -l app=$CLIENT -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$client_pod" ]; then
        echo -e "${RED}Cliente $CLIENT não encontrado! Verifique se o sistema está em execução.${NC}"
        exit 1
    fi
    
    # Obter a porta do cliente (assume 6001 para client1, 6002 para client2, etc.)
    local client_port="600${CLIENT: -1}"
    
    # Enviar valor usando curl dentro do pod do cliente
    kubectl exec -n paxos "$client_pod" -- bash -c "curl -s -X POST http://$CLIENT:$client_port/send -H 'Content-Type: application/json' -d '{\"value\":\"$value\"}'"
    echo ""  # Nova linha após a resposta
    
    echo -e "${GREEN}Valor enviado através do $CLIENT. Use './paxos-client.sh read' para verificar se foi processado.${NC}"
}

# Função para ler valores do sistema
read_values() {
    echo -e "${YELLOW}Lendo valores do sistema Paxos usando $CLIENT...${NC}"
    
    # Obter o pod do cliente
    local client_pod=$(kubectl get pods -n paxos -l app=$CLIENT -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$client_pod" ]; then
        echo -e "${RED}Cliente $CLIENT não encontrado! Verifique se o sistema está em execução.${NC}"
        exit 1
    fi
    
    # Obter a porta do cliente (assume 6001 para client1, 6002 para client2, etc.)
    local client_port="600${CLIENT: -1}"
    
    # Ler valores usando curl dentro do pod do cliente
    echo -e "${GREEN}Valores:${NC}"
    kubectl exec -n paxos "$client_pod" -- bash -c "curl -s http://$CLIENT:$client_port/read"
    echo ""  # Nova linha após a resposta
}

# Função para ver as respostas recebidas pelo cliente
get_responses() {
    echo -e "${YELLOW}Obtendo respostas do $CLIENT...${NC}"
    
    # Obter o pod do cliente
    local client_pod=$(kubectl get pods -n paxos -l app=$CLIENT -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$client_pod" ]; then
        echo -e "${RED}Cliente $CLIENT não encontrado! Verifique se o sistema está em execução.${NC}"
        exit 1
    fi
    
    # Obter a porta do cliente (assume 6001 para client1, 6002 para client2, etc.)
    local client_port="600${CLIENT: -1}"
    
    # Obter respostas usando curl dentro do pod do cliente
    echo -e "${GREEN}Respostas:${NC}"
    kubectl exec -n paxos "$client_pod" -- bash -c "curl -s http://$CLIENT:$client_port/get-responses"
    echo ""  # Nova linha após a resposta
}

# Função para enviar um valor diretamente para o proposer (contornando o cliente)
direct_write() {
    local value="$1"
    local proposer=${PROPOSER:-"proposer1"}
    echo -e "${YELLOW}Enviando valor '$value' diretamente para o $proposer...${NC}"
    
    # Obter o pod do proposer
    local proposer_pod=$(kubectl get pods -n paxos -l app=$proposer -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$proposer_pod" ]; then
        echo -e "${RED}Proposer $proposer não encontrado! Verifique se o sistema está em execução.${NC}"
        exit 1
    fi
    
    # Obter a porta do proposer (assume 3001 para proposer1, 3002 para proposer2, etc.)
    local proposer_port="300${proposer: -1}"
    
    # Enviar valor diretamente usando curl dentro do pod do proposer
    kubectl exec -n paxos "$proposer_pod" -- bash -c "curl -s -X POST http://$proposer:$proposer_port/propose -H 'Content-Type: application/json' -d '{\"value\":\"$value\", \"client_id\":$CLIENT_ID}'"
    echo ""  # Nova linha após a resposta
    
    echo -e "${GREEN}Valor enviado diretamente ao $proposer. Use './paxos-client.sh read' para verificar se foi processado.${NC}"
    echo -e "${YELLOW}Nota: Esta operação contorna o cliente e envia diretamente para o proposer.${NC}"
}

# Função para ver o status do sistema
get_status() {
    echo -e "${YELLOW}Verificando status do sistema Paxos...${NC}"
    
    # Verificar pods em execução
    echo -e "${GREEN}Pods em execução:${NC}"
    kubectl get pods -n paxos
    
    # Obter status do proposer1
    local proposer_pod=$(kubectl get pods -n paxos -l app=proposer1 -o jsonpath="{.items[0].metadata.name}")
    
    if [ ! -z "$proposer_pod" ]; then
        echo -e "\n${GREEN}Status do Proposer 1:${NC}"
        kubectl exec -n paxos "$proposer_pod" -- bash -c "curl -s http://proposer1:3001/view-logs"
        echo ""  # Nova linha após a resposta
    fi
    
    # Obter status do cliente1
    local client_pod=$(kubectl get pods -n paxos -l app=client1 -o jsonpath="{.items[0].metadata.name}")
    
    if [ ! -z "$client_pod" ]; then
        echo -e "\n${GREEN}Status do Cliente 1:${NC}"
        kubectl exec -n paxos "$client_pod" -- bash -c "curl -s http://client1:6001/view-logs"
        echo ""  # Nova linha após a resposta
    fi
}

# Função para abrir o acesso externo no navegador
open_ui() {
    echo -e "${YELLOW}Abrindo URL de acesso ao $CLIENT no navegador...${NC}"
    
    # Verificar se existe um serviço externo para o cliente selecionado
    local service_exists=$(kubectl get service -n paxos "${CLIENT}-external" 2>/dev/null)
    
    if [ -z "$service_exists" ]; then
        echo -e "${RED}Serviço externo para $CLIENT não encontrado. Usando client1-external.${NC}"
        minikube service client1-external -n paxos
    else
        minikube service "${CLIENT}-external" -n paxos
    fi
}

# Função para mostrar a ajuda
show_help() {
    echo "Uso: $0 <comando> [argumentos]"
    echo "Comandos disponíveis:"
    echo "  write <valor>     - Enviar um valor para o sistema"
    echo "  direct-write <valor> - Enviar um valor diretamente para o proposer (bypass cliente)"
    echo "  read              - Ler valores do sistema"
    echo "  responses         - Ver respostas recebidas pelo cliente"
    echo "  status            - Ver status do sistema"
    echo "  open              - Abrir o acesso ao cliente no navegador"
    echo "  help              - Exibir esta ajuda"
    echo ""
    echo "Variáveis de ambiente para escolher o cliente/proposer:"
    echo "  CLIENT=client1|client2   - Escolhe qual cliente usar (padrão: client1)"
    echo "  CLIENT_ID=9|10           - ID do cliente (9=client1, 10=client2)"
    echo "  PROPOSER=proposer1|proposer2|proposer3 - Escolhe qual proposer usar no direct-write (padrão: proposer1)"
    echo ""
    echo "Exemplos:"
    echo "  ./paxos-client.sh write \"novo valor\""
    echo "  CLIENT=client2 ./paxos-client.sh read"
    echo "  PROPOSER=proposer2 ./paxos-client.sh direct-write \"valor direto\""
}

# Verificar se o comando foi fornecido
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

# Processar o comando
command="$1"
case "$command" in
    write)
        if [ $# -lt 2 ]; then
            echo -e "${RED}Erro: O comando 'write' requer um valor.${NC}"
            show_help
            exit 1
        fi
        write_value "$2"
        ;;
    direct-write)
        if [ $# -lt 2 ]; then
            echo -e "${RED}Erro: O comando 'direct-write' requer um valor.${NC}"
            show_help
            exit 1
        fi
        direct_write "$2"
        ;;
    read)
        read_values
        ;;
    responses)
        get_responses
        ;;
    status)
        get_status
        ;;
    open)
        open_ui
        ;;
    help)
        show_help
        ;;
    *)
        echo -e "${RED}Comando desconhecido: $command${NC}"
        show_help
        exit 1
        ;;
esac