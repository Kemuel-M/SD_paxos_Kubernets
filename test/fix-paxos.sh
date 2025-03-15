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
echo -e "${BLUE}              SISTEMA PAXOS - DIAGNÓSTICO E CORREÇÃO             ${NC}"
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

# Verificar status do minikube
echo -e "\n${YELLOW}Verificando status do Minikube...${NC}"
if ! minikube status | grep -q "Running"; then
    echo -e "${YELLOW}Minikube não está rodando corretamente. Tentando reiniciar...${NC}"
    minikube stop
    sleep 2
    minikube start --driver=docker
    
    # Verificar se o reinício resolveu o problema
    if ! minikube status | grep -q "Running"; then
        echo -e "${RED}[ERRO] Não foi possível iniciar o Minikube. Verifique sua instalação.${NC}"
        exit 1
    fi
fi

# Verificar CoreDNS
echo -e "\n${YELLOW}Verificando status do CoreDNS...${NC}"
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Reiniciar CoreDNS para garantir que está funcionando
echo -e "${YELLOW}Reiniciando CoreDNS...${NC}"
kubectl rollout restart deployment -n kube-system coredns
kubectl rollout status deployment -n kube-system coredns

# Verificar problemas de DNS
echo -e "\n${YELLOW}Testando resolução de DNS...${NC}"
if ! kubectl run test-dns --namespace=paxos --rm -i --restart=Never --image=busybox:1.28 -- nslookup kubernetes.default 2>/dev/null; then
    echo -e "${RED}[AVISO] Problemas com DNS detectados. Tentando corrigir...${NC}"
    echo -e "${YELLOW}Aguardando 30 segundos para estabilização do DNS...${NC}"
    sleep 30
    
    # Testar novamente após aguardar
    kubectl run test-dns-2 --namespace=paxos --rm -i --restart=Never --image=busybox:1.28 -- nslookup kubernetes.default
fi

# Verificar e reiniciar pods que não estejam prontos
echo -e "\n${YELLOW}Verificando pods problemáticos...${NC}"
not_ready_pods=$(kubectl get pods -n paxos | grep -v "Running" | grep -v "NAME" | awk '{print $1}')

if [ ! -z "$not_ready_pods" ]; then
    echo -e "${YELLOW}Pods não prontos encontrados:${NC}"
    echo "$not_ready_pods"
    
    # Deletar os pods não prontos para que sejam recriados
    for pod in $not_ready_pods; do
        echo -e "${YELLOW}Deletando pod: $pod${NC}"
        kubectl delete pod -n paxos $pod
    done
    
    echo -e "${YELLOW}Aguardando 10 segundos para recriação dos pods...${NC}"
    sleep 10
fi

# Verificar se o Dockerfile foi atualizado com curl
echo -e "\n${YELLOW}Verificando se é necessário reconstruir a imagem Docker...${NC}"
echo -e "${RED}AVISO: Para prosseguir, é necessário atualizar o Dockerfile para incluir curl.${NC}"
echo -e "${YELLOW}Você já atualizou o Dockerfile para incluir curl? (s/n)${NC}"
read -p "> " rebuild_image

if [[ "$rebuild_image" == "s" || "$rebuild_image" == "S" ]]; then
    echo -e "${YELLOW}Construindo nova imagem Docker...${NC}"
    eval $(minikube docker-env)
    docker build -t paxos-node:latest ./nodes/
    
    # Reiniciar deployments para usar a nova imagem
    echo -e "${YELLOW}Reiniciando deployments para usar a nova imagem...${NC}"
else
    echo -e "${RED}Você precisa atualizar o Dockerfile primeiro. Adicione:${NC}"
    echo -e "${CYAN}RUN apt-get update && apt-get install -y curl${NC}"
    echo -e "${RED}ao Dockerfile e execute este script novamente.${NC}"
    exit 1
fi

# Reiniciar deployments na ordem correta
echo -e "\n${YELLOW}Reiniciando deployments na ordem correta...${NC}"

# Primeiro os proposers
echo -e "${YELLOW}Reiniciando proposers...${NC}"
for i in {1..3}; do
    kubectl rollout restart deployment/proposer$i -n paxos
done

# Aguardar proposers ficarem prontos
echo -e "${YELLOW}Aguardando proposers ficarem prontos...${NC}"
for i in {1..3}; do
    kubectl rollout status deployment/proposer$i -n paxos
done

# Depois os acceptors
echo -e "${YELLOW}Reiniciando acceptors...${NC}"
for i in {1..3}; do
    kubectl rollout restart deployment/acceptor$i -n paxos
done

# Aguardar acceptors ficarem prontos
echo -e "${YELLOW}Aguardando acceptors ficarem prontos...${NC}"
for i in {1..3}; do
    kubectl rollout status deployment/acceptor$i -n paxos
done

# Em seguida os learners
echo -e "${YELLOW}Reiniciando learners...${NC}"
for i in {1..2}; do
    kubectl rollout restart deployment/learner$i -n paxos
done

# Aguardar learners ficarem prontos
echo -e "${YELLOW}Aguardando learners ficarem prontos...${NC}"
for i in {1..2}; do
    kubectl rollout status deployment/learner$i -n paxos
done

# Por último os clients
echo -e "${YELLOW}Reiniciando clients...${NC}"
for i in {1..2}; do
    kubectl rollout restart deployment/client$i -n paxos
done

# Aguardar clients ficarem prontos
echo -e "${YELLOW}Aguardando clients ficarem prontos...${NC}"
for i in {1..2}; do
    kubectl rollout status deployment/client$i -n paxos
done

# Aguardar um tempo para estabilização
echo -e "${YELLOW}Aguardando 20 segundos para estabilização do sistema...${NC}"
sleep 20

# Verificar se todos os pods estão rodando
echo -e "\n${YELLOW}Verificando status final dos pods...${NC}"
pod_status=$(kubectl get pods -n paxos)
echo "$pod_status"

# Verificar se todos os pods estão rodando e prontos
not_running=$(echo "$pod_status" | grep -v "Running" | grep -v "NAME" | wc -l)

if [ "$not_running" -eq "0" ]; then
    echo -e "${GREEN}Todos os pods estão rodando!${NC}"
else
    echo -e "${RED}[AVISO] Ainda há pods que não estão prontos ou rodando.${NC}"
fi

# Forçar eleição de líder
echo -e "\n${YELLOW}Forçando eleição de líder através de port-forward...${NC}"

# Obter o nome do pod proposer1
proposer1_pod=$(kubectl get pods -n paxos -l app=proposer1 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$proposer1_pod" ]; then
    echo -e "${RED}[ERRO] Pod proposer1 não encontrado!${NC}"
else
    # Usar port-forward para conectar ao serviço
    echo -e "${YELLOW}Iniciando port-forward para proposer1...${NC}"
    kubectl port-forward -n paxos $proposer1_pod 3001:3001 &
    PF_PID=$!
    
    # Aguardar um pouco para o port-forward estabelecer
    sleep 3
    
    # Enviar proposta para iniciar eleição
    echo -e "${YELLOW}Enviando proposta para iniciar eleição...${NC}"
    curl -s -X POST http://localhost:3001/propose -H 'Content-Type: application/json' -d '{"value":"force_election","client_id":9}'
    
    # Aguardar eleição
    echo -e "${YELLOW}Aguardando 10 segundos para eleição de líder...${NC}"
    sleep 10
    
    # Verificar se há um líder eleito
    leader_info=$(curl -s http://localhost:3001/view-logs)
    current_leader=$(echo $leader_info | grep -o '"current_leader":[^,}]*' | cut -d':' -f2 | tr -d '"' 2>/dev/null)
    
    # Encerrar o port-forward
    kill $PF_PID 2>/dev/null
    
    if [ -z "$current_leader" ] || [ "$current_leader" = "null" ]; then
        echo -e "${RED}[AVISO] Não foi possível eleger um líder usando proposer1.${NC}"
        
        # Tentar com outro proposer
        proposer2_pod=$(kubectl get pods -n paxos -l app=proposer2 -o jsonpath="{.items[0].metadata.name}")
        if [ ! -z "$proposer2_pod" ]; then
            echo -e "${YELLOW}Tentando com proposer2...${NC}"
            kubectl port-forward -n paxos $proposer2_pod 3002:3002 &
            PF_PID=$!
            
            sleep 3
            curl -s -X POST http://localhost:3002/propose -H 'Content-Type: application/json' -d '{"value":"force_election2","client_id":9}'
            
            sleep 10
            leader_info=$(curl -s http://localhost:3002/view-logs)
            current_leader=$(echo $leader_info | grep -o '"current_leader":[^,}]*' | cut -d':' -f2 | tr -d '"' 2>/dev/null)
            
            kill $PF_PID 2>/dev/null
            
            if [ -z "$current_leader" ] || [ "$current_leader" = "null" ]; then
                echo -e "${RED}[AVISO] Ainda não foi possível eleger um líder.${NC}"
            else
                echo -e "${GREEN}Líder eleito: Proposer $current_leader${NC}"
            fi
        fi
    else
        echo -e "${GREEN}Líder eleito: Proposer $current_leader${NC}"
    fi
fi

echo -e "\n${BLUE}═════════════════════ ACESSOS AO SISTEMA ═════════════════════${NC}"
echo -e "${YELLOW}Para acessar o cliente, execute em um terminal separado:${NC}"
echo -e "${CYAN}minikube service client1-external -n paxos${NC}"
echo -e "${YELLOW}Para acessar o proposer, execute em um terminal separado:${NC}"
echo -e "${CYAN}minikube service proposer1-external -n paxos${NC}"

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Diagnóstico e correção concluídos! Tente usar o cliente agora.${NC}"
echo -e "${YELLOW}Você pode precisar executar:${NC} ${CYAN}./paxos-client.sh${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"