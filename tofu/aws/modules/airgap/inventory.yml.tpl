all:
  vars:
    # Global SSH configuration - update this path to match your environment
    ssh_private_key_file: "${ssh_key}"
    bastion_user: "${aws_ssh_user}"
    bastion_host: "${bastion_host}"
    registry_host: "${registry_host}"
    
  children:
    bastion:
      hosts:
        bastion-node:
          ansible_host: "{{ bastion_host }}"
          ansible_user: "{{ bastion_user }}"
          ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
          
    registry:
      hosts:
        registry-node:
          ansible_host: "{{ registry_host }}"
          ansible_user: "{{ bastion_user }}"
          ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
          
    airgap_nodes:
      vars:
        # SSH proxy configuration for all airgap nodes
        ansible_user: "ubuntu"
        ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
        ansible_ssh_common_args: "-o ProxyCommand='ssh -W %h:%p -i {{ ssh_private_key_file }} {{ bastion_user }}@{{ bastion_host }}' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        bastion_ip: "{{ bastion_host }}"
        
      hosts:
%{ for idx, ip in rancher_server_ips ~}
        rke2-server-${idx}:
          ansible_host: "${ip}"
%{ endfor ~}