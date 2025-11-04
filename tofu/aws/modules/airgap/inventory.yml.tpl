all:
  vars:
    # Global SSH configuration - update this path to match your environment
    ssh_private_key_file: "${ssh_key}"
    bastion_user: "${aws_ssh_user}"
    bastion_host: "${bastion_host}"
    external_lb_hostname: "${external_lb_hostname}"
    internal_lb_hostname: "${internal_lb_hostname}"
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
        ansible_user: "${aws_ssh_user}"
        ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
        ansible_ssh_common_args: "-o ProxyCommand='ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i {{ ssh_private_key_file }} {{ bastion_user }}@{{ bastion_host }}'"
        bastion_ip: "{{ bastion_host }}"
      children:
%{for name, addresses in group_addresses~}
        ${name}:
          hosts:
%{for j in range(length(addresses))~}
            ${name}_node_${j+1}:
              ansible_host: "${addresses[j]}"
%{ endfor ~}
%{ endfor ~}
