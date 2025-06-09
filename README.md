# Infrastructure Automation Repository

This repository contains infrastructure automation scripts using Terraform and Ansible. It is organized into directories for each tool and specific infrastructure components.

## Contributing

All are welcome and encouraged to contribute! Try to keep any changes generalized, easy to understand, and reusable by all. There may be cases, however, where some specifics are required. In these cases, make sure to include yourself or your team in the CODEOWNERS file for the necessary path. Any new ansible playbook or terraform module should have a README that explains usage, including input params, output params, and an example. Please follow best practices for both [Terraform](https://developer.hashicorp.com/terraform/language/style) and [Ansible](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html).

## Directory Structure

See below for a visual representation of the directory structure. In the ansible directory, a product might be "rke2" or "rancher", and a feature might be "airgap." Scripts are there for reusable scripts, for example to run the set of commands required to install an rke2 server node. In the terraform directory, a provider might be "aws" or "harvester", and modules-with-context might be "airgap-modules".

```
├── ansible/
│   ├── product/
│   │   └── feature/
│   └── scripts/
│       
├── terraform/
│   ├── provider/
│   │   ├── modules/
│   │   └── modules-with-context/
```

## Open Questions

- Who is the current admin for https://github.com/rancher/qa-infra-automation? I'd like to have "Issues" enabled so that people can open them directly when there is a problem.

## Ideas
- Coding standards?
- Design doc required before creating modules/playbooks?
- 'actions' where shared resources live + 'infra' where ansible + tf stuff would live
  - any change to actions would involve rigorous testing + multiple team reviews
    - possible that the TF side of things lives here
  - additions to 'infra' would require minimal cross-team reviews/involvement
  - changes to 'infra' would only involve direct teams
- Ansible should be provider-agnostic
- Terraform should contain modular TF pieces that can work together or on their own.
