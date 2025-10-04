all:
  vars:
    # Global SSH configuration - update this path to match your environment
    ssh_private_key_file: "${ssh_key}"
    bastion_user: "${aws_ssh_user}"
    bastion_host: "${bastion_host}"
%{if registry_host != null}
    registry_host: "${registry_host}"
%{endif}
  children:
    bastion:
      hosts:
        bastion-node:
          ansible_host: "{{ bastion_host }}"
          ansible_user: "{{ bastion_user }}"
          ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
%{if registry_host != null}

    registry:
      hosts:
        registry-node:
          ansible_host: "{{ registry_host }}"
          ansible_user: "{{ bastion_user }}"
          ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

%{endif}
    airgap_nodes:
      vars:
        # SSH proxy configuration for all airgap nodes
        ansible_user: "ubuntu"
        ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
        ansible_ssh_common_args: "-o ProxyCommand='ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i {{ ssh_private_key_file }} {{ bastion_user }}@{{ bastion_host }}'"
        bastion_ip: "{{ bastion_host }}"

      children:
        rke2_servers:
          hosts:
%{ for idx, ip in rancher_server_ips ~}
%{ if idx == 0 ~}
            rke2-server-${idx}:
              ansible_host: "${ip}"
%{ endif ~}
%{ endfor ~}

        rke2_agents:
          hosts:
%{ for idx, ip in rancher_server_ips ~}
%{ if idx > 0 ~}
            rke2-agent-${idx - 1}:
              ansible_host: "${ip}"
%{ endif ~}
%{ endfor ~}
