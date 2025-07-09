# FAQ

1. How do we account for OS differences without creating OS-specific playbooks?
   - Assume that everything is required to work on SLES and SLE Micro at minimum. RHEL and Ubuntu are nice to have.
   - Develop playbooks such that they account for this requirement.
   - If your playbook can only support a specific OS or OSes, mention so clearly in its README.

2. What should the structure of the READMEs look like?
   - Please see the README examples in this folder.

3. Do I need to create a design document before developing a new ansible playbook or terraform module?
   - A design document is not required. 
   - In some more complex cases, there may be benefits to reviewing the design with others before implementation. Feel free to create a document and have a design discussion ahead of time if desired! Remember to still capture as much relevant information as possible in the ansible and terraform READMEs during implementation.

4. I always run a specific ansible playbook after bringing up my infra with terraform. How can I streamline this?
   - You may create a specific ansible playbook that does everything (runs the terraform, then runs another ansible playbook). This should live in the ansible directory just like any other playbook.
   - Does this already exist in a CI/CD environment, such as Jenkins?
     - If yes, is it sufficient to just use that?
     - If no, add the flow for this to your CI/CD environment!

5. I have a test that requires running terraform and/or an ansible playbook in the middle of it. How do I do that?
   - There is a plan to have a Go client for this to make it easy. Until that is written, there are tools that allow each of these individually that you are welcome to use (e.g. go-ansible, terratest, and terraform-exec).
