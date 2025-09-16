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
12 | This module uses an S3 backend to store tfstate remotely. This automatically uploads the state to S3 after `tofu apply` and updates it on `tofu destroy`. No AWS CLI is needed; it uses the AWS provider.
13 | 
14 | ### Setup
15 | 1. Create an S3 bucket (e.g., `airgap-terraform-state`) in your desired region with versioning enabled (optional but recommended).
16 |    - Ensure your AWS credentials have s3:GetObject, s3:PutObject, s3:DeleteObject permissions on the bucket.
17 | 
18 | 2. Edit `backend.tfvars` with your bucket details:
19 |    ```
20 |    bucket = "your-s3-bucket-name"
21 |    key    = "airgap/terraform.tfstate"
22 |    region = "us-east-2"  # Bucket region
23 |    ```
24 | 
25 | 3. Initialize the backend:
26 |    ```
27 |    tofu init -backend-config=backend.tfvars
28 |    ```
29 | 
30 | ### Toggling S3 Backend On/Off
31 | The S3 backend is opt-in and can be toggled:
32 | 
33 | - **On (S3 State)**: Run `tofu init -backend-config=backend.tfvars`. State is stored in S3 on apply/destroy.
34 | - **Off (Local State, Default)**: Run `tofu init` without backend config. Uses local `terraform.tfstate` file—no S3 upload.
35 | - **Switching Back to Local**: Run `tofu init -reconfigure` (without backend config). Download state from S3 first if needed to avoid loss.
36 | 
37 | For dynamic toggling, use workspaces (e.g., "s3" workspace with backend, "local" without).
38 | 
39 | ### Usage with Backend
40 | After init, the tfstate is stored in S3:
41 | - `tofu apply -var-file="terraform.tfvars"`: Applies infrastructure and uploads state to S3.
42 | - `tofu destroy -var-file="terraform.tfvars"`: Destroys infrastructure and updates state in S3.
43 | 
44 | For workspaces, the key will be prefixed (e.g., "env:/workspace/terraform.tfstate").
45 | 
46 | ## Usage (Infrastructure Deployment)
47 | 
48 | 1.  **Create a Workspace:**
49 | 
50 |     ```bash
51 |     tofu workspace new <workspace_name>
52 |     ```
53 | 
54 | 2.  **Select the Workspace:**
55 | 
56 |     ```bash
57 |     tofu workspace select <workspace_name>
58 |     ```
59 | 
60 | 3.  **Apply the Configuration:**
61 | 
62 |     ```bash
63 |     tofu apply -var-file="terraform.tfvars"
64 |     ```
65 |     or
66 |     ```bash
67 |     tofu apply -var="<variable_name>=<variable_value>"
68 |     ```
69 | 
70 |     Create a `terraform.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.
71 | 
72 | 4.  **Destroy the Infrastructure:**
73 | 
74 |     ```bash
75 |     tofu destroy -var-file="terraform.tfvars"
76 |     ```
77 |     or
78 |     ```bash
79 |     tofu destroy -var="<variable_name>=<variable_value>"
80 |     ```
81 | 
82 |     Use the same `terraform.tfvars` file or `-var` flags used during `apply`.
83 | 
84 | ## Variables
85 | 
86 | Refer to `variables.tf` for a list of configurable variables.
87 | 
88 | ## Outputs
89 | 
90 | Refer to `outputs.tf` for a list of exported values.
91 | 
92 | ## Sample `terraform.tfvars`
93 | 
94 | ```terraform
95 | aws_access_key        = "key"
96 | aws_secret_key        = "secretkey"
97 | aws_ami               = "ami-"
98 | instance_type         = "t3.xlarge"
99 | aws_security_group    = ["sg-"]
100| aws_subnet            = "subnet-"
101| aws_volume_size       = 500
102| aws_hostname_prefix   = "hostnameprefix"
103| aws_region            = "us-west-1"
104| aws_route53_zone      = "qa.rancher.space"
105| aws_ssh_user          = "ec2-user"
106| aws_vpc               = "vpc-"
107| user_id               = "user_id"
108| ssh_key               = "sshkey"
109| ssh_key_name          = "sshkeyname"
110| ```
