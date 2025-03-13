# Guia de Implantação do Sistema Paxos no Kubernetes (WSL/Ubuntu)

Este guia explica como implantar e utilizar o sistema Paxos em um ambiente Kubernetes usando WSL com Ubuntu.

## Índice

1. [Preparação do Ambiente](#1-preparação-do-ambiente)
2. [Estrutura de Arquivos](#2-estrutura-de-arquivos)
3. [Implantação do Sistema](#3-implantação-do-sistema)
4. [Interação com o Sistema](#4-interação-com-o-sistema)
5. [Monitoramento](#5-monitoramento)
6. [Solução de Problemas](#6-solução-de-problemas)
7. [Limpeza](#7-limpeza)

## 1. Preparação do Ambiente

### 1.1. Requisitos

- Windows 10/11 com WSL2 instalado
- Ubuntu no WSL
- Docker instalado no WSL
- Acesso à internet

### 1.2. Instalação das Ferramentas

Execute o script de preparação do ambiente:

```bash
chmod +x setup-kubernetes-wsl.sh
./setup-kubernetes-wsl.sh
```

Este script instala:
- Docker (se não estiver instalado)
- kubectl
- Minikube

### 1.3. Inicialização do Cluster Minikube

```bash
minikube start --driver=docker
```

Verifique se o cluster está funcionando:

```bash
minikube status
```

## 2. Estrutura de Arquivos

Organize os arquivos da seguinte maneira:

```
paxos-system/
├── nodes/                  # Código-fonte dos nós
│   ├── Dockerfile
│   ├── base_node.py
│   ├── gossip_protocol.py
│   ├── proposer_node.py
│   ├── acceptor_node.py
│   ├── learner_node.py
│   ├── client_node.py
│   ├── main.py
│   └── requirements.txt
├── k8s/                    # Manifestos Kubernetes
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-proposers.yaml
│   ├── 03-acceptors.yaml
│   ├── 04-learners.yaml
│   ├── 05-clients.yaml
│   ├── 06-ingress.yaml
│   └── 07-nodeport-services.yaml
├── setup-kubernetes-wsl.sh # Script de preparação do ambiente
├── deploy-paxos-k8s.sh     # Script de implantação
├── cleanup-paxos-k8s.sh    # Script de limpeza
├── paxos-client.sh         # Cliente de linha de comando
└── paxos_k8s_client.py     # Cliente Python
```

## 3. Implantação do Sistema

### 3.1. Construir Imagem e Implantar

Execute o script de implantação:

```bash
chmod +x deploy-paxos-k8s.sh
./deploy-paxos-k8s.sh
```

Este script:
1. Verifica se o Minikube está em execução
2. Constrói a imagem Docker do nó Paxos
3. Cria todos os recursos Kubernetes necessários
4. Configura o acesso externo ao sistema

### 3.2. Verificar a Implantação

Verifique se todos os pods estão em execução:

```bash
kubectl get pods -n paxos
```

Você deve ver algo como:

```
NAME                         READY   STATUS    RESTARTS   AGE
acceptor1-58f5b9dc74-xhf2g   1/1     Running   0          2m
acceptor2-58f5b9dc74-pqr3t   1/1     Running   0          2m
acceptor3-58f5b9dc74-lkj4f   1/1     Running   0          2m
client1-665b87b4c9-zxc2v     1/1     Running   0          2m
client2-665b87b4c9-asd1f     1/1     Running   0          2m
learner1-58f5b9dc74-qwe5r    1/1     Running   0          2m
learner2-58f5b9dc74-tyu6y    1/1     Running   0          2m
proposer1-58f5b9dc74-mnb7h   1/1     Running   0          2m
proposer2-58f5b9dc74-bnm8j   1/1     Running   0          2m
proposer3-58f5b9dc74-vbn9k   1/1     Running   0          2m
```

## 4. Interação com o Sistema

### 4.1. Usando o Cliente Shell

Torne o script do cliente executável:

```bash
chmod +x paxos-client.sh
```

Comandos disponíveis:

```bash
# Para usar especificamente o client2
CLIENT=client2 ./paxos-client.sh write "valor do client2"

# Para usar um proposer específico no direct-write
PROPOSER=proposer2 ./paxos-client.sh direct-write "direto para proposer2"

### Para usar o client1 (padrão)
# Enviar um valor para o sistema
./paxos-client.sh write "novo valor"

# Enviar um valor diretamente para o proposer
./paxos-client.sh direct-write "valor direto"

# Ler valores do sistema
./paxos-client.sh read

# Ver respostas recebidas pelo cliente
./paxos-client.sh responses

# Ver status do sistema
./paxos-client.sh status

# Abrir acesso no navegador
./paxos-client.sh open
```

### 4.2. Usando o Cliente Python

Torne o script Python executável:

```bash
chmod +x paxos_k8s_client.py
```

Comandos disponíveis:

```bash
# Enviar um valor para o sistema
./paxos_k8s_client.py write "novo valor"

# Enviar um valor diretamente para o proposer
./paxos_k8s_client.py direct-write "valor direto"

# Ler valores do sistema
./paxos_k8s_client.py read

# Ver respostas recebidas pelo cliente
./paxos_k8s_client.py responses

# Ver status do sistema
./paxos_k8s_client.py status

# Monitorar o sistema por 2 minutos
./paxos_k8s_client.py monitor --duration 120 --interval 10
```

### 4.3. Acesso via Navegador

Para acessar o sistema via navegador, execute:

```bash
minikube service client1-external -n paxos
```

Isso abrirá o navegador com a URL de acesso ao cliente.

## 5. Monitoramento

### 5.1. Dashboard do Kubernetes

Acesse o dashboard do Kubernetes:

```bash
minikube dashboard
```

### 5.2. Logs dos Pods

Visualize os logs de um pod específico:

```bash
# Para o proposer1
kubectl logs -n paxos -l app=proposer1

# Para o client1
kubectl logs -n paxos -l app=client1
```

### 5.3. Status do Sistema

Visualize o status detalhado de um serviço:

```bash
# Status do proposer1
kubectl exec -n paxos $(kubectl get pods -n paxos -l app=proposer1 -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3001/view-logs

# Status do client1
kubectl exec -n paxos $(kubectl get pods -n paxos -l app=client1 -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:6001/view-logs
```

## 6. Solução de Problemas

### 6.1. Pods não iniciam

Se alguns pods não estiverem iniciando corretamente:

```bash
# Verifique o status detalhado dos pods
kubectl describe pods -n paxos

# Verifique os logs dos pods com problemas
kubectl logs -n paxos <nome-do-pod>
```

### 6.2. Problemas de rede

Se houver problemas de comunicação entre os pods:

```bash
# Teste a resolução de nomes de serviço de dentro de um pod
kubectl exec -it -n paxos $(kubectl get pods -n paxos -l app=client1 -o jsonpath="{.items[0].metadata.name}") -- nslookup proposer1

# Teste a conectividade usando curl de dentro de um pod
kubectl exec -it -n paxos $(kubectl get pods -n paxos -l app=client1 -o jsonpath="{.items[0].metadata.name}") -- curl -v http://proposer1:3001/health
```

### 6.3. Problemas no algoritmo Paxos

Se o sistema não estiver conseguindo eleger um líder ou processar propostas:

```bash
# Verifique o status do proposer1 (normalmente o líder inicial)
kubectl exec -n paxos $(kubectl get pods -n paxos -l app=proposer1 -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3001/view-logs

# Verifique o status dos acceptors
kubectl exec -n paxos $(kubectl get pods -n paxos -l app=acceptor1 -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:4001/view-logs
```

### 6.4. Reiniciar componentes

Se um componente específico não estiver funcionando corretamente, você pode reiniciá-lo:

```bash
# Reiniciar um deployment específico (por exemplo, proposer1)
kubectl rollout restart deployment proposer1 -n paxos

# Reiniciar todos os deployments
kubectl rollout restart deployment -n paxos
```

## 7. Limpeza

### 7.1. Limpeza do Sistema Paxos

Para remover todos os recursos do sistema Paxos:

```bash
chmod +x cleanup-paxos-k8s.sh
./cleanup-paxos-k8s.sh
```

### 7.2. Parar o Minikube

Se quiser parar o cluster completamente:

```bash
minikube stop
```

Para remover o cluster Minikube:

```bash
minikube delete
```

## 8. Arquitetura do Sistema

### 8.1. Visão Geral

O sistema Paxos no Kubernetes é composto por:

- **3 Proposers**: Iniciam propostas e coordenam o consenso
- **3 Acceptors**: Aceitam ou rejeitam propostas
- **2 Learners**: Aprendem valores escolhidos
- **2 Clients**: Enviam requisições e recebem resultados

### 8.2. Comunicação

No ambiente Kubernetes:

1. A descoberta de serviços é feita pelo DNS interno do Kubernetes
2. Cada serviço tem um nome DNS previsível (ex: `proposer1.paxos.svc.cluster.local`)
3. A comunicação entre os pods é facilitada pela rede interna do Kubernetes
4. O acesso externo é fornecido por serviços NodePort e potencialmente Ingress

### 8.3. Persistência

No ambiente atual, o sistema opera sem persistência de estado entre reinicializações. Em uma configuração de produção, você pode adicionar:

- PersistentVolumeClaims para armazenar dados
- StatefulSets em vez de Deployments para nós que precisam manter estado

## 9. Personalizações e Extensões

### 9.1. Escalar o Sistema

Para aumentar o número de réplicas:

```bash
# Aumentar para 3 learners
kubectl scale deployment learner2 -n paxos --replicas=2
```

### 9.2. Ajustar Configurações

Para modificar configurações, edite o ConfigMap:

```bash
kubectl edit configmap paxos-config -n paxos
```

### 9.3. Adicionar Monitoramento Avançado

Você pode integrar ferramentas como Prometheus e Grafana:

```bash
# Habilitar o add-on Prometheus do Minikube
minikube addons enable metrics-server
minikube addons enable prometheus
```

## 10. Conclusão

Você agora tem um sistema Paxos completo executando no Kubernetes! Esta configuração demonstra:

1. A implementação do algoritmo de consenso Paxos
2. A integração com o protocolo Gossip para descoberta de nós
3. O uso de uma arquitetura orientada a objetos para modularização
4. A implantação em uma plataforma de orquestração de contêineres moderna

Esta combinação oferece um sistema distribuído resiliente, escalável e de fácil manutenção.