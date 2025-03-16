import json
import time
import threading
import logging
import random
import requests
from flask import request, jsonify

from base_node import BaseNode

class Proposer(BaseNode):
    """
    Implementação do nó Proposer no algoritmo Paxos.
    Responsável por propor valores e coordenar o consenso.
    """
    
    def __init__(self, app=None):
        """
        Inicializa o nó Proposer.
        """
        super().__init__(app)
        
        # Estado específico do proposer
        self.proposal_counter = 0
        self.in_election = False
        self.election_timeout = 5  # segundos
        
        # Valores para detecção de falha e recuperação
        self.heartbeat_interval = 2  # segundos para enviar heartbeat
        self.leader_timeout = 8  # segundos sem heartbeat para considerar o líder como falho
        self.last_heartbeat_received = 0  # timestamp do último heartbeat recebido
        self.backoff_time = 0  # tempo de backoff para evitar tempestade de eleições
        
        # Valores de proposta atual
        self.current_proposal_number = 0
        self.proposed_value = None
        self.proposal_accepted_count = 0
        self.waiting_for_acceptor_response = False
    
    def _get_default_port(self):
        """Porta padrão para proposers"""
        return 3000
    
    def _register_routes(self):
        """Registrar rotas específicas do proposer"""
        @self.app.route('/propose', methods=['POST'])
        def propose():
            """Receber proposta de um cliente"""
            return self._handle_propose(request.json)
        
        @self.app.route('/heartbeat', methods=['POST'])
        def heartbeat():
            """Receber heartbeat do líder"""
            return self._handle_heartbeat(request.json)
    
    def _start_threads(self):
        """Iniciar threads específicas do proposer"""
        # Thread de verificação de líder
        threading.Thread(target=self._check_leader, daemon=True).start()
        
        # Thread de heartbeat de líder
        threading.Thread(target=self._leader_heartbeat, daemon=True).start()
    
    def _handle_heartbeat(self, data):
        """
        Manipula heartbeats recebidos do líder
        
        Args:
            data (dict): Dados do heartbeat
        
        Returns:
            Response: Resposta HTTP
        """
        leader_id = data.get('leader_id')
        timestamp = data.get('timestamp', time.time())
        
        if leader_id:
            self.last_heartbeat_received = timestamp
            self.logger.debug(f"Heartbeat recebido do líder {leader_id}")
            
            # Atualizar o líder no gossip se necessário
            current_leader = self.gossip.get_leader()
            if current_leader != leader_id:
                self.gossip.set_leader(leader_id)
            
            return jsonify({"status": "acknowledged"}), 200
        
        return jsonify({"error": "Invalid heartbeat data"}), 400
    
    def _handle_propose(self, data):
        """
        Manipula requisições de proposta de clientes.
        
        Args:
            data (dict): Dados da proposta do cliente
        
        Returns:
            Response: Resposta HTTP
        """
        # Verificar se este nó é o líder ou se estamos em bootstrap (sem líder)
        current_leader = self.gossip.get_leader()
        is_leader = current_leader is not None and int(current_leader) == self.node_id
        bootstrap_mode = current_leader is None  # Permitir proposta quando não há líder
        
        # Se não for líder e não estiver em bootstrap, redirecionar
        if not is_leader and not bootstrap_mode:
            # Redirecionar para o líder atual, se conhecido
            if current_leader:
                try:
                    leader_info = self.gossip.get_node_info(str(current_leader))
                    if leader_info:
                        leader_url = f"http://{leader_info['address']}:{leader_info['port']}/propose"
                        try:
                            response = requests.post(leader_url, json=data, timeout=5)
                            return response.content, response.status_code
                        except Exception as e:
                            self.logger.error(f"Erro ao redirecionar para líder: {e}")
                except Exception as e:
                    self.logger.error(f"Erro ao obter informações do líder: {e}")
            
            return jsonify({"error": "Not the leader", "current_leader": current_leader}), 403
        
        value = data.get('value')
        client_id = data.get('client_id')
        
        if not value:
            return jsonify({"error": "Value required"}), 400
        
        with self.lock:
            if self.waiting_for_acceptor_response:
                return jsonify({"error": "Already processing a proposal"}), 429
            
            self.waiting_for_acceptor_response = True
            self.proposed_value = value
            self.proposal_counter += 1
            self.current_proposal_number = self.proposal_counter * 100 + self.node_id
            self.proposal_accepted_count = 0
        
        # Log diferente dependendo do modo
        if bootstrap_mode:
            self.logger.info(f"Recebida proposta em modo bootstrap do cliente {client_id}: {value}")
        else:
            self.logger.info(f"Recebida proposta do cliente {client_id}: {value}")
        
        # Enviar prepare para todos os acceptors
        try:
            acceptors = self.gossip.get_nodes_by_role('acceptor')
            quorum_size = len(acceptors) // 2 + 1
            
            if quorum_size == 0:
                with self.lock:
                    self.waiting_for_acceptor_response = False
                return jsonify({"error": "No acceptors available"}), 503
            
            self.logger.info(f"Enviando prepare para {len(acceptors)} acceptors")
            
            for acceptor_id, acceptor in acceptors.items():
                try:
                    acceptor_url = f"http://{acceptor['address']}:{acceptor['port']}/prepare"
                    prepare_data = {
                        "proposer_id": self.node_id,
                        "proposal_number": self.current_proposal_number,
                        "is_leader_election": False
                    }
                    
                    threading.Thread(target=self._send_client_prepare, args=(
                        acceptor_url, prepare_data, quorum_size, value, client_id)).start()
                except Exception as e:
                    self.logger.error(f"Erro ao enviar prepare para acceptor {acceptor_id}: {e}")
            
            return jsonify({"status": "proposal received", "proposal_number": self.current_proposal_number}), 200
        except Exception as e:
            self.logger.error(f"Erro ao processar proposta: {e}")
            with self.lock:
                self.waiting_for_acceptor_response = False
            return jsonify({"error": str(e)}), 500
    
    def _check_leader(self):
        """Verificar se há um líder ativo e iniciar eleição se necessário"""
        while True:
            try:
                current_leader = self.gossip.get_leader()
                current_time = time.time()
                
                with self.lock:
                    # Se não houver líder
                    if current_leader is None:
                        # Se não estiver em eleição e já passou o tempo de backoff
                        if not self.in_election and current_time > self.backoff_time:
                            self.logger.info("Sem líder detectado, iniciando eleição")
                            self._start_election()
                    # Se este nó for o líder
                    elif int(current_leader) == self.node_id:
                        self.gossip.update_local_metadata({
                            "is_leader": True,
                            "last_heartbeat": current_time
                        })
                        self.logger.debug("Este nó é o líder atual")
                    # Se outro nó for o líder, verificar timeout de heartbeat
                    else:
                        leader_info = self.gossip.get_node_info(str(current_leader))
                        if leader_info and leader_info.get('metadata'):
                            last_heartbeat = leader_info.get('metadata').get('last_heartbeat', 0)
                            
                            # Se o último heartbeat foi há muito tempo, considerar o líder como falho
                            if current_time - last_heartbeat > self.leader_timeout:
                                self.logger.warning(f"Timeout do líder {current_leader}. Iniciando nova eleição.")
                                # Adicionar backoff aleatório para evitar tempestade de eleições
                                self.backoff_time = current_time + random.uniform(0.5, 2.0)
                                self._start_election()
                        
                        # Atualizar status de líder local
                        is_leader = self.gossip.get_node_info(str(self.node_id))
                        if is_leader and is_leader.get('metadata', {}).get('is_leader', False):
                            self.gossip.update_local_metadata({"is_leader": False})
            except Exception as e:
                self.logger.error(f"Erro ao verificar líder: {e}")
            
            time.sleep(2)  # Verificar a cada 2 segundos
    
    def _leader_heartbeat(self):
        """Enviar heartbeat como líder para os outros nós"""
        while True:
            # Verificar se este nó é o líder
            is_leader = False
            current_leader = self.gossip.get_leader()
            current_time = time.time()
            
            if current_leader is not None and int(current_leader) == self.node_id:
                is_leader = True
                self.logger.debug("Enviando heartbeat de líder")
                
                # Atualizar metadata no Gossip
                self.gossip.update_local_metadata({
                    "is_leader": True,
                    "last_heartbeat": current_time
                })
                
                # Enviar heartbeat diretamente para todos os proposers
                try:
                    proposers = self.gossip.get_nodes_by_role('proposer')
                    for proposer_id, proposer in proposers.items():
                        if proposer_id != str(self.node_id):  # Não enviar para si mesmo
                            try:
                                proposer_url = f"http://{proposer['address']}:{proposer['port']}/heartbeat"
                                heartbeat_data = {
                                    "leader_id": self.node_id,
                                    "timestamp": current_time
                                }
                                
                                # Usar thread para não bloquear
                                threading.Thread(target=lambda u, d: requests.post(u, json=d, timeout=2), 
                                               args=(proposer_url, heartbeat_data)).start()
                            except Exception as e:
                                self.logger.debug(f"Erro ao enviar heartbeat para proposer {proposer_id}: {e}")
                except Exception as e:
                    self.logger.error(f"Erro ao enviar heartbeats: {e}")
            
            # Tempo de espera adaptativo
            sleep_time = self.heartbeat_interval if is_leader else 5
            time.sleep(sleep_time)
    
    def _start_election(self):
        """Iniciar uma eleição para líder"""
        with self.lock:
            if self.in_election:
                return
            
            self.in_election = True
            # Gerar número de proposta único: timestamp * 100 + ID
            proposal_counter = int(time.time()) % 10000
            self.current_proposal_number = proposal_counter * 100 + self.node_id
            self.proposal_accepted_count = 0
        
        self.logger.info(f"Iniciando eleição com proposta número {self.current_proposal_number}")
        
        # Enviar mensagem prepare para todos os acceptors
        try:
            acceptors = self.gossip.get_nodes_by_role('acceptor')
            quorum_size = len(acceptors) // 2 + 1
            
            if quorum_size == 0:
                self.logger.warning("Nenhum acceptor disponível para eleição")
                with self.lock:
                    self.in_election = False
                return
            
            self.logger.info(f"Enviando prepare para {len(acceptors)} acceptors (quorum: {quorum_size})")
            
            # Implementar timeout para a eleição
            election_start_time = time.time()
            election_timeout = self.election_timeout
            
            # Lista para armazenar threads de prepare
            prepare_threads = []
            
            for acceptor_id, acceptor in acceptors.items():
                try:
                    acceptor_url = f"http://{acceptor['address']}:{acceptor['port']}/prepare"
                    data = {
                        "proposer_id": self.node_id,
                        "proposal_number": self.current_proposal_number,
                        "is_leader_election": True
                    }
                    
                    thread = threading.Thread(target=self._send_prepare, args=(acceptor_url, data, quorum_size))
                    prepare_threads.append(thread)
                    thread.start()
                except Exception as e:
                    self.logger.error(f"Erro ao enviar prepare para acceptor {acceptor_id}: {e}")
            
            # Aguardar conclusão das threads ou timeout
            end_time = time.time() + election_timeout
            for thread in prepare_threads:
                timeout = max(0.1, end_time - time.time())
                thread.join(timeout=timeout)
            
            # Verificar se a eleição foi bem-sucedida
            with self.lock:
                if self.in_election:
                    # Se não conseguimos eleger um líder dentro do timeout, abortar a eleição
                    if time.time() > election_start_time + election_timeout:
                        self.logger.warning("Timeout na eleição de líder. Tentando novamente mais tarde.")
                        self.in_election = False
                        # Definir backoff para evitar tempestade de eleições
                        self.backoff_time = time.time() + random.uniform(2, 5)
                        
        except Exception as e:
            self.logger.error(f"Erro ao iniciar eleição: {e}")
            with self.lock:
                self.in_election = False
    
    def _send_prepare(self, url, data, quorum_size):
        """
        Enviar mensagem prepare para um acceptor
        
        Args:
            url (str): URL do acceptor
            data (dict): Dados para enviar
            quorum_size (int): Tamanho do quórum necessário
        """
        # Implementar retry com backoff exponencial
        max_retries = 3
        base_timeout = 1.0
        
        for retry in range(max_retries):
            try:
                timeout = base_timeout * (2 ** retry)  # Backoff exponencial
                response = requests.post(url, json=data, timeout=timeout)
                
                if response.status_code == 200:
                    result = response.json()
                    if result.get("status") == "promise":
                        with self.lock:
                            self.proposal_accepted_count += 1
                            self.logger.info(f"Recebido promise: {self.proposal_accepted_count}/{quorum_size}")
                            
                            # Se atingir o quórum, torna-se líder
                            if self.proposal_accepted_count >= quorum_size and self.in_election:
                                self.in_election = False
                                self.logger.info("Quórum atingido! Tornando-se líder")
                                
                                # Atualizar informação de líder no Gossip
                                self.gossip.set_leader(self.node_id)
                                
                                # Enviar mensagem accept para todos os acceptors
                                try:
                                    acceptors = self.gossip.get_nodes_by_role('acceptor')
                                    for acceptor_id, acceptor in acceptors.items():
                                        acceptor_url = f"http://{acceptor['address']}:{acceptor['port']}/accept"
                                        accept_data = {
                                            "proposer_id": self.node_id,
                                            "proposal_number": self.current_proposal_number,
                                            "is_leader_election": True,
                                            "value": f"leader:{self.node_id}"
                                        }
                                        
                                        try:
                                            requests.post(acceptor_url, json=accept_data, timeout=5)
                                        except Exception as e:
                                            self.logger.error(f"Erro ao enviar accept para acceptor {acceptor_id}: {e}")
                                except Exception as e:
                                    self.logger.error(f"Erro ao enviar accepts após eleição: {e}")
                    else:
                        self.logger.info(f"Acceptor rejeitou proposta: {result.get('message')}")
                else:
                    self.logger.error(f"Erro ao enviar prepare: {response.text}")
                
                # Se obtivemos uma resposta, saímos do retry
                break
            except Exception as e:
                self.logger.error(f"Erro ao enviar prepare (tentativa {retry+1}/{max_retries}): {e}")
                # Esperar antes de tentar novamente (com jitter para evitar sincronização)
                if retry < max_retries - 1:
                    jitter = random.uniform(0.1, 0.3)
                    time.sleep(base_timeout * (2 ** retry) + jitter)
    
    def _send_client_prepare(self, acceptor_url, prepare_data, quorum_size, value, client_id):
        """
        Enviar mensagem prepare para um acceptor (para proposta de cliente)
        
        Args:
            acceptor_url (str): URL do acceptor
            prepare_data (dict): Dados do prepare
            quorum_size (int): Tamanho do quórum necessário
            value (str): Valor proposto
            client_id (int): ID do cliente
        """
        # Implementar retry com backoff
        max_retries = 3
        base_timeout = 1.0
        
        for retry in range(max_retries):
            try:
                timeout = base_timeout * (2 ** retry)  # Backoff exponencial
                response = requests.post(acceptor_url, json=prepare_data, timeout=timeout)
                
                if response.status_code == 200:
                    result = response.json()
                    if result.get("status") == "promise":
                        with self.lock:
                            self.proposal_accepted_count += 1
                            self.logger.info(f"Recebido promise para proposta do cliente: {self.proposal_accepted_count}/{quorum_size}")
                            
                            # Se atingir o quórum, enviar accept
                            if self.proposal_accepted_count >= quorum_size and self.waiting_for_acceptor_response:
                                self.logger.info("Quórum atingido para proposta do cliente! Enviando accepts")
                                
                                # Enviar mensagem accept para todos os acceptors
                                try:
                                    acceptors = self.gossip.get_nodes_by_role('acceptor')
                                    for acceptor_id, acceptor in acceptors.items():
                                        acceptor_url = f"http://{acceptor['address']}:{acceptor['port']}/accept"
                                        accept_data = {
                                            "proposer_id": self.node_id,
                                            "proposal_number": self.current_proposal_number,
                                            "is_leader_election": False,
                                            "value": value,
                                            "client_id": client_id
                                        }
                                        
                                        try:
                                            requests.post(acceptor_url, json=accept_data, timeout=5)
                                        except Exception as e:
                                            self.logger.error(f"Erro ao enviar accept para acceptor {acceptor_id}: {e}")
                                    
                                    # Reiniciar estado
                                    self.waiting_for_acceptor_response = False
                                except Exception as e:
                                    self.logger.error(f"Erro ao enviar accepts após quórum: {e}")
                                    self.waiting_for_acceptor_response = False
                    else:
                        self.logger.info(f"Acceptor rejeitou proposta do cliente: {result.get('message')}")
                        with self.lock:
                            # Se algum acceptor rejeitar, precisamos finalizar
                            if self.waiting_for_acceptor_response:
                                self.waiting_for_acceptor_response = False
                else:
                    self.logger.error(f"Erro ao enviar prepare para proposta do cliente: {response.text}")
                    with self.lock:
                        if self.waiting_for_acceptor_response:
                            self.waiting_for_acceptor_response = False
                
                # Se obtivemos uma resposta, saímos do retry
                break
            except Exception as e:
                self.logger.error(f"Erro ao enviar prepare para proposta do cliente (tentativa {retry+1}/{max_retries}): {e}")
                if retry < max_retries - 1:
                    # Esperar antes de tentar novamente (com jitter para evitar sincronização)
                    jitter = random.uniform(0.1, 0.3)
                    time.sleep(base_timeout * (2 ** retry) + jitter)
                else:
                    with self.lock:
                        if self.waiting_for_acceptor_response:
                            self.waiting_for_acceptor_response = False
    
    def _handle_view_logs(self):
        """Manipulador para a rota view-logs"""
        current_leader = self.gossip.get_leader()
        is_leader = current_leader is not None and int(current_leader) == self.node_id
        
        acceptors = self.gossip.get_nodes_by_role('acceptor')
        learners = self.gossip.get_nodes_by_role('learner')
        
        return jsonify({
            "id": self.node_id,
            "role": self.node_role,
            "is_leader": is_leader,
            "current_leader": current_leader,
            "in_election": self.in_election,
            "proposal_counter": self.proposal_counter,
            "acceptors_count": len(acceptors),
            "learners_count": len(learners),
            "known_nodes_count": len(self.gossip.get_all_nodes()),
            "current_proposal": {
                "number": self.current_proposal_number,
                "value": self.proposed_value,
                "accepted_count": self.proposal_accepted_count,
                "waiting_for_response": self.waiting_for_acceptor_response
            }
        }), 200

# Para uso como aplicação independente
if __name__ == '__main__':
    proposer = Proposer()
    proposer.start()