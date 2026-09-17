"""System-service boundary fixture; Ansible scheduling and role tasks stay real."""

import json
import os

from ansible.module_utils.basic import AnsibleModule
import yaml


def main():
    module = AnsibleModule(argument_spec={
        "operation": {"type": "str", "required": True},
        "services": {"type": "dict", "default": {}},
        "name": {"type": "str"},
        "state": {"type": "str"},
        "config_path": {"type": "path"},
        "kubeconfig_path": {"type": "path"},
        "log_path": {"type": "path"},
        "fail_restart": {"type": "bool", "default": False},
    })
    values = module.params
    if values["operation"] == "facts":
        module.exit_json(changed=False, ansible_facts={"services": values["services"]})
    if values["fail_restart"]:
        module.fail_json(msg="Simulated service restart failure")
    if values["state"] != "restarted":
        module.fail_json(msg="Expected an actual restart request")
    with open(values["config_path"], encoding="utf-8") as source:
        config = yaml.safe_load(source)
    if "write-kubeconfig-mode" in config:
        mode = int(str(config["write-kubeconfig-mode"]), 8)
        os.chmod(values["kubeconfig_path"], mode)
    with open(values["log_path"], "a", encoding="utf-8") as log:
        log.write(json.dumps({"name": values["name"], "state": values["state"]}) + "\n")
    module.exit_json(changed=True)


if __name__ == "__main__":
    main()
