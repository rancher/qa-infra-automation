# Running the Elemental Playbook

This document describes how to run the Ansible playbook responsible for configuring Elemental on Rancher, as well as creating and uploading the Elemental ISO to an S3 bucket.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../../README.md):
*   **Kubernetes Cluster:** A running Kubernetes cluster (e.g., RKE2, K3s, or a managed Kubernetes service).  The playbook assumes you have a `kubeconfig` file that allows access to this cluster.
*   **Environment Variables:**  You'll need to set the following environment variables:
    *   `VARS_FILE`: The full path to your variables file (e.g., `vars.yaml`).

## Configuration

1.  **Set Environment Variables**

    Before running the playbook, set the necessary environment variables. Since the playbook is run from the root of the repository, the paths are relative to that location. For example:

    ```bash
    export VARS_FILE="/path/to/vars.yaml"
    ```

    Replace `/path/to/vars.yaml` with the actual paths to your files.

2.  **Configure Elemental Files**

    Prepare your Elemental configuration file defining charts, inventory, ISO, and cluster details.
    Below is an example configuration:

    ```yaml
    ---
    apiVersion: elemental.cattle.io/v1beta1
    kind: MachineInventorySelectorTemplate
    metadata:
    name: fire-machine-selector
    namespace: fleet-default
    spec:
    template:
        spec:
        selector:
            matchExpressions:
            - key: element
                operator: In
                values: [ 'fire' ]
    ---
    kind: Cluster
    apiVersion: provisioning.cattle.io/v1
    metadata:
    name: elemental-cluster
    namespace: fleet-default
    spec:
    rkeConfig:
        chartValues:
        rke2-calico: {}
        dataDirectories:
        k8sDistro: ''
        provisioning: ''
        systemAgent: ''
        etcd:
        disableSnapshots: false
        snapshotRetention: 5
        snapshotScheduleCron: 0 */5 * * *
        machineGlobalConfig:
        cni: calico
        disable-kube-proxy: false
        etcd-expose-metrics: false
        machinePools:
        - controlPlaneRole: true
            drainBeforeDelete: true
            etcdRole: true
            machineConfigRef:
            apiVersion: elemental.cattle.io/v1beta1
            kind: MachineInventorySelectorTemplate
            name: fire-machine-selector
            name: fire-pool
            quantity: 3
            unhealthyNodeTimeout: 0s
            workerRole: true
            hostnamePrefix: elemental-cluster-fire-pool-
        machineSelectorConfig:
        - config:
            protect-kernel-defaults: false
        registries: {}
        upgradeStrategy:
        controlPlaneConcurrency: '1'
        controlPlaneDrainOptions:
            deleteEmptyDirData: true
            disableEviction: false
            enabled: false
            force: false
            gracePeriod: -1
            ignoreDaemonSets: true
            skipWaitForDeleteTimeoutSeconds: 0
            timeout: 120
        workerConcurrency: '1'
        workerDrainOptions:
            deleteEmptyDirData: true
            disableEviction: false
            enabled: false
            force: false
            gracePeriod: -1
            ignoreDaemonSets: true
            skipWaitForDeleteTimeoutSeconds: 0
            timeout: 120
    kubernetesVersion: v1.33.5+rke2r1
    localClusterAuthEndpoint:
        enabled: false
    ---
    apiVersion: elemental.cattle.io/v1beta1
    kind: MachineRegistration
    metadata:
    name: fire-nodes
    namespace: fleet-default
    spec:
    config:
        cloud-config:
        users:
        - name: root
            passwd: root
        elemental:
        install:
            device-selector:
            - key: Name
            operator: In
            values:
            - /dev/sda
            - /dev/vda
            - /dev/nvme0
            - key: Size
            operator: Gt
            values:
            - 25Gi
            reboot: true
            snapshotter:
            maxSnaps: 2
            type: btrfs
        reset:
            reboot: true
            reset-oem: true
            reset-persistent: true
    machineInventoryLabels:
        element: fire
    ---
    apiVersion: elemental.cattle.io/v1beta1
    kind: SeedImage
    metadata:
    name: fire-img
    namespace: fleet-default
    spec:
    baseImage: registry.suse.com/suse/sl-micro/6.1/baremetal-iso-image:2.2.0-4.3
    cleanupAfterMinutes: 1440
    targetPlatform: linux/x86_64
    type: iso
    registrationRef:
        apiVersion: elemental.cattle.io/v1beta1
        kind: MachineRegistration
        name: fire-nodes
        namespace: fleet-default
    ---
    ```

3.  **Create an S3 Bucket**
    Create an S3 bucket with public access to store the Elemental ISO image, follow the instructions in the referenced [README.md](../../../../../tofu/aws/modules/s3/README.md) to create S3 with public access
    This bucket will be used by the playbook to upload and reference the generated ISO.

4.  **Customize variables:**

    Review and adjust the parameters in your vars.yaml file according to your environment and desired configuration.

    *   `elementalconfig_file`: Path to the Elemental YAML configuration file (e.g., "./elementalconfig.yaml").
    *   `elemental_pool_name`: Elemental cluster pool name. (e.g., "elemental-cluster-fire-pool").
    *   `kubeconfig_file`: Path to the kubeconfig file providing access to the target Kubernetes cluster. Ensure this file is accessible from where Ansible is running
    *   `s3_bucket`: S3 bucket name
    *   `aws_access_key`: AWS access key
    *   `aws_secret_key`: AWS secret key
    *   `aws_region`: AWS region

## Running the Playbook

Execute the playbook using the following command:

```bash
ansible-playbook ansible/rancher/downstream/elemental/harvester/elemental-playbook.yml -vvvv -e "@$VARS_FILE"
```

## Outputs

This playbook does not produce any direct outputs.
The deployment results are reflected within the Kubernetes cluster, S3 bucket and the configured Elemental resources.

## Create Elemental VMs on Harvester
Create a elemental VMS on Harvester using the Tofu module setup instructions located at [README.md](../../../../../tofu/harvester/modules/elemental-vm/README.md)
