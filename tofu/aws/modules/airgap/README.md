1 | # AWS Airgap tofu Module
 2 | 
 3 | This module deploys airgap rancher on AWS.
 4 | 
 5 | ## Prerequisites
 6 | 
 7 | * AWS account configured with appropriate credentials (for provider and S3 backend).
 8 | * tofu installed.
 9 | * S3 bucket for remote tfstate (create one with IAM permissions for Terraform to read/write).
10 | 
11 | ## S3 Backend for tfstate Management
12 | 
13 | This module uses an S3 backend to store tfstate remotely. This automatically uploads the state to S3 after `tofu apply` and updates it on `tofu destroy`. No AWS CLI is needed; it uses the AWS provider.
14 | 
15 | ### Setup
16 | 
17 | 1. Create an S3 bucket (e.g., `airgap-terraform-state`) in your desired region with versioning enabled (optional but recommended).
18 |    - Ensure your AWS credentials have s3:GetObject, s3:PutObject, s3:DeleteObject permissions on the bucket.
19 | 
20 | 2. Edit `backend.tfvars` with your bucket details:
21 |    ```
22 |    bucket = "your-s3-bucket-name"
23 |    key    = "airgap/terraform.tfstate"
24 |    region = "us-east-2"  # Bucket region
25 |    ```
26 | 
27 | 3. Initialize the backend:
28 |    ```
29 |    tofu init -backend-config=backend.tfvars
30 |    ```
31 | 
32 | ### Usage with Backend
33 | 
34 | After init, the tfstate is stored in S3:
35 | - `tofu apply -var-file="terraform.tfvars"`: Applies infrastructure and uploads state to S3.
36 | - `tofu destroy -var-file="terraform.tfvars"`: Destroys infrastructure and updates state in S3.
37 | 
38 | For workspaces, the key will be prefixed (e.g., "env:/workspace/terraform.tfstate").
39 | 
40 | ## Usage (Infrastructure Deployment)
41 | 
42 | 1.  **Create a Workspace:**
43 | 
44 |     ```bash
45 |     tofu workspace new <workspace_name>
46 |     ```
47 | 
48 | 2.  **Select the Workspace:**
49 | 
50 |     ```bash
51 |     tofu workspace select <workspace_name>
52 |     ```
53 | 
54 | 3.  **Apply the Configuration:**
55 | 
56 |     ```bash
57 |     tofu apply -var-file="terraform.tfvars"
58 |     ```
59 |     or
60 |     ```bash
61 |     tofu apply -var="<variable_name>=<variable_value>"
62 |     ```
63 | 
64 |     Create a `terraform.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.
65 | 
66 | 4.  **Destroy the Infrastructure:**
67 | 
68 |     ```bash
69 |     tofu destroy -var-file="terraform.tfvars"
70 |     ```
71 |     or
72 |     ```bash
73 |     tofu destroy -var="<variable_name>=<variable_value>"
74 |     ```
75 | 
76 |     Use the same `terraform.tfvars` file or `-var` flags used during `apply`.
77 | 
78 | ## Variables
79 | 
80 | Refer to `variables.tf` for a list of configurable variables.
81 | 
82 | ## Outputs
83 | 
84 | Refer to `outputs.tf` for a list of exported values.
85 | 
86 | ## Sample `terraform.tfvars`
87 | 
88 | ```terraform
89 | aws_access_key        = "key"
90 | aws_secret_key        = "secretkey"
91 | aws_ami               = "ami-"
92 | instance_type         = "t3.xlarge"
93 | aws_security_group    = ["sg-"]
94 | aws_subnet            = "subnet-"
95 | aws_volume_size       = 500
96 | aws_hostname_prefix   = "hostnameprefix"
97 | aws_region            = "us-west-1"
98 | aws_route53_zone      = "qa.rancher.space"
99 | aws_ssh_user          = "ec2-user"
100| aws_vpc               = "vpc-"
101| user_id               = "user_id"
102| ssh_key               = "sshkey"
103| ssh_key_name          = "sshkeyname"
104| ```
