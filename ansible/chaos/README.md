# Running the Chaos Playbook

This README provides instructions on how to run the Ansible playbook for running a Chaos experiment using Steadybit.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../README.md):
*   **Kubernetes Cluster:** A running Kubernetes cluster.  The playbook assumes you have a `kubeconfig` file that allows access to this cluster, and that it is either at the default path (`~/.kube/config`) or you have an environment variable pointing to it (`export KUBECONFIG=/path/to/kubeconfig.yaml`)


## Configuration

1.  **Set required variables:**

    Directly in this directory, create a `vars.yaml` file with the following variables:

    ```yaml
    steadybit_token: your_token
    steadybit_cli_version: 4.2.11 # Optional. Can set the steadybit cli version explicitly, otherwise it will just use version "4"
    experiment_file: experiments/experiment.yml # Optional. Can specify the relative path to the experiment file. By default it will use "experiments/experiment.yml"
    experiment_timeout: 500 # Optional. Timeout (in seconds) to wait for the experiment execution to complete. By default this is "300"
    ```

2.  **Set required values for Steadybit helm installation**

    Directly in this directory, create a `values.yml` file for installing the steadybit-agent via helm. For example, when using k3s, it should look similar to this:

    ```yaml
    agent:
      key: "$STEADYBIT_KEY" # Replace with your steadybit platform key
      registerUrl: "https://platform.steadybit.com"
    global:
      clusterName: "mycluster"
    extension-container:
      container:
        runtime: "containerd"
      containerRuntimes:
        containerd:
          socket: "/run/k3s/containerd/containerd.sock"
      containerEngines:
        containerd:
          socket: "/var/run/k3s/containerd/containerd.sock"
      extraEnv:
        - name: "STEADYBIT_EXTENSION_CONTAINER_RUNTIME"
          value: "containerd"
        - name: "STEADYBIT_EXTENSION_CONTAINER_SOCKET"
          value: "/run/k3s/containerd/containerd.sock"

3.  **Provide Steadybit experiment file**

    Directly in this directory, create an `experiments/experiment.yml` file for updating the Steadybit chaos experiment. This can be retrieved by running a command similar to this, but using your experiment key: `steadybit experiment get -k ADM-1 -f experiments/experiment.yml`. Make any necessary edits to the `experimentVariables` in the output as required for your experiment.


## Running the Playbook

To run the playbook, use the following command:

```bash
ansible-playbook steadybit-install-playbook.yml --extra-vars "@vars.yaml"
```

## Outputs

When the experiment is a success, the playbook should end successfully. Otherwise, there should be a failure message that contains a URL to the experiment run to view the failure reason.
