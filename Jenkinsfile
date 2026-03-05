#!groovy
@Library('qa-jenkins-library@pull/17/head') _

def repoRoot
def sshDir
def privateKey
def pubKey = "public.pub"
def runnerImage = "maxross/infra-runner:v1.0.0"
def playbookDir

pipeline {
  agent any

  // Commenting out parameters since we'll have these defined via Jenkins Job Builder. They can be re-enabled if we want to run this pipeline manually from the Jenkins UI. 
  // Furthermore, the default values for these parameters are more well defined in the Jenkins Job Builder YAML file.
  // parameters {
  //     string(name: 'REPO', defaultValue: '', description: 'Git repository to checkout')
  //     string(name: 'BRANCH', defaultValue: 'main', description: 'Git branch or ref to checkout')
  //     string(name: 'TOFU_MODULE', defaultValue: 'tofu/aws/modules/cluster_nodes', description: 'Tofu module path to apply')
  //     text(name: 'TOFU_CONFIG', defaultValue: '', description: 'Base tfvars file content used to build terraform.tfvars')
  //     string(name: 'SSH_KEY_TYPE', defaultValue: 'pem', description: 'Type of SSH key provided (pem or rsa)')
  //     string(name: 'ANSIBLE_PLAYBOOK', defaultValue: 'ansible/k3s/default/k3s-playbook.yml', description: 'Path to Ansible playbook relative to repo root')
  //     text(name: 'ANSIBLE_VARS', defaultValue: '', description: 'Additional Ansible variables in YAML format; content is written directly to vars.yaml')
  // }

  stages {

    stage('Checkout Repository') {
      steps {
        script {
          repoRoot = project.checkout(repository: params.REPO, branch: params.BRANCH, target: 'reporoot')
        }
      }
    }

    stage('Configure Tofu Variables') {
      steps{
        script {
          sshDir = "${env.WORKSPACE}/.ssh"
          property.useWithCredentials(['AWS_SSH_PEM_KEY_NAME', 'AWS_SSH_PEM_KEY', 'AWS_SSH_RSA_KEY_NAME', 'AWS_SSH_RSA_KEY']) {
            dir(sshDir) {
              if (params.SSH_KEY_TYPE == 'pem') {
                infrastructure.writeSshKey(keyContent: env.AWS_SSH_PEM_KEY, keyName: env.AWS_SSH_PEM_KEY_NAME, pubKeyName: pubKey, dir: sshDir)
                privateKey = env.AWS_SSH_PEM_KEY_NAME
              } else if (params.SSH_KEY_TYPE == 'rsa') {
                infrastructure.writeSshKey(keyContent: env.AWS_SSH_RSA_KEY, keyName: env.AWS_SSH_RSA_KEY_NAME, pubKeyName: pubKey, dir: sshDir)
                privateKey = env.AWS_SSH_RSA_KEY_NAME
              } else {
                error "Unsupported SSH_KEY_TYPE: ${params.SSH_KEY_TYPE}. Supported types are 'pem' and 'rsa'."
              }
            }
          }
          property.useWithProperties(['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY']) {
            dir("${repoRoot}/${params.TOFU_MODULE}") {
              writeFile file: 'terraform.tfvars', text: """${params.TOFU_CONFIG}
aws_access_key = "${AWS_ACCESS_KEY_ID}"
aws_secret_key = "${AWS_SECRET_ACCESS_KEY}"
public_ssh_key = "/.ssh/${pubKey}"
"""
            }
          }
        }
      }
    }

    stage('Create Infra') {
      steps {
        script {
          container.runCommand(
            name: "${JOB_BASE_NAME}_${BUILD_NUMBER}_tofu",
            image: runnerImage,
            volumes: ["${repoRoot}:/tofu", "${sshDir}:/.ssh"],
            command: "sh -c \"tofu -chdir=\\\"${params.TOFU_MODULE}\\\" init && tofu -chdir=\\\"${params.TOFU_MODULE}\\\" apply -auto-approve\"",
            workingDir: "/tofu"
          )
        }
      }
    }

    stage('Configure Ansible Inventory') {
      environment {
        TERRAFORM_NODE_SOURCE="${params.TOFU_MODULE}"
        RANCHER_INFRA_TOOLS_IMAGE="${runnerImage}"
      }
      steps {
        script {
          def fqdn
          def kube_api_host

          dir(repoRoot) {
            playbookDir = infrastructure.getDirectory(filePath: params.ANSIBLE_PLAYBOOK)
            fqdn = tofu.getOutputs(dir: "${params.TOFU_MODULE}", output: 'fqdn')
            kube_api_host = tofu.getOutputs(dir: "${params.TOFU_MODULE}", output: 'kube_api_host')
          }

          container.runCommand(
            name: "${JOB_BASE_NAME}_${BUILD_NUMBER}_envsubst",
            image: runnerImage,
            volumes: ["${repoRoot}:/tofu", "${sshDir}:/.ssh"],
            envVars: [TERRAFORM_NODE_SOURCE: "${params.TOFU_MODULE}"],
            command: "sh -c \"pwd && ls -la && envsubst < \\\"${playbookDir}/inventory-template.yml\\\" > \\\"${playbookDir}/terraform-inventory.yml\\\"\"",
            workingDir: "/tofu"
          )

          dir("${repoRoot}/${playbookDir}") {
            writeFile file: 'vars.yaml', text: """${params.ANSIBLE_VARS}
kubeconfig_file: "./kubeconfig.yaml"
fqdn: "${fqdn}"
kube_api_host: "${kube_api_host}"
"""
          }
        }
      }
    }

    stage('Deploy K8s Distro') {
      steps {
        script {
          container.runCommand(
            name: "${JOB_BASE_NAME}_${BUILD_NUMBER}_ansible",
            image: runnerImage,
            volumes: ["${repoRoot}:/ansible", "${sshDir}:/.ssh"],
            envVars: [ANSIBLE_CONFIG: "${playbookDir}/ansible.cfg", ANSIBLE_PRIVATE_KEY_FILE: "/.ssh/${privateKey}"],
            command: "sh -c \"ansible-playbook -i \\\"${playbookDir}/terraform-inventory.yml\\\" -vvvv \\\"${params.ANSIBLE_PLAYBOOK}\\\"\"",
            workingDir: "/ansible"
          )
        }
      }
    }

    stage('Print Kubeconfig') {
      steps {
        script {
          container.runCommand(
            name: "${JOB_BASE_NAME}_${BUILD_NUMBER}_print_kubeconfig",
            image: runnerImage,
            volumes: ["${repoRoot}:/tofu"],
            envVars: [TERRAFORM_NODE_SOURCE: "${params.TOFU_MODULE}"],
            command: "sh -c \"cat \\\"${playbookDir}/kubeconfig.yaml\\\"\"",
            workingDir: "/tofu"
          )
        }
      }
    }
  }
}