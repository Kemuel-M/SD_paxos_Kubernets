#!/bin/bash

# Cores para saída
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              SISTEMA PAXOS - INICIALIZAÇÃO DA REDE              ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Verificar se kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERRO] kubectl não encontrado. Por favor, instale o kubectl antes de continuar.${NC}"
    exit 1
fi

# Verificar se o namespace paxos existe
if ! kubectl get namespace paxos &> /dev/null; then
    echo -e "${RED}[ERRO] Namespace 'paxos' não encontrado. Execute ./deploy-paxos-k8s.sh primeiro.${NC}"
    exit 1
fi

# Verificar se todos os pods estão em execução
echo -e "\n${YELLOW}Verificando status dos pods...${NC}"
PODS_READY=$(kubectl get pods -n paxos -o jsonpath='{.items[*].status.containerStatuses[0].ready}' | tr ' ' '\n' | grep -c "true")
PODS_TOTAL=$(kubectl get pods -n paxos -o jsonpath='{.items[*].status.containerStatuses[0].ready}' | tr ' ' '\n' | wc -l)

if [ "$PODS_READY" -ne "$PODS_TOTAL" ]; then
    echo -e "${YELLOW}Alguns pods ainda não estão prontos ($PODS_READY/$PODS_TOTAL)${NC}"
    echo -e "${YELLOW}Aguardando inicialização de todos os pods...${NC}"
    
    # Esperar até que todos os pods estejam prontos (com timeout)
    timeout=120 # segundos
    elapsed=0
    spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    spin_idx=0
    
    while [ "$PODS_READY" -ne "$PODS_TOTAL" ] && [ "$elapsed" -lt "$timeout" ]; do
        spin_char="${spinner[spin_idx]}"
        echo -ne "${YELLOW}${spin_char} Aguardando pods... ${elapsed}s/${timeout}s${NC}\r"
        
        spin_idx=$(( (spin_idx + 1) % ${#spinner[@]} ))
        sleep 1
        elapsed=$((elapsed + 1))
        
        PODS_READY=$(kubectl get pods -n paxos -o jsonpath='{.items[*].status.containerStatuses[0].ready}' | tr ' ' '\n' | grep -c "true")
        PODS_TOTAL=$(kubectl get pods -n paxos -o jsonpath='{.items[*].status.containerStatuses[0].ready}' | tr ' ' '\n' | wc -l)
    done
    
    if [ "$PODS_READY" -ne "$PODS_TOTAL" ]; then
        echo -e "\n${RED}[AVISO] Nem todos os pods estão prontos após o timeout.${NC}"
        echo -e "${YELLOW}Continuando, mas podem ocorrer problemas...${NC}"
    else
        echo -e "\n${GREEN}Todos os pods estão prontos!${NC}"
    fi
else
    echo -e "${GREEN}Todos os pods estão prontos ($PODS_READY/$PODS_TOTAL)${NC}"
fi

# Função para verificar a saúde de um serviço
check_service_health() {
    local service=$1
    local namespace=$2
    local result
    
    # Obter o pod correspondente ao serviço
    local pod=$(kubectl get pods -n $namespace -l app=$service -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ -z "$pod" ]; then
        echo "${RED}Offline${NC} (pod não encontrado)"
        return 1
    fi
    
    # Verificar a saúde do serviço usando o endpoint health
    result=$(kubectl exec -n $namespace $pod -- curl -s http://localhost:8000/health 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "${GREEN}Online${NC}"
        return 0
    else
        echo "${RED}Offline${NC}"
        return 1
    fi
}

# Verificar a saúde de todos os serviços
echo -e "\n${BLUE}════════════════════ VERIFICAÇÃO DE SAÚDE ════════════════════${NC}"
printf "${CYAN}%-15s %-15s${NC}\n" "SERVIÇO" "STATUS"
echo -e "${CYAN}───────────────────────────────────────${NC}"

# Verificar proposers
for i in {1..3}; do
    status=$(check_service_health "proposer$i" "paxos")
    printf "%-15s %-15b\n" "Proposer $i" "$status"
done

# Verificar acceptors
for i in {1..3}; do
    status=$(check_service_health "acceptor$i" "paxos")
    printf "%-15s %-15b\n" "Acceptor $i" "$status"
done

# Verificar learners
for i in {1..2}; do
    status=$(check_service_health "learner$i" "paxos")
    printf "%-15s %-15b\n" "Learner $i" "$status"
done

# Verificar clients
for i in {1..2}; do
    status=$(check_service_health "client$i" "paxos")
    printf "%-15s %-15b\n" "Client $i" "$status"
done

# Inicialização do sistema Paxos
echo -e "\n${YELLOW}Iniciando sistema Paxos...${NC}"

# Função para executar comando em um pod
exec_in_pod() {
    local service=$1
    local namespace=$2
    local command=$3
    
    # Obter o pod correspondente ao serviço
    local pod=$(kubectl get pods -n $namespace -l app=$service -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ -z "$pod" ]; then
        echo "${RED}[ERRO] Pod para $service não encontrado${NC}"
        return 1
    fi
    
    # Executar o comando no pod
    kubectl exec -n $namespace $pod -- bash -c "$command" 2>/dev/null
    return $?
}

# Verificar se há um líder eleito e iniciar eleição se necessário
echo -e "${YELLOW}Verificando eleição de líder...${NC}"
LEADER_ID=$(exec_in_pod "proposer1" "paxos" "curl -s http://localhost:3001/view-logs | python3 -c \"import sys, json; print(json.load(sys.stdin).get('current_leader', 'None'))\"")

if [ "$LEADER_ID" == "None" ] || [ -z "$LEADER_ID" ]; then
    echo -e "${YELLOW}Nenhum líder eleito. Forçando eleição...${NC}"
    
    # Iterar sobre todos os proposers e tentar forçar uma eleição
    for i in {1..3}; do
        echo -e "${YELLOW}Tentando iniciar eleição via Proposer $i...${NC}"
        
        # Enviar uma solicitação direta para forçar eleição
        exec_in_pod "proposer$i" "paxos" "curl -s -X POST http://localhost:300$i/propose -H 'Content-Type: application/json' -d '{\"value\":\"trigger_election\", \"client_id\":9}'" > /dev/null
        
        # Aguardar um pouco para a eleição ocorrer
        sleep 5
        
        # Verificar se a eleição ocorreu
        LEADER_ID=$(exec_in_pod "proposer1" "paxos" "curl -s http://localhost:3001/view-logs | python3 -c \"import sys, json; print(json.load(sys.stdin).get('current_leader', 'None'))\"")
        
        if [ "$LEADER_ID" != "None" ] && [ -n "$LEADER_ID" ]; then
            echo -e "${GREEN}Líder eleito: Proposer $LEADER_ID${NC}"
            break
        fi
    done
    
    # Verificar novamente se há um líder
    if [ "$LEADER_ID" == "None" ] || [ -z "$LEADER_ID" ]; then
        echo -e "${RED}[AVISO] Não foi possível eleger um líder. O sistema pode não funcionar corretamente.${NC}"
    fi
else
    echo -e "${GREEN}Líder atual: Proposer $LEADER_ID${NC}"
fi

# Obter URLs de acesso
CLIENT_URL=$(minikube service client1-external -n paxos --url | head -n1 2>/dev/null || echo "URL não disponível")
PROPOSER_URL=$(minikube service proposer1-external -n paxos --url | head -n1 2>/dev/null || echo "URL não disponível")

echo -e "\n${GREEN}Sistema Paxos inicializado com sucesso!${NC}"
echo -e "${YELLOW}Para interagir com o sistema, use:${NC}"
echo -e "  ${GREEN}./paxos-client.sh${NC} - Para enviar comandos como cliente"
echo -e "  ${GREEN}./monitor.sh${NC} - Para monitorar o sistema em tempo real"

echo -e "\n${BLUE}═════════════════════ ACESSOS AO SISTEMA ═════════════════════${NC}"
echo -e "${YELLOW}Cliente:${NC} $CLIENT_URL"
echo -e "${YELLOW}Proposer:${NC} $PROPOSER_URL"
echo -e "${YELLOW}Ou use:${NC} minikube service client1-external -n paxos"

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Para parar o sistema: ${RED}./cleanup-paxos-k8s.sh${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"