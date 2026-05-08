#!groovy
@Library('qa-jenkins-library@pull/17/head') _

def repoRoot
def sshDir
def privateKey
def pubKey = "public.pub"
def runnerImage = "ranchertest/infra-runner:v1.0.0"
def playbookDir

pipeline {
  agent any

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
          property.useWithCredentials(['AWS_SSH_PEM_KEY_NAME', 'AWS_SSH_PEM_KEY', 'AWS_SSH_RSA_KEY_NAME', 'AWS_SSH_RSA_KEY', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY']) {
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
            dir("${repoRoot}/${params.TOFU_MODULE}") {
              writeFile file: 'terraform.tfvars', text: """${params.TOFU_CONFIG}
aws_access_key = "${AWS_ACCESS_KEY_ID}"
aws_secret_key = "${AWS_SECRET_ACCESS_KEY}"
public_ssh_key = "/.ssh/${pubKey}"
aws_hostname_prefix = "${params.HOSTNAME_PREFIX}"
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
            command: "sh -c \"tofu -chdir=${params.TOFU_MODULE} init && tofu -chdir=${params.TOFU_MODULE} apply -auto-approve\"",
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
            command: "sh -c \"envsubst < ${playbookDir}/inventory-template.yml > ${playbookDir}/terraform-inventory.yml\"",
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
            command: "sh -c \"ansible-playbook -i ${playbookDir}/terraform-inventory.yml ${params.ANSIBLE_PLAYBOOK}\"",
            workingDir: "/ansible"
          )
        }
      }
    }
  }

  post {
    success {
      script {
        container.runCommand(
          name: "${JOB_BASE_NAME}_${BUILD_NUMBER}_print_kubeconfig",
          image: runnerImage,
          volumes: ["${repoRoot}:/tofu"],
          envVars: [TERRAFORM_NODE_SOURCE: "${params.TOFU_MODULE}"],
          command: "sh -c \"cat ${playbookDir}/kubeconfig.yaml\"",
          workingDir: "/tofu"
        )
      }
    }
    unsuccessful {
      script {
        if (params.DESTROY_ON_FAILURE?.toBoolean() && repoRoot && params?.TOFU_MODULE && fileExists("${repoRoot}/${params.TOFU_MODULE}")) {
          container.runCommand(
            name: "${JOB_BASE_NAME}_${BUILD_NUMBER}_tofu_destroy",
            image: runnerImage,
            volumes: ["${repoRoot}:/tofu", "${sshDir}:/.ssh"],
            command: "sh -c \"tofu -chdir=${params.TOFU_MODULE} destroy -auto-approve\"",
            workingDir: "/tofu"
          )
        }
      }
    }
  }
}