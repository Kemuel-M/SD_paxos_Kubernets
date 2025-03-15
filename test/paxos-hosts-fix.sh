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
echo -e "${BLUE}              SISTEMA PAXOS - CORREÇÃO DE HOSTNAMES              ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Verificar se kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERRO] kubectl não encontrado. Por favor, instale o kubectl antes de continuar.${NC}"
    exit 1
fi

# Obter todos os pods e seus IPs
echo -e "${YELLOW}Obtendo informações de todos os pods...${NC}"

# Criar arquivo de hosts temporário
HOSTS_FILE=$(mktemp)
echo "# Hosts adicionais para Paxos" > $HOSTS_FILE
echo "# Gerado por paxos-hosts-fix.sh" >> $HOSTS_FILE
echo "" >> $HOSTS_FILE

# Adicionar entradas para todos os pods
kubectl get pods -n $NAMESPACE -o wide | grep -v NAME | awk '{print $6, $1}' | while read ip pod; do
    if [ ! -z "$ip" ] && [ ! -z "$pod" ]; then
        echo "$ip $pod" >> $HOSTS_FILE
        echo "$ip $pod.$NAMESPACE.pod.cluster.local" >> $HOSTS_FILE
    fi
done

# Adicionar entradas para todos os serviços
kubectl get svc -n $NAMESPACE | grep -v NAME | awk '{print $3, $1}' | while read ip service; do
    if [ ! -z "$ip" ] && [ ! -z "$service" ]; then
        echo "$ip $service" >> $HOSTS_FILE
        echo "$ip $service.$NAMESPACE.svc.cluster.local" >> $HOSTS_FILE
    fi
done

# Mostrar o conteúdo do arquivo de hosts
echo -e "${YELLOW}Arquivo de hosts gerado:${NC}"
cat $HOSTS_FILE
echo ""

# Função para injetar hosts em cada pod
inject_hosts() {
    local pod=$1
    
    echo -e "${YELLOW}Injetando hosts em $pod...${NC}"
    
    # Criar script para modificar /etc/hosts no pod
    cat <<'EOF' > /tmp/update_hosts.sh
#!/bin/sh
# Backup original hosts file
cp /etc/hosts /etc/hosts.backup

# Append new entries
cat /tmp/paxos_hosts >> /etc/hosts

# Show the updated hosts file
echo "Updated /etc/hosts:"
cat /etc/hosts
EOF
    
    # Tornar o script executável
    chmod +x /tmp/update_hosts.sh
    
    # Copiar arquivo de hosts e script para o pod
    kubectl cp $HOSTS_FILE $NAMESPACE/$pod:/tmp/paxos_hosts
    kubectl cp /tmp/update_hosts.sh $NAMESPACE/$pod:/tmp/update_hosts.sh
    
    # Executar o script no pod
    kubectl exec -n $NAMESPACE $pod -- sh /tmp/update_hosts.sh
    
    # Imprimir resultado
    echo -e "${GREEN}Hosts adicionados com sucesso em $pod${NC}"
    echo ""
}

# Injetar hosts em todos os pods
echo -e "${YELLOW}Injetando arquivo de hosts em todos os pods...${NC}"
kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | while read pod; do
    inject_hosts $pod
done

# Reiniciar serviços Python dentro dos pods
echo -e "${YELLOW}Reiniciando serviços Python em todos os pods...${NC}"
kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | while read pod; do
    echo -e "${YELLOW}Reiniciando serviço em $pod...${NC}"
    
    # Criar script para reiniciar o serviço Python
    cat <<'EOF' > /tmp/restart_service.sh
#!/bin/sh
# Find Python process
pid=$(ps aux | grep "python main.py" | grep -v grep | awk '{print $1}')

if [ -n "$pid" ]; then
  echo "Reiniciando processo Python (PID: $pid)..."
  kill -TERM $pid
  sleep 1
  # Process will be restarted by the container's entrypoint
else
  echo "Nenhum processo Python encontrado para reiniciar"
fi
EOF
    
    # Tornar o script executável
    chmod +x /tmp/restart_service.sh
    
    # Copiar script para o pod
    kubectl cp /tmp/restart_service.sh $NAMESPACE/$pod:/tmp/restart_service.sh
    
    # Executar o script no pod
    kubectl exec -n $NAMESPACE $pod -- sh /tmp/restart_service.sh
    
    echo ""
done

# Aguardar um pouco para os serviços reiniciarem
echo -e "${YELLOW}Aguardando 15 segundos para os serviços reiniciarem...${NC}"
sleep 15

# Forçar eleição de líder
echo -e "${YELLOW}Forçando eleição de líder...${NC}"

# Obter um pod proposer
proposer_pod=$(kubectl get pods -n $NAMESPACE -l app=proposer1 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$proposer_pod" ]; then
    echo -e "${RED}[ERRO] Nenhum pod proposer encontrado!${NC}"
else
    # Criar script Python para forçar eleição
    cat <<'EOF' > /tmp/force_election.py
import json
import requests
import time
import random

# Tentar iniciar eleição via todos os proposers
proposers = [
    ("localhost", 3001),
    ("proposer1", 3001),
    ("proposer2", 3002),
    ("proposer3", 3003)
]

# Função para verificar se há um líder eleito
def check_leader():
    for name, port in proposers:
        try:
            print(f"Verificando líder via {name}:{port}...")
            url = f"http://{name}:{port}/view-logs"
            response = requests.get(url, timeout=3)
            if response.status_code == 200:
                data = response.json()
                leader = data.get("current_leader")
                if leader is not None and leader != "null":
                    print(f"Líder encontrado: {leader}")
                    return True
            print("Nenhum líder encontrado")
        except Exception as e:
            print(f"Erro ao verificar líder via {name}: {e}")
    return False

# Iniciar processo de eleição forçada
for i in range(3):  # Tente 3 vezes
    print(f"\nTentativa {i+1} de eleição forçada")
    
    # Verificar se já há um líder
    if check_leader():
        print("Um líder já está eleito!")
        exit(0)
    
    # Tentar cada proposer
    random.shuffle(proposers)
    for name, port in proposers:
        try:
            print(f"Tentando forçar eleição via {name}:{port}...")
            url = f"http://{name}:{port}/propose"
            data = {
                "value": f"force_election_{random.randint(1000, 9999)}",
                "client_id": 9
            }
            response = requests.post(url, json=data, timeout=5)
            print(f"Resposta: {response.status_code} - {response.text}")
            
            # Esperar um pouco para a eleição acontecer
            print("Aguardando 3 segundos...")
            time.sleep(3)
            
            # Verificar se a eleição foi bem-sucedida
            if check_leader():
                print("Eleição bem-sucedida!")
                exit(0)
        except Exception as e:
            print(f"Erro ao tentar via {name}: {e}")
    
    # Aguardar entre tentativas
    print("Aguardando 5 segundos antes de tentar novamente...")
    time.sleep(5)

print("Não foi possível eleger um líder após múltiplas tentativas")
EOF
    
    # Copiar script para o pod
    kubectl cp /tmp/force_election.py $NAMESPACE/$proposer_pod:/tmp/force_election.py
    
    # Executar o script no pod
    echo -e "${YELLOW}Executando script de eleição no pod $proposer_pod...${NC}"
    kubectl exec -n $NAMESPACE $proposer_pod -- python3 /tmp/force_election.py
fi

# Limpar arquivos temporários
rm -f $HOSTS_FILE /tmp/update_hosts.sh /tmp/restart_service.sh /tmp/force_election.py

echo -e "\n${BLUE}═════════════════════ VERIFICAÇÃO FINAL ═════════════════════${NC}"
# Verificar status dos pods
echo -e "${YELLOW}Status dos pods:${NC}"
kubectl get pods -n $NAMESPACE

# Verificar leader via API
echo -e "\n${YELLOW}Verificando líder eleito...${NC}"
kubectl exec -n $NAMESPACE $proposer_pod -- curl -s http://localhost:3001/view-logs | grep -o '"current_leader":[^,}]*'

echo -e "\n${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Correção de hostnames concluída!${NC}"
echo -e "${YELLOW}Execute o cliente para testar o sistema:${NC} ${CYAN}./paxos-client.sh${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
