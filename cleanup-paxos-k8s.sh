#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Removendo sistema Paxos do Kubernetes...${NC}"

# Remover todos os recursos do namespace paxos
kubectl delete -f k8s/06-ingress.yaml 2>/dev/null || true
kubectl delete -f k8s/07-nodeport-services.yaml 2>/dev/null || true
kubectl delete -f k8s/05-clients.yaml 2>/dev/null || true
kubectl delete -f k8s/04-learners.yaml 2>/dev/null || true
kubectl delete -f k8s/03-acceptors.yaml 2>/dev/null || true
kubectl delete -f k8s/02-proposers.yaml 2>/dev/null || true
kubectl delete -f k8s/01-configmap.yaml 2>/dev/null || true

# Aguardar um pouco para os recursos terminarem
echo -e "${YELLOW}Aguardando remoção de recursos...${NC}"
sleep 10

# Remover o namespace (remove todos os recursos dentro dele)
kubectl delete -f k8s/00-namespace.yaml

echo -e "${GREEN}Sistema Paxos removido com sucesso do Kubernetes!${NC}"

# Perguntar se deseja parar o cluster Minikube
read -p "Deseja parar o cluster Minikube? (s/n): " STOP_CLUSTER
if [[ "$STOP_CLUSTER" == "s" || "$STOP_CLUSTER" == "S" ]]; then
    echo -e "${YELLOW}Parando cluster Minikube...${NC}"
    minikube stop
    echo -e "${GREEN}Cluster Minikube parado.${NC}"
fi
