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
echo -e "${BLUE}              SISTEMA PAXOS - FORÇANDO LIDERANÇA                 ${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"

# Verificar se kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERRO] kubectl não encontrado. Por favor, instale o kubectl antes de continuar.${NC}"
    exit 1
fi

# Escolher proposer1 como nosso líder
LEADER_ID=1
LEADER_POD=$(kubectl get pods -n $NAMESPACE -l app=proposer1 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$LEADER_POD" ]; then
    echo -e "${RED}[ERRO] Pod proposer1 não encontrado!${NC}"
    exit 1
fi

echo -e "${YELLOW}Forcing proposer1 (pod: $LEADER_POD) to be the leader...${NC}"

# Criar um script Python que acessará diretamente variáveis internas
cat <<'EOF' > /tmp/force_leadership.py
import json
import threading
import time
import requests

# Manual election function
def manual_election():
    """
    This function will manually manipulate the leader state in all proposers
    """
    print("\nSTEP 1: Checking current state of all proposers")
    proposers = [
        ("localhost", 3001, 1),
        ("proposer1", 3001, 1),
        ("proposer2", 3002, 2),
        ("proposer3", 3003, 3)
    ]
    
    for name, port, id in proposers:
        try:
            print(f"Checking proposer{id} via {name}:{port}...")
            response = requests.get(f"http://{name}:{port}/view-logs", timeout=2)
            if response.status_code == 200:
                data = response.json()
                print(f"Proposer{id} state: {json.dumps(data, indent=2)}")
            else:
                print(f"Error: {response.status_code}")
        except Exception as e:
            print(f"Error connecting to {name}: {e}")
    
    print("\nSTEP 2: Performing manual leader election process")
    print("Attempting to force proposer1 as leader...")
    
    # First try using proposer1 to trigger an election
    try:
        # Prepare phase to all acceptors
        acceptors = ["acceptor1", "acceptor2", "acceptor3"]
        proposal_num = int(time.time() % 10000) * 100 + 1  # Generate a unique proposal number
        
        print(f"Using proposal number: {proposal_num}")
        
        # Send prepare to all acceptors
        success_count = 0
        for acceptor in acceptors:
            try:
                print(f"Sending prepare to {acceptor}...")
                prepare_data = {
                    "proposer_id": 1,
                    "proposal_number": proposal_num,
                    "is_leader_election": True
                }
                response = requests.post(f"http://{acceptor}:4001/prepare", json=prepare_data, timeout=3)
                if response.status_code == 200:
                    result = response.json()
                    if result.get("status") == "promise":
                        success_count += 1
                        print(f"Received promise from {acceptor}")
                    else:
                        print(f"Rejected by {acceptor}: {result.get('message')}")
                else:
                    print(f"Error from {acceptor}: {response.status_code}")
            except Exception as e:
                print(f"Failed to send prepare to {acceptor}: {e}")
        
        print(f"Received {success_count} promises")
        
        # If we got promises, send accepts
        if success_count >= 2:  # Majority of 3
            print("Got quorum! Sending accept messages...")
            accept_value = "leader:1"  # Set proposer1 as leader
            
            # Send accept to all acceptors
            for acceptor in acceptors:
                try:
                    print(f"Sending accept to {acceptor}...")
                    accept_data = {
                        "proposer_id": 1,
                        "proposal_number": proposal_num,
                        "is_leader_election": True,
                        "value": accept_value,
                        "client_id": 9
                    }
                    response = requests.post(f"http://{acceptor}:4001/accept", json=accept_data, timeout=3)
                    if response.status_code == 200:
                        result = response.json()
                        if result.get("status") == "accepted":
                            print(f"Accept successful on {acceptor}")
                        else:
                            print(f"Accept rejected by {acceptor}: {result.get('message')}")
                    else:
                        print(f"Error from {acceptor}: {response.status_code}")
                except Exception as e:
                    print(f"Failed to send accept to {acceptor}: {e}")
            
            print("Manual election phase 1 completed")
        else:
            print("Failed to get quorum of promises")
        
    except Exception as e:
        print(f"Error in manual election: {e}")
    
    print("\nSTEP 3: Direct manipulation of internal state")
    
    # Direct state manipulation in proposer1
    try:
        print("Setting leadership directly in each proposer...")
        
        # Set proposer1 as leader
        for name, port, id in proposers:
            try:
                value = "1" if id == 1 else "null"
                is_leader = "true" if id == 1 else "false"
                
                gossip_inject = f"""
                try:
                    from importlib import import_module
                    import json
                    import time
                    
                    # Access the global gossip instance
                    if 'g' not in globals() or g is None:
                        # Find references to the gossip instance
                        for var_name in dir():
                            try:
                                var = globals()[var_name]
                                if hasattr(var, 'gossip'):
                                    g = var.gossip
                                    break
                            except:
                                pass
                    
                    if 'g' in globals() and g is not None:
                        # Print current state
                        print(f"Current leader: {{g.get_leader()}}")
                        
                        # Force leader
                        g.leader_id = {id if id == 1 else 'None'}
                        
                        # Update metadata
                        g.update_local_metadata({{"is_leader": {is_leader}}})
                        
                        # Force propagation
                        g.self_version += 1
                        print(f"Leader set to: {{g.get_leader()}}")
                        print("State updated successfully")
                    else:
                        print("Could not find gossip instance")
                except Exception as e:
                    print(f"Error: {{e}}")
                """
                
                # Create a temporary Python file
                temp_file = f"/tmp/gossip_inject_{id}.py"
                with open(temp_file, "w") as f:
                    f.write(gossip_inject)
                
                # Execute the script in the target proposer
                cmd = f"kubectl exec -n paxos $(kubectl get pods -n paxos -l app=proposer{id} -o jsonpath='{{.items[0].metadata.name}}') -- python -c \"$(cat {temp_file})\""
                print(f"Executing in proposer{id}...")
                import subprocess
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                print(f"Output: {result.stdout}")
                if result.stderr:
                    print(f"Error: {result.stderr}")
            except Exception as e:
                print(f"Failed to set leader in proposer{id}: {e}")
        
    except Exception as e:
        print(f"Error in direct state manipulation: {e}")
    
    print("\nSTEP 4: Verification of leadership state")
    
    # Verify leadership state
    for name, port, id in proposers:
        try:
            print(f"Verifying proposer{id} via {name}:{port}...")
            response = requests.get(f"http://{name}:{port}/view-logs", timeout=2)
            if response.status_code == 200:
                data = response.json()
                print(f"Current leader: {data.get('current_leader')}")
                print(f"Is leader: {data.get('is_leader')}")
            else:
                print(f"Error: {response.status_code}")
        except Exception as e:
            print(f"Error connecting to {name}: {e}")
    
    print("\nLeadership adjustment completed")

# Call our manual election function
manual_election()
EOF

# Copiar o script para o pod líder
kubectl cp /tmp/force_leadership.py ${NAMESPACE}/${LEADER_POD}:/tmp/force_leadership.py

# Executar o script dentro do pod
echo -e "${YELLOW}Executando script de injeção de liderança...${NC}"
kubectl exec -n ${NAMESPACE} ${LEADER_POD} -- python3 /tmp/force_leadership.py

# Aguardar alguns segundos
echo -e "${YELLOW}Aguardando 5 segundos para a propagação das mudanças...${NC}"
sleep 5

# Verificar o estado final
echo -e "${YELLOW}Verificando estado final dos proposers...${NC}"
for i in {1..3}; do
    PROPOSER_POD=$(kubectl get pods -n $NAMESPACE -l app=proposer$i -o jsonpath="{.items[0].metadata.name}")
    if [ ! -z "$PROPOSER_POD" ]; then
        echo -e "${YELLOW}Proposer $i (pod: $PROPOSER_POD):${NC}"
        kubectl exec -n $NAMESPACE $PROPOSER_POD -- curl -s http://localhost:300$i/view-logs | grep -E "current_leader|is_leader"
        echo ""
    fi
done

# Testar envio de uma proposta para o líder
echo -e "${YELLOW}Testando envio de proposta para o líder...${NC}"
kubectl exec -n $NAMESPACE $LEADER_POD -- curl -s -X POST http://localhost:3001/propose -H 'Content-Type: application/json' -d '{"value":"test_after_leadership","client_id":9}'

# Reiniciar pods na ordem correta para garantir que as mudanças sejam mantidas
echo -e "${YELLOW}Aplicando modificações para reinício dos pods...${NC}"

# Criar um script para reiniciar os pods com garantia de estabilidade
cat <<'EOF' > /tmp/restart_pods.py
import subprocess
import time
import json

namespace = "paxos"

def run_command(cmd):
    """Execute a command and return the output"""
    process = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return process.stdout.strip()

def restart_deployment(name):
    """Restart a deployment and wait for it to be ready"""
    print(f"Restarting {name}...")
    run_command(f"kubectl rollout restart deployment/{name} -n {namespace}")
    run_command(f"kubectl rollout status deployment/{name} -n {namespace}")
    print(f"{name} restarted successfully")

# Restart in correct order
print("\nRestarting acceptors...")
restart_deployment("acceptor1")
restart_deployment("acceptor2")
restart_deployment("acceptor3")

print("\nRestarting learners...")
restart_deployment("learner1")
restart_deployment("learner2")

print("\nRestarting clients...")
restart_deployment("client1")
restart_deployment("client2")

print("\nRestarting proposers (leader last)...")
restart_deployment("proposer2")
restart_deployment("proposer3")
restart_deployment("proposer1")  # Leader should be restarted last

# Wait for system to stabilize
print("\nWaiting for system to stabilize...")
time.sleep(15)

# Check final state
print("\nChecking proposer states...")
for i in range(1, 4):
    pod = run_command(f"kubectl get pods -n {namespace} -l app=proposer{i} -o jsonpath='{{.items[0].metadata.name}}'")
    logs = run_command(f"kubectl exec -n {namespace} {pod} -- curl -s http://localhost:300{i}/view-logs")
    try:
        data = json.loads(logs)
        print(f"Proposer{i} - Leader: {data.get('current_leader')}, Is Leader: {data.get('is_leader')}")
    except:
        print(f"Proposer{i} - Error parsing response")

print("\nSystem restart completed")
EOF

# Executar o script de reinício
python3 /tmp/restart_pods.py

echo -e "\n${BLUE}═════════════════════ VERIFICAÇÃO FINAL ═════════════════════${NC}"
# Verificar status dos pods
echo -e "${YELLOW}Status dos pods:${NC}"
kubectl get pods -n $NAMESPACE

echo -e "\n${BLUE}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Tentativa de eleição de líder forçada concluída!${NC}"
echo -e "${YELLOW}Execute o cliente para testar o sistema:${NC} ${CYAN}./paxos-client.sh${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════════════${NC}"
