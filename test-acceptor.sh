#!/bin/bash

# Script para testar o sistema diretamente via um acceptor
PROPOSAL_NUM=$(date +%s)00
ACCEPTOR_POD=$(kubectl get pods -n paxos -l app=acceptor1 -o jsonpath="{.items[0].metadata.name}")

echo "Enviando accept diretamente para acceptor1..."
kubectl exec -n paxos $ACCEPTOR_POD -- curl -s -X POST http://localhost:4001/accept \
  -H "Content-Type: application/json" \
  -d "{\"proposer_id\":1,\"proposal_number\":$PROPOSAL_NUM,\"is_leader_election\":false,\"value\":\"teste_direto\",\"client_id\":9}"

echo "Verificando se o valor foi aprendido pelo learner1..."
sleep 2
kubectl port-forward -n paxos svc/learner1 5001:5001 &
PORT_FWD_PID=$!
sleep 2
curl "http://localhost:5001/get-values"
kill $PORT_FWD_PID