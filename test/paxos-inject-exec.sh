#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

NAMESPACE="paxos"

clear
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              SISTEMA PAXOS - DIAGNÓSTICO AVANÇADO               ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Verificar se kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERRO] kubectl não encontrado. Por favor, instale o kubectl antes de continuar.${NC}"
    exit 1
fi

# Função para exibir logs de um pod
show_pod_logs() {
    local pod_name=$1
    
    echo -e "${YELLOW}Logs do pod $pod_name:${NC}"
    kubectl logs -n $NAMESPACE $pod_name | tail -n 20
    echo ""
}

# Função para descrever um pod
describe_pod() {
    local pod_name=$1
    
    echo -e "${YELLOW}Descrição do pod $pod_name:${NC}"
    kubectl describe pod -n $NAMESPACE $pod_name
    echo ""
}

# Verificar pods em estado de erro
echo -e "\n${YELLOW}Verificando pods com erros...${NC}"
error_pods=$(kubectl get pods -n $NAMESPACE | grep -E "Error|CrashLoopBackOff" | awk '{print $1}')

if [ ! -z "$error_pods" ]; then
    echo -e "${RED}Pods com erros encontrados:${NC}"
    for pod in $error_pods; do
        echo -e "${RED}$pod${NC}"
        show_pod_logs $pod
        describe_pod $pod
    done
else
    echo -e "${GREEN}Nenhum pod com erro encontrado.${NC}"
fi

# Exibir configuração de rede do cluster
echo -e "\n${YELLOW}Verificando configuração de rede do cluster...${NC}"
echo -e "${CYAN}Services:${NC}"
kubectl get svc -n $NAMESPACE

echo -e "\n${CYAN}Endpoints:${NC}"
kubectl get endpoints -n $NAMESPACE

echo -e "\n${CYAN}Testando conectividade interna...${NC}"
# Criar pod temporário para teste de rede
kubectl run net-test --namespace=$NAMESPACE --rm -i --restart=Never --image=busybox:1.28 -- sh -c "
ping -c 2 kubernetes.default.svc.cluster.local
echo '---'
nslookup proposer1.paxos.svc.cluster.local
echo '---'
nslookup proposer2.paxos.svc.cluster.local
echo '---'
nslookup acceptor1.paxos.svc.cluster.local
" || echo -e "${RED}Falha ao executar testes de rede${NC}"

# Verificar logs relevantes dos proposers
echo -e "\n${YELLOW}Verificando logs dos proposers...${NC}"
proposer1_pod=$(kubectl get pods -n $NAMESPACE -l app=proposer1 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ ! -z "$proposer1_pod" ]; then
    show_pod_logs $proposer1_pod
fi

proposer2_pod=$(kubectl get pods -n $NAMESPACE -l app=proposer2 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ ! -z "$proposer2_pod" ]; then
    show_pod_logs $proposer2_pod
fi

proposer3_pod=$(kubectl get pods -n $NAMESPACE -l app=proposer3 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ ! -z "$proposer3_pod" ]; then
    show_pod_logs $proposer3_pod
fi

# Configurar envio direto de valor para Proposers via kubectl exec + python
echo -e "\n${YELLOW}Tentando eleição de líder via Python diretamente...${NC}"

if [ ! -z "$proposer1_pod" ]; then
    echo -e "${CYAN}Injetando script Python no proposer1...${NC}"
    kubectl exec -n $NAMESPACE $proposer1_pod -- python -c '
import json
import requests

try:
    # Forçar eleição diretamente usando a API Python
    print("Tentando iniciar eleição via proposer1 (localhost)...")
    response = requests.post("http://localhost:3001/propose",
                           headers={"Content-Type": "application/json"},
                           json={"value": "force_election_python", "client_id": 9},
                           timeout=5)
    print(f"Resposta: {response.status_code} - {response.text}")
    
    # Verificar status do proposer
    view_logs = requests.get("http://localhost:3001/view-logs", timeout=5)
    print(f"Status do proposer: {view_logs.text}")
    
    # Tentar iniciar eleição diretamente
    print("\nTentando forçar método interno de eleição...")
    print("AVISO: Isso é um hack e pode não funcionar em todos os casos")
    
    # Código Python para simular comandos internos (hack)
    import time
    import threading
    
    # Simular o início de uma eleição diretamente (isso é apenas uma aproximação!)
    try:
        # Tentar iniciar via proposer2
        print("\nTentando via proposer2...")
        response = requests.post("http://proposer2.paxos.svc.cluster.local:3002/propose",
                           headers={"Content-Type": "application/json"},
                           json={"value": "force_election_via_p2", "client_id": 9},
                           timeout=5)
        print(f"Resposta proposer2: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Erro ao tentar via proposer2: {e}")
        
    try:
        # Tentar iniciar via proposer3
        print("\nTentando via proposer3...")
        response = requests.post("http://proposer3.paxos.svc.cluster.local:3003/propose",
                           headers={"Content-Type": "application/json"},
                           json={"value": "force_election_via_p3", "client_id": 9},
                           timeout=5)
        print(f"Resposta proposer3: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Erro ao tentar via proposer3: {e}")
    
except Exception as e:
    print(f"Erro: {e}")
'
fi

# Verificar estado final
echo -e "\n${YELLOW}Estado final dos pods:${NC}"
kubectl get pods -n $NAMESPACE

echo -e "\n${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Diagnóstico avançado concluído. Verifique as mensagens acima para entender o problema.${NC}"
echo -e "${YELLOW}Executando ./run.sh novamente para tentar inicializar o sistema...${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Executar run.sh novamente
echo -e "${YELLOW}Executando ./run.sh...${NC}"
#./run.sh
