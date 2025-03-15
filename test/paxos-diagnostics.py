#!/usr/bin/env python3
import os
import sys
import time
import json
import subprocess
import argparse
from concurrent.futures import ThreadPoolExecutor

class PaxosDiagnostics:
    """Tool to diagnose and fix issues with Paxos cluster in Kubernetes."""
    
    def __init__(self, namespace="paxos", verbose=False):
        self.namespace = namespace
        self.verbose = verbose
        self.pods = {}
        self.services = {}
        self.dns_issues = False
        self.endpoints_issues = False
        
    def print_header(self, message):
        """Print a formatted header."""
        print("\n" + "=" * 70)
        print(message.center(70))
        print("=" * 70)
        
    def log(self, message, level="INFO"):
        """Log a message with timestamp."""
        if level == "DEBUG" and not self.verbose:
            return
        
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {message}")
        
    def run_command(self, command, hide_output=False):
        """Run a shell command and return the output."""
        if self.verbose and not hide_output:
            self.log(f"Running command: {command}", "DEBUG")
            
        try:
            result = subprocess.run(
                command, 
                shell=True, 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0 and not hide_output:
                self.log(f"Command failed: {result.stderr}", "ERROR")
                return None
                
            return result.stdout.strip()
        except Exception as e:
            if not hide_output:
                self.log(f"Exception running command: {e}", "ERROR")
            return None
            
    def get_pods(self):
        """Get all pods in the namespace."""
        self.print_header("CHECKING PODS")
        
        command = f"kubectl get pods -n {self.namespace} -o json"
        output = self.run_command(command)
        
        if not output:
            self.log("Failed to get pods", "ERROR")
            return False
            
        try:
            pods_json = json.loads(output)
            
            if not pods_json.get('items'):
                self.log("No pods found in namespace", "ERROR")
                return False
                
            self.log(f"Found {len(pods_json['items'])} pods")
            
            # Process each pod
            for pod in pods_json['items']:
                name = pod['metadata']['name']
                status = pod['status']['phase']
                ready = False
                
                # Check if pod is ready
                if pod['status'].get('containerStatuses'):
                    ready = pod['status']['containerStatuses'][0].get('ready', False)
                
                # Get pod IP
                pod_ip = pod['status'].get('podIP', 'unknown')
                
                # Get labels
                labels = pod['metadata'].get('labels', {})
                app = labels.get('app', 'unknown')
                role = labels.get('role', 'unknown')
                
                self.pods[name] = {
                    'name': name,
                    'status': status,
                    'ready': ready,
                    'ip': pod_ip,
                    'app': app,
                    'role': role
                }
                
                ready_status = "READY" if ready else "NOT READY"
                self.log(f"Pod {name} ({role}): {status} / {ready_status} / IP: {pod_ip}")
            
            return True
        except Exception as e:
            self.log(f"Error processing pods: {e}", "ERROR")
            return False
            
    def get_services(self):
        """Get all services in the namespace."""
        self.print_header("CHECKING SERVICES")
        
        command = f"kubectl get services -n {self.namespace} -o json"
        output = self.run_command(command)
        
        if not output:
            self.log("Failed to get services", "ERROR")
            return False
            
        try:
            services_json = json.loads(output)
            
            if not services_json.get('items'):
                self.log("No services found in namespace", "ERROR")
                return False
                
            self.log(f"Found {len(services_json['items'])} services")
            
            # Process each service
            for service in services_json['items']:
                name = service['metadata']['name']
                service_type = service['spec']['type']
                cluster_ip = service['spec'].get('clusterIP', 'None')
                ports = service['spec'].get('ports', [])
                selector = service['spec'].get('selector', {})
                
                port_info = []
                for port in ports:
                    port_info.append(f"{port.get('name', 'unnamed')}:{port.get('port')}->{port.get('targetPort')}")
                
                self.services[name] = {
                    'name': name,
                    'type': service_type,
                    'cluster_ip': cluster_ip,
                    'ports': port_info,
                    'selector': selector
                }
                
                self.log(f"Service {name}: {service_type} / IP: {cluster_ip} / Ports: {', '.join(port_info)}")
            
            return True
        except Exception as e:
            self.log(f"Error processing services: {e}", "ERROR")
            return False
    
    def check_dns_resolution(self):
        """Check if DNS resolution is working properly."""
        self.print_header("CHECKING DNS RESOLUTION")
        
        # Create a test pod to run DNS queries
        self.log("Creating temporary DNS test pod...")
        create_pod_cmd = f"""
        kubectl run dns-test --namespace={self.namespace} --rm -i --restart=Never --image=busybox:1.28 -- nslookup kubernetes.default
        """
        dns_output = self.run_command(create_pod_cmd)
        
        if not dns_output or "server can't find" in dns_output:
            self.log("DNS resolution test failed", "ERROR")
            self.dns_issues = True
            self.log("Attempting to fix CoreDNS...")
            
            # Try to restart CoreDNS
            self.run_command("kubectl rollout restart deployment -n kube-system coredns")
            self.log("CoreDNS restarted. Wait a few minutes and try again.")
            return False
        else:
            self.log("DNS resolution is working correctly")
            
            # Test specific service resolution
            for service_name in ['proposer1', 'acceptor1']:
                if service_name in self.services:
                    test_cmd = f"""
                    kubectl run dns-test-{service_name} --namespace={self.namespace} --rm -i --restart=Never --image=busybox:1.28 -- \
                    nslookup {service_name}.{self.namespace}.svc.cluster.local
                    """
                    service_dns = self.run_command(test_cmd)
                    
                    if service_dns and "server can't find" not in service_dns:
                        self.log(f"Service {service_name} DNS resolution successful")
                    else:
                        self.log(f"Cannot resolve service {service_name}", "WARNING")
            
            return True
            
    def check_health_endpoints(self):
        """Check health endpoints for all pods."""
        self.print_header("CHECKING HEALTH ENDPOINTS")
        
        # Group pods by role
        pods_by_role = {}
        for pod_name, pod_info in self.pods.items():
            role = pod_info['role']
            if role not in pods_by_role:
                pods_by_role[role] = []
            pods_by_role[role].append(pod_info)
            
        # Check health for each pod
        healthy_pods = 0
        for role, pods in pods_by_role.items():
            self.log(f"Checking {len(pods)} {role} pods...")
            
            for pod in pods:
                pod_name = pod['name']
                
                # Skip pods that aren't ready
                if not pod['ready']:
                    self.log(f"Skipping {pod_name} as it's not ready")
                    continue
                    
                # Try to access the health endpoint
                cmd = f"kubectl exec -n {self.namespace} {pod_name} -- curl -s http://localhost:8000/health"
                health_output = self.run_command(cmd)
                
                if health_output:
                    try:
                        health_json = json.loads(health_output)
                        if health_json.get('status') == 'healthy':
                            self.log(f"{pod_name}: Health endpoint OK")
                            healthy_pods += 1
                        else:
                            self.log(f"{pod_name}: Health endpoint returned: {health_output}", "WARNING")
                    except:
                        self.log(f"{pod_name}: Invalid JSON from health endpoint: {health_output}", "WARNING")
                else:
                    self.log(f"{pod_name}: Health endpoint not responding", "WARNING")
        
        if healthy_pods == 0:
            self.log("No pods have working health endpoints", "ERROR")
            self.endpoints_issues = True
            return False
        else:
            self.log(f"{healthy_pods}/{len(self.pods)} pods have working health endpoints")
            return True
            
    def check_inter_pod_communication(self):
        """Check if pods can communicate with each other."""
        self.print_header("CHECKING INTER-POD COMMUNICATION")
        
        # Get a client pod for testing
        client_pods = [p for _, p in self.pods.items() if p['role'] == 'client' and p['ready']]
        if not client_pods:
            self.log("No ready client pods found for testing", "ERROR")
            return False
            
        test_pod = client_pods[0]
        self.log(f"Using {test_pod['name']} for communication tests")
        
        # Check connectivity to each service
        for service_name, service_info in self.services.items():
            if service_name.endswith('external'):
                continue  # Skip external services
                
            for port_info in service_info['ports']:
                if 'api' in port_info:
                    port = port_info.split(':')[1].split('->')[0]
                    cmd = f"kubectl exec -n {self.namespace} {test_pod['name']} -- curl -s --connect-timeout 5 http://{service_name}:{port}/health"
                    output = self.run_command(cmd, hide_output=True)
                    
                    if output:
                        self.log(f"Connection to {service_name}:{port} successful")
                    else:
                        self.log(f"Failed to connect to {service_name}:{port}", "WARNING")
        
        return True
        
    def fix_minikube_dns(self):
        """Fix common Minikube DNS issues."""
        self.print_header("FIXING MINIKUBE DNS")
        
        self.log("Enabling Minikube DNS addon...")
        self.run_command("minikube addons enable dns")
        
        self.log("Restarting CoreDNS...")
        self.run_command("kubectl rollout restart deployment -n kube-system coredns")
        
        self.log("Wait for CoreDNS to restart...")
        self.run_command("kubectl rollout status deployment/coredns -n kube-system")
        
        return True
        
    def restart_paxos_system(self):
        """Restart all Paxos components in the correct order."""
        self.print_header("RESTARTING PAXOS SYSTEM")
        
        # Restart in order: proposers, acceptors, learners, clients
        roles_order = ['proposer', 'acceptor', 'learner', 'client']
        
        for role in roles_order:
            self.log(f"Restarting {role}s...")
            role_pods = [p for _, p in self.pods.items() if p['role'] == role]
            
            for pod in role_pods:
                app_name = pod['app']
                self.log(f"Restarting deployment {app_name}...")
                self.run_command(f"kubectl rollout restart deployment/{app_name} -n {self.namespace}")
                
            # Wait for pods to be ready before continuing to next role
            self.log(f"Waiting for {role}s to be ready...")
            for pod in role_pods:
                app_name = pod['app']
                self.run_command(f"kubectl rollout status deployment/{app_name} -n {self.namespace}")
                
            self.log(f"All {role}s restarted")
                
        return True
        
    def execute_leader_election(self):
        """Force a leader election."""
        self.print_header("EXECUTING LEADER ELECTION")
        
        # Find proposer1 pod
        proposer1_pods = [p for _, p in self.pods.items() if p['app'] == 'proposer1' and p['ready']]
        if not proposer1_pods:
            self.log("Proposer1 pod not found or not ready", "ERROR")
            return False
            
        proposer1 = proposer1_pods[0]
        self.log(f"Using {proposer1['name']} to initiate leader election")
        
        # Send a direct election request
        cmd = f"kubectl exec -n {self.namespace} {proposer1['name']} -- curl -s -X POST http://localhost:3001/propose -H 'Content-Type: application/json' -d '{{\"value\":\"leader_election_trigger\", \"client_id\":9}}'"
        output = self.run_command(cmd)
        
        if output:
            self.log(f"Election request sent: {output}")
            self.log("Waiting 10 seconds for leader election process...")
            time.sleep(10)
            
            # Check if leader was elected
            cmd = f"kubectl exec -n {self.namespace} {proposer1['name']} -- curl -s http://localhost:3001/view-logs"
            output = self.run_command(cmd)
            
            if output:
                try:
                    logs_json = json.loads(output)
                    leader_id = logs_json.get('current_leader')
                    if leader_id and leader_id != "None":
                        self.log(f"Leader elected: Proposer {leader_id}")
                        return True
                    else:
                        self.log("No leader elected yet", "WARNING")
                except:
                    self.log(f"Invalid JSON from view-logs: {output}", "WARNING")
            else:
                self.log("Failed to get leader information", "ERROR")
        else:
            self.log("Failed to send election request", "ERROR")
            
        return False
        
    def diagnose_and_fix(self):
        """Run all diagnostics and attempt to fix issues."""
        self.print_header("STARTING PAXOS SYSTEM DIAGNOSTICS")
        
        # Check pods
        if not self.get_pods():
            self.log("Failed to get pod information, cannot continue", "ERROR")
            return False
            
        # Check services
        if not self.get_services():
            self.log("Failed to get service information, cannot continue", "ERROR")
            return False
            
        # Check DNS resolution
        dns_ok = self.check_dns_resolution()
        
        # Check health endpoints 
        health_ok = self.check_health_endpoints()
        
        # Check inter-pod communication
        comm_ok = self.check_inter_pod_communication()
        
        # Report issues
        self.print_header("DIAGNOSTIC SUMMARY")
        
        issues_found = False
        if not dns_ok:
            self.log("❌ DNS resolution issues detected", "ERROR")
            issues_found = True
        else:
            self.log("✅ DNS resolution working correctly")
            
        if not health_ok:
            self.log("❌ Health endpoint issues detected", "ERROR")
            issues_found = True
        else:
            self.log("✅ Health endpoints working correctly")
            
        if not comm_ok:
            self.log("❌ Inter-pod communication issues detected", "ERROR")
            issues_found = True
        else:
            self.log("✅ Inter-pod communication working correctly")
            
        # Fix issues if found
        if issues_found:
            self.print_header("APPLYING FIXES")
            
            if not dns_ok:
                self.fix_minikube_dns()
                
            self.log("Restarting Paxos system in the correct order...")
            self.restart_paxos_system()
            
            self.log("Waiting 20 seconds for system to stabilize...")
            time.sleep(20)
            
            # Force leader election
            self.execute_leader_election()
        else:
            self.log("No significant issues found, system should be operational")
            
        return True
        
def main():
    parser = argparse.ArgumentParser(description="Diagnose and fix issues with Paxos in Kubernetes")
    parser.add_argument("--namespace", "-n", default="paxos", help="Kubernetes namespace")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose output")
    args = parser.parse_args()
    
    diagnostics = PaxosDiagnostics(namespace=args.namespace, verbose=args.verbose)
    diagnostics.diagnose_and_fix()

if __name__ == "__main__":
    main()
