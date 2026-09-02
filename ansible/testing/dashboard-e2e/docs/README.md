# dashboard-e2e internals

How this playbook is put together, and how the pieces around it fit.

The top-level [`README.md`](../README.md) and
[`QUICKSTART.md`](../QUICKSTART.md) answer "how do I run it". These pages
answer "why does it work that way", which is what you need when a run resolves
the wrong build, when a Jenkins job behaves differently from a local run, or
when you are changing the thing itself.

| Page | Covers |
| --- | --- |
| [architecture.md](architecture.md) | The play: phases, task order, what each stage produces, and the variables that carry state between them |
| [jenkins.md](jenkins.md) | The Jenkins path: parent matrix job, child job, `init.sh`, and the two containers a build runs |
| [resolver.md](resolver.md) | Which chart, image and build type a row resolves to, and why each signal was chosen |
| [ci-files.md](ci-files.md) | `files/`, and how it is laid over the `cypress/jenkins/` directory of the dashboard checkout |

## The whole thing in one picture

```text
Jenkins parent job  (dashboard: cypress/jenkins/Jenkinsfile_multi)
  │  one TEST_MATRIX row  =  kind:tag[:k8s]  =  one child build
  ▼
Jenkins child job   (dashboard: cypress/jenkins/Jenkinsfile)
  │  checks out BOTH repos, then runs one script
  ▼
init.sh             (dashboard: cypress/jenkins/init.sh)
  │  writes vars.yaml, builds the runner image. No git: Jenkins already
  │  fetched the code, the same way run.sh assumes a checkout is present
  ▼
dashboard-e2e-runner container
  │  ENTRYPOINT: ansible-playbook dashboard-e2e-playbook.yml
  ▼
dashboard-e2e-playbook.yml   ← you are here
  │  resolve → provision → deploy → ask Rancher what it is → set up → test
  ▼
dashboard-test container
     ENTRYPOINT: bash cypress/jenkins/cypress.sh   ← from files/, not from the
                                                     dashboard checkout
```

Three things about that diagram are easy to get wrong and worth stating up
front.

**The playbook does not live in the dashboard repo, and the Jenkins glue does
not live here.** `Jenkinsfile`, `Jenkinsfile_multi`, `init.sh` and
`slack-notification.sh` are all in `rancher/dashboard` under `cypress/jenkins/`.
Everything they drive is in this directory. A change to the contract between
them is a change to two repositories.

**The dashboard checkout is both input and workspace.** `init.sh` checks out
`rancher/dashboard` for the Jenkins job's own scripts. The playbook then clones
`rancher/dashboard` *again*, at the branch that matches the Rancher under test,
into `dashboard/` beside itself, and overwrites five files in its
`cypress/jenkins/` directory from [`files/`](../files). That second checkout is
what Cypress runs against. See [ci-files.md](ci-files.md).

**A run tests a backend *and* a UI, and they are chosen separately.** The
resolver picks the Rancher image. The UI is chosen by `ui-offline-preferred`,
which defaults to `dynamic`: local assets on a released build, but the CDN at
`releases.rancher.com/dashboard/latest` on a head build. That CDN path moves on
its own, so a head row on the default pairs the image with whatever UI was
published most recently. Measured on a `v2.16.0-head` cluster: the image
embedded dashboard `df69324` while the CDN served `5c9f7a9`, a day newer.
Setting `ui_offline_preferred: "true"` serves the UI built with the image, which
is why the Jenkins jobs set it. Every run reports which one it got as
`PROVENANCE ui build`. See [resolver.md](resolver.md#which-ui).

**Nothing is passed to Ansible with `-e`.** All configuration reaches the play
through `vars.yaml`, loaded by `vars_files`. The `-e` flags on the `docker run`
lines in `init.sh` are Docker environment variables. This distinction is load
bearing: `-e` extra-vars outrank `set_fact`, so a run configured that way could
not be rewritten by the resolver. See [resolver.md](resolver.md#precedence).

## Where each concern lives

| Concern | File |
| --- | --- |
| Stage order, phase gating | [`dashboard-e2e-playbook.yml`](../dashboard-e2e-playbook.yml) |
| Which channel a row deploys from | [`tasks/resolve-channel.yml`](../tasks/resolve-channel.yml) |
| Which chart version and image tag | [`tasks/resolve-helm-version.yml`](../tasks/resolve-helm-version.yml) |
| Ordering the release ladder | [`filter_plugins/rancher_charts.py`](../filter_plugins/rancher_charts.py) |
| AWS, DNS, inventory | [`tasks/provision.yml`](../tasks/provision.yml) |
| K3s and Rancher install | [`tasks/install-k3s-rancher.yml`](../tasks/install-k3s-rancher.yml) |
| Dashboard checkout, CI overlay, image build | [`tasks/setup-test-env.yml`](../tasks/setup-test-env.yml) |
| Running Cypress, collecting results | [`tasks/run-tests.yml`](../tasks/run-tests.yml) |
| Tearing it all down | [`tasks/cleanup.yml`](../tasks/cleanup.yml) |
| The runner image | [`Dockerfile.quickstart`](../Dockerfile.quickstart) |
| The local wrapper | [`run.sh`](../run.sh) |
