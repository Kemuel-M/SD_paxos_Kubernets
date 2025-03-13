#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Para interagir com o sistema, use:${NC}"
echo -e "   ./paxos-client.sh write \"novo valor\""
echo -e "   ./paxos-client.sh read"
echo -e "   ./paxos-client.sh status"

echo -e "\n${GREEN}Para visualizar todos os recursos:${NC}"
echo -e "kubectl get all -n paxos"

echo -e "\n${GREEN}Para limpar o sistema:${NC}"
echo -e "./cleanup-paxos-k8s.sh"
echo -e "${YELLOW}Implantando sistema Paxos no Kubernetes...${NC}"

# Verificar se o cluster Minikube está em execução
if ! minikube status | grep -q "Running"; then
    echo -e "${YELLOW}Inicializando cluster Minikube...${NC}"
    minikube start --driver=docker
    
    # Habilitar o add-on ingress do Minikube
    echo -e "${YELLOW}Habilitando add-on Ingress...${NC}"
    minikube addons enable ingress
else
    echo -e "${GREEN}Cluster Minikube já está em execução.${NC}"
fi

# Construir a imagem Docker do nó Paxos
echo -e "${YELLOW}Construindo imagem Docker do nó Paxos...${NC}"
eval $(minikube -p minikube docker-env)
docker build -t paxos-node:latest ./nodes/

# Criar o namespace e recursos do Kubernetes
echo -e "${YELLOW}Criando recursos Kubernetes...${NC}"
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-proposers.yaml
kubectl apply -f k8s/03-acceptors.yaml
kubectl apply -f k8s/04-learners.yaml
kubectl apply -f k8s/05-clients.yaml
kubectl apply -f k8s/07-nodeport-services.yaml

# Aguardar a inicialização de todos os pods
echo -e "${YELLOW}Aguardando inicialização dos pods...${NC}"
kubectl -n paxos wait --for=condition=Ready pods --all --timeout=300s

# Aplicar ingress após os serviços estarem prontos
echo -e "${YELLOW}Configurando Ingress...${NC}"
kubectl apply -f k8s/06-ingress.yaml

# Obter informações do cluster
echo -e "${GREEN}Sistema Paxos implantado com sucesso no Kubernetes!${NC}"
echo -e "${YELLOW}Informações de acesso:${NC}"
echo -e "Para acessar o cliente diretamente: minikube service client1-external -n paxos --url"
echo -e "Para acessar o painel de monitoramento: minikube service client1-external -n paxos --url"

# Obter URLs de acesso
CLIENT_URL=$(minikube service client1-external -n paxos --url | head -n1)
MONITOR_URL=$(minikube service client1-external -n paxos --url | tail -n1)

echo -e "${GREEN}URL do Cliente: ${CLIENT_URL}${NC}"
echo -e "${GREEN}URL do Monitor: ${MONITOR_URL}${NC}"

echo -e "${