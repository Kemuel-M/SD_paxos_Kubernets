#!/usr/bin/env python3
import subprocess
import json
import sys
import time
import argparse

class PaxosK8sClient:
    """Cliente para interagir com o sistema Paxos em Kubernetes."""
    
    def __init__(self, namespace="paxos"):
        """Inicializa o cliente."""
        self.namespace = namespace
    
    def _run_kubectl_cmd(self, cmd):
        """Executa um comando kubectl e retorna a saída."""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"Erro ao executar comando: {result.stderr}")
                return None
            return result.stdout.strip()
        except Exception as e:
            print(f"Erro: {e}")
            return None
    
    def _exec_in_pod(self, pod_selector, container_cmd):
        """Executa um comando dentro de um pod."""
        # Obter o nome do pod
        pod_name = self._run_kubectl_cmd(
            f"kubectl get pods -n {self.namespace} -l {pod_selector} -o jsonpath='{{.items[0].metadata.name}}'"
        )
        
        if not pod_name:
            print(f"Pod com seletor '{pod_selector}' não encontrado!")
            return None
        
        # Executar o comando no pod
        return self._run_kubectl_cmd(
            f"kubectl exec -n {self.namespace} {pod_name} -- bash -c \"{container_cmd}\""
        )
    
    def write_value(self, value):
        """Envia um valor para o sistema Paxos."""
        print(f"Enviando valor '{value}' para o sistema Paxos...")
        
        # Escapar aspas duplas no valor
        escaped_value = value.replace('"', '\\"')
        
        # Enviar valor usando curl dentro do pod do cliente
        response = self._exec_in_pod(
            "app=client1",
            f"curl -s -X POST http://client1:6001/send -H 'Content-Type: application/json' -d '{{\"value\":\"{escaped_value}\"}}'"
        )
        
        if response:
            try:
                result = json.loads(response)
                print(f"Resposta: {json.dumps(result, indent=2)}")
                return result
            except json.JSONDecodeError:
                print(f"Resposta não-JSON recebida: {response}")
                return response
        
        return None
    
    def direct_write(self, value):
        """Envia um valor diretamente para o proposer."""
        print(f"Enviando valor '{value}' diretamente para o proposer...")
        
        # Escapar aspas duplas no valor
        escaped_value = value.replace('"', '\\"')
        
        # Enviar valor diretamente usando curl dentro do pod do proposer
        response = self._exec_in_pod(
            "app=proposer1",
            f"curl -s -X POST http://proposer1:3001/propose -H 'Content-Type: application/json' -d '{{\"value\":\"{escaped_value}\", \"client_id\":9}}'"
        )
        
        if response:
            try:
                result = json.loads(response)
                print(f"Resposta: {json.dumps(result, indent=2)}")
                return result
            except json.JSONDecodeError:
                print(f"Resposta não-JSON recebida: {response}")
                return response
        
        return None
    
    def read_values(self):
        """Lê valores do sistema Paxos."""
        print("Lendo valores do sistema Paxos...")
        
        # Ler valores usando curl dentro do pod do cliente
        response = self._exec_in_pod(
            "app=client1",
            "curl -s http://client1:6001/read"
        )
        
        if response:
            try:
                result = json.loads(response)
                values = result.get("values", [])
                print(f"Valores lidos ({len(values)}):")
                for i, value in enumerate(values):
                    print(f"{i+1}. {value}")
                return values
            except json.JSONDecodeError:
                print(f"Resposta não-JSON recebida: {response}")
                return response
        
        return None
    
    def get_responses(self):
        """Obtém respostas recebidas pelo cliente."""
        print("Obtendo respostas do cliente...")
        
        # Obter respostas usando curl dentro do pod do cliente
        response = self._exec_in_pod(
            "app=client1",
            "curl -s http://client1:6001/get-responses"
        )
        
        if response:
            try:
                result = json.loads(response)
                responses = result.get("responses", [])
                print(f"Respostas recebidas ({len(responses)}):")
                for i, resp in enumerate(responses):
                    print(f"{i+1}. Proposta {resp.get('proposal_number')}: '{resp.get('value')}' do learner {resp.get('learner_id')}")
                    print(f"   Aprendido em: {resp.get('learned_at')}, Recebido em: {resp.get('received_at')}")
                return responses
            except json.JSONDecodeError:
                print(f"Resposta não-JSON recebida: {response}")
                return response
        
        return None
    
    def get_client_status(self):
        """Obtém o status do cliente."""
        print("Obtendo status do cliente...")
        
        # Obter status usando curl dentro do pod do cliente
        response = self._exec_in_pod(
            "app=client1",
            "curl -s http://client1:6001/view-logs"
        )
        
        if response:
            try:
                result = json.loads(response)
                print(f"Status do cliente: {json.dumps(result, indent=2)}")
                return result
            except json.JSONDecodeError:
                print(f"Resposta não-JSON recebida: {response}")
                return response
        
        return None
    
    def get_proposer_status(self):
        """Obtém o status do proposer."""
        print("Obtendo status do proposer...")
        
        # Obter status usando curl dentro do pod do proposer
        response = self._exec_in_pod(
            "app=proposer1",
            "curl -s http://proposer1:3001/view-logs"
        )
        
        if response:
            try:
                result = json.loads(response)
                print(f"Status do proposer: {json.dumps(result, indent=2)}")
                return result
            except json.JSONDecodeError:
                print(f"Resposta não-JSON recebida: {response}")
                return response
        
        return None
    
    def get_system_status(self):
        """Obtém o status geral do sistema."""
        print("Obtendo status do sistema Paxos...")
        
        # Verificar pods em execução
        pods = self._run_kubectl_cmd(f"kubectl get pods -n {self.namespace} -o wide")
        print("Pods em execução:")
        print(pods)
        
        # Obter status dos componentes principais
        self.get_proposer_status()
        self.get_client_status()
        
        return pods
    
    def monitor_system(self, duration=60, interval=5):
        """Monitora o sistema por um período."""
        print(f"Monitorando o sistema por {duration} segundos (a cada {interval} segundos)...")
        
        end_time = time.time() + duration
        while time.time() < end_time:
            self.get_proposer_status()
            self.get_client_status()
            
            # Esperar pelo próximo ciclo
            remaining = end_time - time.time()
            if remaining <= 0:
                break
            sleep_time = min(interval, remaining)
            time.sleep(sleep_time)
            print("\n--- Nova verificação ---\n")

def parse_args():
    """Analisa os argumentos da linha de comando."""
    parser = argparse.ArgumentParser(description='Cliente para interagir com o sistema Paxos em Kubernetes')
    
    # Subcomandos
    subparsers = parser.add_subparsers(dest='command', help='Comandos disponíveis')
    
    # Comando write
    write_parser = subparsers.add_parser('write', help='Enviar um valor para o sistema')
    write_parser.add_argument('value', help='Valor a ser enviado')
    
    # Comando direct-write
    direct_write_parser = subparsers.add_parser('direct-write', help='Enviar um valor diretamente para o proposer')
    direct_write_parser.add_argument('value', help='Valor a ser enviado')
    
    # Comando read
    subparsers.add_parser('read', help='Ler valores do sistema')
    
    # Comando responses
    subparsers.add_parser('responses', help='Ver respostas recebidas pelo cliente')
    
    # Comando status
    subparsers.add_parser('status', help='Ver status do sistema')
    
    # Comando monitor
    monitor_parser = subparsers.add_parser('monitor', help='Monitorar o sistema por um período')
    monitor_parser.add_argument('--duration', type=int, default=60, help='Duração em segundos (padrão: 60)')
    monitor_parser.add_argument('--interval', type=int, default=5, help='Intervalo em segundos (padrão: 5)')
    
    # Namespace comum para todos os comandos
    parser.add_argument('--namespace', '-n', default='paxos', help='Namespace Kubernetes (padrão: paxos)')
    
    return parser.parse_args()

def main():
    """Função principal."""
    args = parse_args()
    
    # Criar cliente Paxos
    client = PaxosK8sClient(namespace=args.namespace)
    
    # Executar o comando especificado
    if args.command == 'write':
        client.write_value(args.value)
    elif args.command == 'direct-write':
        client.direct_write(args.value)
    elif args.command == 'read':
        client.read_values()
    elif args.command == 'responses':
        client.get_responses()
    elif args.command == 'status':
        client.get_system_status()
    elif args.command == 'monitor':
        client.monitor_system(duration=args.duration, interval=args.interval)
    else:
        print("Comando não especificado. Use --help para ver os comandos disponíveis.")

if __name__ == '__main__':
    main()
