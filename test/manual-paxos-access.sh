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
echo -e "${BLUE}              SISTEMA PAXOS - ACESSO MANUAL                       ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Verificar se kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERRO] kubectl não encontrado. Por favor, instale o kubectl antes de continuar.${NC}"
    exit 1
fi

# Função para criar e gerenciar port-forwards
declare -A pf_pids

start_port_forward() {
    local service=$1
    local local_port=$2
    local target_port=$3
    
    echo -e "${YELLOW}Iniciando port-forward para $service: localhost:$local_port -> $service:$target_port${NC}"
    
    # Check if already forwarding
    if [[ -v pf_pids[$service] ]]; then
        if kill -0 ${pf_pids[$service]} 2>/dev/null; then
            echo -e "${YELLOW}Port-forward para $service já está ativo (PID: ${pf_pids[$service]})${NC}"
            return
        fi
    fi
    
    kubectl port-forward -n $NAMESPACE "service/$service" "$local_port:$target_port" &
    pf_pids[$service]=$!
    
    echo -e "${GREEN}Port-forward iniciado: ${pf_pids[$service]}${NC}"
    # Wait a bit for port-forward to start
    sleep 2
}

stop_port_forward() {
    local service=$1
    
    if [[ -v pf_pids[$service] ]]; then
        echo -e "${YELLOW}Parando port-forward para $service (PID: ${pf_pids[$service]})${NC}"
        kill ${pf_pids[$service]} 2>/dev/null
        unset pf_pids[$service]
    else
        echo -e "${YELLOW}Nenhum port-forward ativo para $service${NC}"
    fi
}

stop_all_port_forwards() {
    echo -e "${YELLOW}Parando todos os port-forwards${NC}"
    for service in "${!pf_pids[@]}"; do
        stop_port_forward $service
    done
}

# Set up trap to clean up port-forwards on exit
trap stop_all_port_forwards EXIT

# Função para usar Python diretamente via cliente
use_client_python() {
    local client_pod=$(kubectl get pods -n $NAMESPACE -l app=client1 -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$client_pod" ]; then
        echo -e "${RED}[ERRO] Pod do cliente não encontrado${NC}"
        return
    fi
    
    echo -e "${CYAN}Acessando cliente diretamente via Python...${NC}"
    
    kubectl exec -it -n $NAMESPACE $client_pod -- python3 -c '
import json
import requests
import time
import random

print("\nBem-vindo ao Cliente Python Paxos!")
print("==================================")

def read_values():
    """Ler valores do sistema"""
    try:
        response = requests.get("http://localhost:6001/read", timeout=5)
        if response.status_code == 200:
            values = response.json().get("values", [])
            print(f"\nValores obtidos ({len(values)}):")
            for i, value in enumerate(values):
                print(f"{i+1}. {value}")
        else:
            print(f"Erro ao ler valores: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Erro ao ler valores: {e}")

def send_value(value):
    """Enviar valor para o sistema"""
    try:
        response = requests.post(
            "http://localhost:6001/send",
            headers={"Content-Type": "application/json"},
            json={"value": value},
            timeout=5
        )
        
        print(f"\nResposta: {response.status_code}")
        if response.status_code == 200:
            print("Valor enviado com sucesso!")
            print(json.dumps(response.json(), indent=2))
        else:
            print(f"Erro ao enviar valor: {response.text}")
    except Exception as e:
        print(f"Erro ao enviar valor: {e}")

def try_direct_proposer(value):
    """Tentar enviar diretamente para um proposer"""
    proposers = [
        ("proposer1", 3001),
        ("proposer2", 3002),
        ("proposer3", 3003)
    ]
    
    # Tentar cada proposer em ordem aleatória
    random.shuffle(proposers)
    
    for proposer, port in proposers:
        try:
            url = f"http://{proposer}.{namespace}.svc.cluster.local:{port}/propose"
            print(f"\nTentando enviar para {proposer} ({url})...")
            
            response = requests.post(
                url,
                headers={"Content-Type": "application/json"},
                json={"value": value, "client_id": 9},
                timeout=5
            )
            
            print(f"Resposta: {response.status_code}")
            print(json.dumps(response.json(), indent=2))
            
            if response.status_code == 200:
                print(f"Valor enviado com sucesso via {proposer}!")
                return True
        except Exception as e:
            print(f"Erro ao enviar para {proposer}: {e}")
    
    print("Falha ao enviar para todos os proposers")
    return False

def get_responses():
    """Obter respostas recebidas"""
    try:
        response = requests.get("http://localhost:6001/get-responses", timeout=5)
        if response.status_code == 200:
            responses = response.json().get("responses", [])
            print(f"\nRespostas recebidas ({len(responses)}):")
            for i, resp in enumerate(responses):
                print(f"{i+1}. Proposta {resp.get(\"proposal_number\")}: \"{resp.get(\"value\")}\" do learner {resp.get(\"learner_id\")}")
                print(f"   Aprendido: {resp.get(\"learned_at\")}, Recebido: {resp.get(\"received_at\")}")
        else:
            print(f"Erro ao obter respostas: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Erro ao obter respostas: {e}")

def get_client_status():
    """Obter status do cliente"""
    try:
        response = requests.get("http://localhost:6001/view-logs", timeout=5)
        if response.status_code == 200:
            print("\nStatus do cliente:")
            print(json.dumps(response.json(), indent=2))
        else:
            print(f"Erro ao obter status: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Erro ao obter status: {e}")

def force_leader_election():
    """Forçar uma eleição de líder"""
    value = f"force_election_{random.randint(1000, 9999)}"
    
    print("\nForçando eleição de líder...")
    # Tentar via todos os proposers
    proposers = [
        ("proposer1", 3001),
        ("proposer2", 3002),
        ("proposer3", 3003)
    ]
    
    # Tentar cada proposer
    for proposer, port in proposers:
        try:
            url = f"http://{proposer}.{namespace}.svc.cluster.local:{port}/propose"
            print(f"Tentando via {proposer} ({url})...")
            
            response = requests.post(
                url,
                headers={"Content-Type": "application/json"},
                json={"value": f"{value}_{proposer}", "client_id": 9},
                timeout=5
            )
            
            print(f"Resposta: {response.status_code}")
            print(json.dumps(response.json(), indent=2))
            
            # Checar se há um líder
            try:
                status_url = f"http://{proposer}.{namespace}.svc.cluster.local:{port}/view-logs"
                status = requests.get(status_url, timeout=5)
                
                if status.status_code == 200:
                    leader = status.json().get("current_leader")
                    if leader:
                        print(f"Líder atual: Proposer {leader}")
                        return
            except:
                pass
                
        except Exception as e:
            print(f"Erro ao enviar para {proposer}: {e}")
    
    print("Não foi possível eleger um líder")

# Ambiente
namespace = "paxos"

# Loop principal
while True:
    print("\nOpções:")
    print("1. Ler valores")
    print("2. Enviar valor")
    print("3. Enviar diretamente para proposer")
    print("4. Ver respostas recebidas")
    print("5. Ver status do cliente")
    print("6. Forçar eleição de líder")
    print("0. Sair")
    
    try:
        choice = input("\nEscolha uma opção: ")
        
        if choice == "1":
            read_values()
        elif choice == "2":
            value = input("Digite o valor: ")
            if value:
                send_value(value)
        elif choice == "3":
            value = input("Digite o valor: ")
            if value:
                try_direct_proposer(value)
        elif choice == "4":
            get_responses()
        elif choice == "5":
            get_client_status()
        elif choice == "6":
            force_leader_election()
        elif choice == "0":
            break
        else:
            print("Opção inválida!")
    except KeyboardInterrupt:
        print("\nSaindo...")
        break
    except Exception as e:
        print(f"Erro: {e}")
        
    # Aguardar um pouco antes de mostrar menu novamente
    time.sleep(1)
'
}

# Menu principal
show_menu() {
    clear
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}              SISTEMA PAXOS - ACESSO MANUAL                       ${NC}"
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    echo -e "1) Acesso via Python direto no pod do cliente"
    echo -e "2) Acesso via port-forward de todos os serviços"
    echo -e "3) Diagnóstico de rede interno"
    echo -e "4) Reiniciar todos os pods"
    echo -e "5) Ver logs dos pods"
    echo -e "0) Sair"
    echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Escolha uma opção:${NC}"
}

setup_all_port_forwards() {
    echo -e "${YELLOW}Configurando port-forwards para todos os serviços principais...${NC}"
    
    # Proposers
    start_port_forward "proposer1" "3001" "api"
    start_port_forward "proposer2" "3002" "api"
    start_port_forward "proposer3" "3003" "api"
    
    # Client
    start_port_forward "client1" "6001" "api"
    
    # Learner
    start_port_forward "learner1" "5001" "api"
    
    echo -e "${GREEN}Port-forwards configurados. Use curl para acessar os serviços:${NC}"
    echo -e "  curl http://localhost:3001/view-logs"
    echo -e "  curl http://localhost:6001/read"
    echo -e "  curl -X POST http://localhost:3001/propose -H 'Content-Type: application/json' -d '{\"value\":\"test\",\"client_id\":9}'"
    
    echo -e "\n${YELLOW}Pressione Enter para continuar...${NC}"
    read
}

diagnose_network() {
    echo -e "${YELLOW}Executando diagnóstico de rede interno...${NC}"
    
    # Criar pod para diagnóstico
    kubectl run net-diag --namespace=$NAMESPACE --rm -i --restart=Never --image=busybox:1.28 -- sh -c '
    echo "=== Informações de DNS ==="
    cat /etc/resolv.conf
    
    echo "\n=== Testando DNS ==="
    nslookup kubernetes.default
    
    echo "\n=== Testando conectividade entre serviços ==="
    for svc in proposer1 proposer2 proposer3 acceptor1 acceptor2 acceptor3 learner1 learner2 client1 client2; do
        echo "\nTestando $svc:"
        if ping -c 1 -W 2 $svc.paxos.svc.cluster.local > /dev/null 2>&1; then
            echo "✅ Ping para $svc.paxos.svc.cluster.local bem-sucedido"
        else
            echo "❌ Ping para $svc.paxos.svc.cluster.local falhou"
        fi
        
        if nslookup $svc.paxos.svc.cluster.local > /dev/null 2>&1; then
            echo "✅ Resolução de nome para $svc.paxos.svc.cluster.local bem-sucedida"
        else
            echo "❌ Resolução de nome para $svc.paxos.svc.cluster.local falhou"
        fi
    done
    
    echo "\n=== Interfaces de rede ==="
    ifconfig || ip addr
    
    echo "\n=== Roteamento ==="
    route || ip route
    '
    
    echo -e "\n${YELLOW}Diagnóstico concluído. Pressione Enter para continuar...${NC}"
    read
}

restart_all_pods() {
    echo -e "${YELLOW}Reiniciando todos os pods na ordem correta...${NC}"
    
    # Reiniciar deployments na ordem
    echo -e "${YELLOW}Reiniciando proposers...${NC}"
    kubectl rollout restart deployment -n $NAMESPACE -l role=proposer
    kubectl rollout status deployment -n $NAMESPACE -l role=proposer
    
    echo -e "${YELLOW}Reiniciando acceptors...${NC}"
    kubectl rollout restart deployment -n $NAMESPACE -l role=acceptor
    kubectl rollout status deployment -n $NAMESPACE -l role=acceptor
    
    echo -e "${YELLOW}Reiniciando learners...${NC}"
    kubectl rollout restart deployment -n $NAMESPACE -l role=learner
    kubectl rollout status deployment -n $NAMESPACE -l role=learner
    
    echo -e "${YELLOW}Reiniciando clients...${NC}"
    kubectl rollout restart deployment -n $NAMESPACE -l role=client
    kubectl rollout status deployment -n $NAMESPACE -l role=client
    
    echo -e "${GREEN}Todos os pods reiniciados.${NC}"
    echo -e "${YELLOW}Aguardando 15 segundos para estabilização...${NC}"
    sleep 15
    
    echo -e "${YELLOW}Status dos pods:${NC}"
    kubectl get pods -n $NAMESPACE
    
    echo -e "\n${YELLOW}Pressione Enter para continuar...${NC}"
    read
}

view_pod_logs() {
    echo -e "${YELLOW}Escolha qual tipo de pod para ver logs:${NC}"
    echo -e "1) Proposers"
    echo -e "2) Acceptors"
    echo -e "3) Learners"
    echo -e "4) Clients"
    read -p "> " log_choice
    
    local role=""
    case $log_choice in
        1) role="proposer";;
        2) role="acceptor";;
        3) role="learner";;
        4) role="client";;
        *) echo -e "${RED}Opção inválida${NC}"; return;;
    esac
    
    # Obter pods do tipo selecionado
    local pods=$(kubectl get pods -n $NAMESPACE -l role=$role -o jsonpath="{.items[*].metadata.name}")
    
    if [ -z "$pods" ]; then
        echo -e "${RED}Nenhum pod do tipo $role encontrado${NC}"
        return
    fi
    
    # Mostrar logs de cada pod
    for pod in $pods; do
        echo -e "${YELLOW}=== Logs do pod $pod ===${NC}"
        kubectl logs -n $NAMESPACE $pod | tail -n 30
        echo -e "${YELLOW}===============================${NC}"
    done
    
    echo -e "\n${YELLOW}Pressione Enter para continuar...${NC}"
    read
}

# Loop principal
while true; do
    show_menu
    read choice
    
    case $choice in
        1) use_client_python;;
        2) setup_all_port_forwards;;
        3) diagnose_network;;
        4) restart_all_pods;;
        5) view_pod_logs;;
        0) 
            stop_all_port_forwards
            echo -e "${GREEN}Saindo...${NC}"
            exit 0
            ;;
        *) echo -e "${RED}Opção inválida!${NC}"; sleep 1;;
    esac
done
