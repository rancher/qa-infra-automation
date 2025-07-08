# Infrastructure Automation Repository

This repository contains infrastructure automation scripts using Tofu and Ansible. It is organized into directories for each tool and specific infrastructure components. Below is an overview that highlights the most important things to keep in mind for contributors. See the `docs/` folder for all other documentation related to this repository.

## Getting Started

All are welcome and encouraged to contribute! Try to keep any changes generalized, easy to understand, and reusable by all. There may be cases, however, where some specifics are required. In these cases, make sure to include yourself or your team in the [CODEOWNERS](./CODEOWNERS) file for the necessary path. Any new ansible playbook or tofu module should have a README that explains usage, including input params, output params, and an example. Please follow best practices for both [Tofu](https://opentofu.org/docs/language/syntax/style/) and [Ansible](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html).

Some contributors may be more familiar with Terraform than Tofu. Tofu is the open-source alternative but is otherwise almost identical. See their docs to learn more about how to [migrate from Terraform to Tofu](https://opentofu.org/docs/intro/migration/). 

It may be helpful when developing or running the modules and playbooks here to have a file with some default environment variables. For a reference, please see this [example](./vars.example-env).

## Directory Structure

See below for a visual representation of the directory structure. In the ansible directory, a product might be "rke2" or "rancher", and a feature might be "airgap." Scripts are there for reusable scripts, for example to run the set of commands required to install an rke2 server node. In the terraform directory, a provider might be "aws" or "harvester", and context might be "airgap".

```
├── ansible/
│   ├── product/
│   │   └── feature/
│   │       └── scripts/
│   └── roles/
│       
├── tofu/
│   ├── provider/
│   │   ├── modules/
│   │   │   └── context/
```

## Standards
- Ansible playbooks should be provider-agnostic.
- Tofu should contain modular TF pieces that can work together or on their own.
- Everything should be as modular as possible.
- Any collection of tasks that are easily reusable should be a *role* and called from playbooks that need them
