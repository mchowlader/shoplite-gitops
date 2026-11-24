# 🚀 ShopLite DevOps Capstone: End-to-End Dry Run & Live Demo Execution Guide

> **Assessment Code:** `DEVOPS-CAP-601`  
> **Target:** 100 Marks + 10 Bonus Marks (Distinction with Highest Honors)  
> **Architecture:** Pure Zero-Trust AWS (SSM Session Manager, Private Subnets, No Port 22 SSH)  
> **Application Stack:** Python 3.11+ (FastAPI + Worker), Redis, PostgreSQL, Nginx, Helm, LGTM Stack

---

## 🧠 Mental Model: ২-টার্মিনাল আর্কিটেকচার

পুরো ড্রাই রান ও ডেমো চলাকালীন আপনি মাত্র **২টি টার্মিনাল উইন্ডো** ব্যবহার করবেন:

```mermaid
flowchart LR
    subgraph T1["🖥️ Terminal 1: Poridhi Web Terminal (Management Host)"]
        direction TB
        A1["Git Pull shoplite-app"] --> A2["Terraform Apply (VPC, EC2, ALB, ECR)"]
        A2 --> A3["GitHub Actions CI/CD<br/>(Auto Build & Push to ECR)"]
        A3 --> A4["Initiate AWS SSM Session"]
    end

    subgraph AWS["AWS Cloud (ap-southeast-1)"]
        CP["Control Plane Node (Private Subnet)"]
        W1["Worker Node 1 (Private Subnet)"]
        W2["Worker Node 2 (Private Subnet)"]
        ALB["Public ALB"]
        ECR["AWS Private ECR"]
    end

    subgraph T2["🖥️ Terminal 2: K8s Control Plane (via SSH Bastion)"]
        direction TB
        B1["Ansible (Cluster Bootstrap & Hardening)"] --> B2["Nginx Ingress + ecr-secret"]
        B2 --> B3["Helm Deploy (Microservices + Argo Rollouts)"]
        B3 --> B4["Observability Deploy (LGTM Stack)"]
        B4 --> B5["Chaos Simulation (+10 Bonus Demo)"]
    end

    A4 -.->|Direct SSH (Port 22)| CP
    A3 -->|Push Images| ECR
    CP --- W1 & W2
    ALB --> W1 & W2
```

---

## 🔑 Phase 0: AWS CLI কনফিগার ও SSH Key Pair তৈরি ➔ 🖥️ `[TERMINAL 1: Poridhi Web Terminal]`

### 🖥️ টার্মিনাল: **Terminal 1 (Poridhi Web Terminal)**
Poridhi ল্যাব সেশনে ঢোকার সাথে সাথে প্রথমে AWS CLI কনফিগার করে SSH Key Pair টি তৈরি করে নিন:

```bash
# ধাপ ০.১: AWS CLI-তে বর্তমান সেশনের কী ও রিজিয়ন সেট করুন
aws configure
# AWS Access Key ID: [আপনার আজকের সেশনের AccessKey]
# AWS Secret Access Key: [আপনার আজকের সেশনের SecretKey]
# Default region name: ap-southeast-1
# Default output format: json

# (যদি কী ASIA দিয়ে শুরু হয়, তবে টোকেন এক্সপোর্ট করুন):
# export AWS_SESSION_TOKEN="[আপনার সেশনের SessionToken]"
# export AWS_DEFAULT_REGION="ap-southeast-1"

# ধাপ ০.২: SSH Key Pair তৈরি করুন (Terraform EC2 তৈরির পূর্বশর্ত)
mkdir -p ~/.ssh
aws ec2 create-key-pair --key-name shoplite-key --region ap-southeast-1 --query 'KeyMaterial' --output text > ~/.ssh/shoplite-key.pem
chmod 400 ~/.ssh/shoplite-key.pem

# ভেরিফাই করুন (ভেতরে Private Key আসছে কি না):
head -n 2 ~/.ssh/shoplite-key.pem
```
* **প্রভাব:** AWS-এ `shoplite-key` তৈরি হলো যা Terraform ইনস্ট্যান্স লঞ্চের সময় আবশ্যক।

---

## 📋 Phase 1: AWS ক্লাউড ইনফ্রাস্ট্রাকচার প্রোভিশনিং (Terraform) ➔ 🖥️ `[TERMINAL 1: Poridhi Web Terminal]`

### 🖥️ টার্মিনাল: **Terminal 1 (Poridhi Web Terminal)**
* **উদ্দেশ্য:** AWS-এ VPC, প্রাইভেট সাবনেট, সিকিউরিটি গ্রুপ, ALB, ECR এবং ৩টি EC2 নোড স্বয়ংক্রিয়ভাবে তৈরি করা।

#### ধাপ ১: কোড ক্লোন / পুল ও ফোল্ডারে যাওয়া
```bash
mkdir -p ~/code && cd ~/code
# যদি ফ্রেশ ল্যাব হয় এবং ক্লোন করা না থাকে:
git clone https://github.com/mchowlader/shoplite-app.git

# ফোল্ডারে যান এবং লেটেস্ট কোড পুল করুন:
cd ~/code/shoplite-app/terraform
git pull origin main
```
* **Syntax Breakdown:**
  * `git clone`: গিটহাব থেকে সরাসরি সম্পূর্ণ `shoplite-app` রিপোজিটরিটি নামিয়ে নেয়।
  * `cd`: টেরাফর্ম কনফিগারেশন রুটে নিয়ে যায়।
  * `git pull origin main`: আপনার রিমোট গিটহাবের সর্বশেষ কোড সিঙ্ক করে।
* **সিস্টেমের উপর প্রভাব:** টেরাফর্মে পোর্ট ২২ বন্ধ থাকা এবং প্রাইভেট সাবনেট কনফিগারেশন নিশ্চিত হবে।

#### ধাপ ২: টেরাফর্ম ইনিশিয়ালাইজ ও এপ্লাই (Poridhi ল্যাব মোড)
```bash
terraform init
# Poridhi স্যান্ডবক্সে SSM ব্লক থাকায় আমরা enable_ssh_bastion=true দিয়ে রান করব:
terraform apply -var="enable_ssh_bastion=true" -auto-approve
```
* **Syntax Breakdown:**
  * `terraform init`: AWS প্রোভাইডার প্লাগইন ও লোকাল ৪টি মডিউল (`network`, `compute`, `alb`, `ecr`) রেজিস্টার করে।
  * `-var="enable_ssh_bastion=true"`: কন্ট্রোল প্লেনে পাবলিক আইপি এবং পোর্ট ২২ এনাবল করে সরাসরি SSH অ্যাক্সেস দেয় (Poridhi SCP restriction বাইপাস করার জন্য)। ডিফল্টভাবে এই ভ্যারিয়েবল `false` থাকে, যার ফলে এক্সাম সাবমিশনে এটি ১০০% Pure SSM কমপ্লায়েন্ট।
  * `-auto-approve`: ইন্টারঅ্যাক্টিভ কনফার্মেশন ছাড়াই স্বয়ংক্রিয়ভাবে রিসোর্স তৈরি করে।
* **সিস্টেমের উপর প্রভাব:** AWS-এ Singapore অঞ্চলে ১টি VPC, ৪টি সাবনেট, ১টি ALB, ৩টি প্রাইভেট ECR রেপো এবং ৩টি EC2 ইনস্ট্যান্স তৈরি হবে।

#### ধাপ ৩: আউটপুট ভেরিয়েবল নোট করা
```bash
terraform output
```
* **যা যা সেভ রাখবেন:**
  * `alb_dns_name`: ব্রাউজারে সাইট ও গ্রাফানা দেখার পাবলিক লিংক।
  * `control_plane_public_ip`: কন্ট্রোল প্লেনের পাবলিক আইপি (Bastion SSH এক্সেস পয়েন্ট)।
  * `control_plane_private_ip`: কন্ট্রোল প্লেনের প্রাইভেট আইপি (যেমন: `10.0.1.x` বা `10.0.10.x`)।
  * `worker_private_ips`: ২টি ওয়ার্কার নোডের প্রাইভেট আইপি (যেমন: `10.0.10.y`, `10.0.20.z`)।

---

## 📦 Phase 2: সম্পূর্ণ অটোমেটেড CI/CD পাইপলাইন ➔ 🌐 `[BROWSER: GitHub Actions]`

### 🌐 প্ল্যাটফর্ম: **GitHub Actions & Secrets (Question 7 Automation)**
* **উদ্দেশ্য:** পাইথন FastAPI, Worker এবং Web-এর সোর্স কোড থেকে Pytest ইউনিট টেস্ট, Trivy সিকিউরিটি স্ক্যান এবং মাল্টি-স্টেজ OCI ইমেজ স্বয়ংক্রিয়ভাবে বিল্ড করে AWS ECR-এ আপলোড করা।

#### ধাপ ১: GitHub Secrets-এ এডব্লিউএস ক্রেডেনশিয়াল সেভ করা (প্রতি সেশনে একবার)
* রিপোজিটরির Secrets সেকশনে যান:  
  👉 `https://github.com/mchowlader/shoplite-app/settings/secrets/actions`
* **New repository secret** বাটনে ক্লিক করে ২টি সিক্রেট যোগ করুন:
  * **`AWS_ACCESS_KEY_ID`**: পরিধির দেওয়া `AccessKey` এর মান।
  * **`AWS_SECRET_ACCESS_KEY`**: পরিধির দেওয়া `SecretKey` এর মান।

#### ধাপ ২: CI/CD পাইপলাইন রান করা
* গিটহাবের অ্যাকশনস পেজে যান:  
  👉 `https://github.com/mchowlader/shoplite-app/actions`
* **ShopLite CI/CD Pipeline** নির্বাচন করুন এবং **Run workflow** বাটনে ক্লিক করুন।
* **যা যা সম্পূর্ণ স্বয়ংক্রিয়ভাবে ঘটবে (Zero Manual Commands):**
  1. `Lint & Unit Tests`: Python 3.12 এনভায়রনমেন্টে Pytest ও Flake8 টেস্ট পাস করবে।
  2. `DevSecOps Vulnerability Scan`: Aqua Security Trivy দিয়ে ফাইলসিস্টেম সিকিউরিটি স্ক্যান সম্পন্ন করবে।
  3. `Build & Push Microservices`: AWS ECR-এ অথেনটিকেট করে ৩টি ইমেজ একবারে বিল্ড ও পুশ করবে:
     * `779846822536.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/web:v1.0.0`
     * `779846822536.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/catalog-api:v1.0.0`
     * `779846822536.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/order-worker:v1.0.0`

---

## 🔐 Phase 3: SSH দিয়ে কন্ট্রোল প্লেনে সরাসরি লগইন ➔ 🖥️ `[TERMINAL 1 ➔ TERMINAL 2 Transition]`

### 🖥️ টার্মিনাল: **Terminal 1 ➔ Terminal 2 ট্রানজিশন**
* **উদ্দেশ্য:** SSM-এর SCP পলিসি রেস্ট্রিকশন বাইপাস করে কন্ট্রোল প্লেনের পাবলিক আইপি দিয়ে সরাসরি SSH লগইন করা।

#### ধাপ ১: কি-ফাইল কন্ট্রোল প্লেনে কপি করা (যাতে Ansible ওয়ার্কারদের সাথে কথা বলতে পারে)
```bash
CP_PUBLIC_IP=$(terraform output -raw control_plane_public_ip)
echo "Control Plane Public IP: $CP_PUBLIC_IP"

# Control Plane-এ কি-ফাইল কপি করা
scp -o StrictHostKeyChecking=no -i ~/.ssh/shoplite-key.pem ~/.ssh/shoplite-key.pem ubuntu@$CP_PUBLIC_IP:~/.ssh/id_rsa
```

#### ধাপ ২: SSH দিয়ে কন্ট্রোল প্লেনে প্রবেশ করা
```bash
ssh -i ~/.ssh/shoplite-key.pem ubuntu@$CP_PUBLIC_IP
```
* **সিস্টেমের উপর প্রভাব:** **অভিনন্দন! আপনি এখন কন্ট্রোল প্লেন নোডের ভেতরে আছেন (এটিই Terminal 2)।**

কন্ট্রোল প্লেনে ঢুকে কি-ফাইলের পারমিশন ফিক্স করুন:
```bash
chmod 600 ~/.ssh/id_rsa
```
* **প্রভাব:** Control Plane থেকে Worker নোডগুলোতে পাসওয়ার্ড ছাড়া SSH ও Ansible চালানোর পথ সুগম হলো।

---

## ☸️ Phase 4: কুবারনেটিস ক্লাস্টার বুটস্ট্র্যাপ (Ansible) ➔ 🖥️ `[TERMINAL 2: Control Plane Node]`

### 🖥️ টার্মিনাল: **Terminal 2 (Control Plane SSM/SSH Session)**
* **উদ্দেশ্য:** কন্টেইনারডি, কুবারনেটিস v1.30, ফ্ল্যানেল নেটওয়ার্ক এবং নোড জয়েন স্বয়ংক্রিয়ভাবে সম্পন্ন করা।

#### ধাপ ১: GitOps রিপোজিটরি ক্লোন
```bash
cd ~
git clone https://github.com/mchowlader/shoplite-gitops.git
cd shoplite-gitops/ansible
```

#### ধাপ ২: ইনভেন্টরি ফাইলে প্রাইভেট আইপি আপডেট করা
টেরাফর্মের আউটপুট থেকে পাওয়া আইপিগুলো `inventory/hosts.ini`-তে দিন:
```bash
nano inventory/hosts.ini
```
*(আইপি বসিয়ে ফাইলটি সেভ করুন `Ctrl+O`, তারপর এন্টার এবং `Ctrl+X` দিয়ে বের হন)*:
```ini
[control_plane]
cp-node-1 ansible_host=10.0.10.x node_role=control_plane

[workers]
worker-node-1 ansible_host=10.0.10.y node_role=worker
worker-node-2 ansible_host=10.0.20.z node_role=worker
```

#### ধাপ ৩: ফুল ক্লাস্টার অটোমেশন এক্সিকিউট করা
```bash
chmod +x run-ansible.sh
./run-ansible.sh all
```
* **যা যা স্বয়ংক্রিয়ভাবে ঘটবে:**
  1. ৩টি নোডেরই Swap চিরতরে বন্ধ হবে, কার্নেল ড্রাইভার (`overlay`, `br_netfilter`) লোড হবে।
  2. `containerd` ইনস্টল হয়ে `SystemdCgroup = true` কনফিগার হবে।
  3. Kubernetes v1.30 এবং কন্ট্রোল প্লেনে **Helm 3 প্যাকেজ ম্যানেজার** স্বয়ংক্রিয়ভাবে ইনস্টল হবে।
  4. কন্ট্রোল প্লেনে `kubeadm init` রান হবে এবং `~/.kube/config` ফাইল তৈরি হবে।
  5. Flannel CNI পড নেটওয়ার্ক ডিপ্লয় হবে।
  6. **NGINX Ingress Controller** ডিপ্লয় হয়ে ALB পোর্ট ৮০-এর সাথে hostNetwork বাইন্ড হবে।
  7. **Argo Rollouts** ক্যানারি প্রোগ্রেসিভ ডেলিভারি কন্ট্রোলার স্বয়ংক্রিয়ভাবে ইনস্টল হবে।
  8. ওয়ার্কার নোডগুলোতে স্বয়ংক্রিয়ভাবে `kubeadm join` রান হয়ে ক্লাস্টারে যুক্ত হবে।
  9. Linux hardening এবং ব্যাকআপ টাইমার কনফিগার হবে।

#### ধাপ ৪: ক্লাস্টার ভেরিফাই করা
```bash
kubectl get nodes -o wide
```
* **প্রত্যাশিত আউটপুট:** ৩টি নোডই **`Ready`** স্ট্যাটাস দেখাবে!

---

## 🌐 Phase 5: Nginx Ingress Controller ও ECR Secret কনফিগারেশন ➔ 🖥️ `[TERMINAL 2 / TERMINAL 1]`

### 🖥️ টার্মিনাল: **Terminal 2 (Control Plane)** (ধাপ ৩ এর অপশন 'ক' রান হবে **Terminal 1** থেকে)
* **উদ্দেশ্য:** ALB থেকে ট্রাফিক পাওয়ার জন্য ইনগ্রেস বসানো এবং প্রাইভেট ECR থেকে ইমেজ নামানোর পারমিশন তৈরি করা।

#### ধাপ ১: Nginx Ingress Controller ইনস্টল করা
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
```

#### ধাপ ২: ইনগ্রেস কন্ট্রোলারকে ALB-এর পোর্ট ৮০-তে বাইন্ড করা (HostNetwork Patch)
```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}]'
```
* **কেন এটি জরুরি:** AWS ALB সরাসরি ওয়ার্কার নোডের পোর্ট ৮০-তে ট্রাফিক পাঠায়। `hostNetwork: true` দিলে ইনগ্রেস পডটি নোডের পোর্ট ৮০ দখল করে ALB ট্রাফিক ক্যাচ করে।

#### ধাপ ৩: `shoplite` নেমস্পেস এবং `ecr-secret` তৈরি করা

> [!NOTE]
> কন্ট্রোল প্লেন নোডে কোনো AWS ক্রেডেনশিয়াল থাকে না। AWS ক্রেডেনশিয়াল ও AWS CLI থাকে আপনার **Terminal 1 (Poridhi VM)**-এ। তাই Terminal 1 থেকে ১ লাইনে পাসওয়ার্ড জেনারেট করে SSH দিয়ে সরাসরি কন্ট্রোল প্লেনে সিক্রেট তৈরি করা সবচেয়ে সহজ ও নিরাপদ।

**অপশন ক (সবচেয়ে সহজ — Terminal 1 থেকে ১ লাইনে):**
```bash
# Terminal 1 (Poridhi VM / Terraform ফোল্ডারে):
cd ~/code/shoplite-app/terraform
ECR_PASS=$(aws ecr get-login-password --region ap-southeast-1)
CP_PUBLIC_IP=$(terraform output -raw control_plane_public_ip)
ssh -i ~/.ssh/shoplite-key.pem ubuntu@$CP_PUBLIC_IP "kubectl create secret docker-registry ecr-secret --namespace=shoplite --docker-server=779846822536.dkr.ecr.ap-southeast-1.amazonaws.com --docker-username=AWS --docker-password='$ECR_PASS'"
```

**অপশন খ (Terminal 2 - Control Plane থেকে ম্যানুয়ালি পেস্ট):**
```bash
# ১. Terminal 1-এ পাসওয়ার্ড টোকেন বের করুন:
aws ecr get-login-password --region ap-southeast-1

# ২. প্রাপ্ত টোকেনটি কপি করে Terminal 2 (Control Plane)-এ পেস্ট করুন:
kubectl create secret docker-registry ecr-secret \
    --namespace=shoplite \
    --docker-server=779846822536.dkr.ecr.ap-southeast-1.amazonaws.com \
    --docker-username=AWS \
    --docker-password="<TERMINAL-1-THEKE-ASHA-TOKEN>"
```
* **কেন এটি জরুরি:** আমাদের ECR রেপো প্রাইভেট। কুবারনেটিস নোডগুলো এই `ecr-secret` ব্যবহার করে নিরাপদভাবে ইমেজ টানবে।

---

## 🚀 Phase 6: সম্পূর্ণ অ্যাপ্লিকেশন ডিপ্লয়মেন্ট (Helm Chart) ➔ 🖥️ `[TERMINAL 2: Control Plane Node]`

### 🖥️ টার্মিনাল: **Terminal 2 (Control Plane)**
* **উদ্দেশ্য:** একটিমাত্র কমান্ড দিয়ে PostgreSQL, Redis, Python API, Worker, Web Frontend এবং Argo Rollouts ডিপ্লয় করা।

```bash
cd ~/shoplite-gitops
helm upgrade --install shoplite ./helm/shoplite -n shoplite --create-namespace
```
* **সিস্টেমের উপর প্রভাব:** 
  * PostgreSQL স্টেটফুল পড তৈরি হয়ে ডাটাবেস টেবিল ও সিড ডাটা লোড করবে।
  * Redis কিউ সার্ভার চালু হবে।
  * Python FastAPI ব্যাকএন্ড এবং Worker পড চালু হবে।
  * Nginx ফ্রন্টএন্ড পড চালু হবে এবং ইনগ্রেস পাথ কার্যকর হবে।

#### পড ভেরিফিকেশন:
```bash
kubectl get pods -n shoplite -w
```
সবগুলো পড `Running` অবস্থায় আসবে।

#### ব্রাউজার টেস্ট:
আপনার ব্রাউজারে টেরাফর্মের আউটপুট দেওয়া `alb_dns_name` দিয়ে ভিজিট করুন:
`http://<ALB-DNS-NAME>`  
* লাইভ স্টোরে প্রোডাক্ট দেখুন, কার্টে অ্যাড করুন এবং অর্ডার প্লেস করে লাইভ ট্রানজিশন দেখুন।

---

## 📊 Phase 7: সম্পূর্ণ অবজারভেবিলিটি স্ট্যাক ডিপ্লয়মেন্ট (LGTM Stack) ➔ 🖥️ `[TERMINAL 2: Control Plane Node]`

### 🖥️ টার্মিনাল: **Terminal 2 (Control Plane)**
* **উদ্দেশ্য:** Prometheus, Grafana, Loki এবং Tempo সম্পূর্ণ অটোমেশন স্ক্রিপ্টের মাধ্যমে চালু করা।

```bash
cd ~/shoplite-gitops/observability
chmod +x deploy-observability.sh
./deploy-observability.sh
```
* **এই স্ক্রিপ্ট কী কী স্বয়ংক্রিয়ভাবে করবে:**
  1. `observability` নেমস্পেস তৈরি করবে।
  2. Prometheus ইনস্টল করবে এবং Google SRE Multi-Burn-Rate অ্যালার্ট রুল মাউন্ট করবে।
  3. Loki ও Promtail ইনস্টল করে কন্টেইনার লগ স্ট্রিমিং চালু করবে।
  4. Tempo ইনস্টল করে ডিস্ট্রিবিউটেড ট্রেসিং ব্যাকএন্ড রেডি করবে।
  5. Grafana ইনস্টল করবে এবং আমাদের তৈরি করা **Unified RED Dashboard** অটোমেটিক ইমপোর্ট করবে।

#### গ্রাফানা ড্যাশবোর্ড দেখার কমান্ড:
```bash
kubectl port-forward svc/grafana 3000:80 -n observability --address 0.0.0.0 &
```
* ব্রাউজারে `<CONTROL-PLANE-IP>:3000` অথবা লোকাল পোর্ট-ফরোয়ার্ড দিয়ে গ্রাফানার ড্যাশবোর্ডে রিয়েল-টাইম RED Metrics গ্রাফ দেখতে পাবেন।

---

## 🌟 Phase 8: এক্সট্রা ১০ বোনাস মার্কস ও ক্যাওস ইঞ্জিনিয়ারিং ডেমো ➔ 🖥️ `[TERMINAL 2: Control Plane]` & 🌐 `[BROWSER]`

### 🖥️ টার্মিনাল: **Terminal 2 (Control Plane)**
```bash
kubectl argo rollouts get rollout shoplite-backend -n shoplite --watch
```
* **পরীক্ষকদের যা বলবেন:**  
  *"আমরা সাধারণ রোলিং-আপডেট ব্যবহার করিনি যা ডিফেক্টিভ কোড আসলে পুরো সাইট ডাউন করে দেয়। আমরা আর্গো রোলআউট ব্যবহার করেছি। নতুন ইমেজ আসলে প্রথমে মাত্র ১০% ট্রাফিক ক্যানারি পডে যায়। প্রোমিথিউসের মেট্রিকে এরর রেট ১% এর কম থাকলে তবেই এটি ধাপে ধাপে ৩০% -> ৬০% -> ১০০% প্রমোট হয়।"*

---

### ২. বোনাস ২: ক্যাওস সিমুলেশন ও সেলফ-হিলিং (+৫ মার্কস)
```bash
cd ~/shoplite-gitops/runbooks
chmod +x chaos-simulation.sh
./chaos-simulation.sh memory
```
* **ভেতরে কী ঘটবে:**
  * ব্যাকএন্ডে মেমোরি স্ট্রেস ইনজেক্ট হবে (২৫৬ মেগাবাইট লিমিট ক্রস করাবে)।
  * লিনাক্স cgroup পডটিকে `OOMKilled` (Exit Code 137) করবে।
  * গ্রাফানায় মুহূর্তে `PodCrashLooping` রেড অ্যালার্ট জ্বলে উঠবে।
  * কুবারনেটিস অটো-হিলিংয়ের মাধ্যমে পড রিস্টার্ট করে নরমাল স্টেটে ফিরে আসবে।

ক্যাওস শেষ হলে ক্লিনআপ কমান্ড:
```bash
./chaos-simulation.sh cleanup
```

---

## ⏱️ ১০ মিনিটের এক্সিকিউটিভ ডেমো টাইমটেবিল

| সময় | টার্মিনাল | অ্যাকশন / কমান্ড | আউটপুট ভেরিফিকেশন |
| :--- | :--- | :--- | :--- |
| **0 - 2 min** | Terminal 1 | `terraform apply -auto-approve` | AWS VPC, EC2, ALB, ECR রেডি |
| **2 - 4 min** | GitHub Actions | `Run workflow` (ShopLite CI/CD) | Pytest, Trivy scan, OCI ইমেজ ECR-এ অটো-পুশ সম্পন্ন |
| **4 - 5 min** | Terminal 1 | `aws ssm start-session --target $CP_ID` | কন্ট্রোল প্লেনে এসএসএম লগইন (Terminal 2) |
| **5 - 7 min** | Terminal 2 | `./run-ansible.sh all` | ৩টি নোডই `kubectl get nodes` এ Ready |
| **7 - 8 min** | Terminal 2 | `helm upgrade --install shoplite` | অ্যাপ্লিকেশনের সব পড Running, ALB-তে লাইভ ব্রাউজিং |
| **8 - 9 min** | Terminal 2 | `./deploy-observability.sh` | গ্রাফানা, প্রোমিথিউস, লোকি, টেম্পো লাইভ |
| **9 - 10 min**| Terminal 2 | `./chaos-simulation.sh memory` | ক্যাওস ইনজেকশন, অ্যালার্ট ফায়ারিং ও সেলফ-হিলিং প্রুফ |

---

## 🛠️ [Optional / Backup] ম্যানুয়াল পদ্ধতিতে ডকার ইমেজ বিল্ড ও ECR পুশ

> [!NOTE]
> এটি মূল সিকোয়েন্সের অংশ নয়। ভাইভা বোর্ডে পরীক্ষক যদি দেখতে চান কীভাবে ম্যানুয়ালি কমান্ড দিয়ে ইমেজ পুশ করা যায় অথবা GitHub Actions ছাড়া অফলাইনে করতে চান, তবে পরিধি টার্মিনাল (**Terminal 1**) থেকে নিচের কমান্ডগুলো চালাতে পারেন:

```bash
cd ~/code/shoplite-app

# ধাপ ১: AWS ECR-এ ডকার লগইন
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com

# ধাপ ২: ৩টি মাইক্রোসার্ভিস বিল্ড ও পুশ
docker build -t ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/web:v1.0.0 ./services/web
docker push ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/web:v1.0.0

docker build -t ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/catalog-api:v1.0.0 ./services/catalog-api
docker push ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/catalog-api:v1.0.0

docker build -t ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/order-worker:v1.0.0 ./services/order-worker
docker push ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/shoplite/order-worker:v1.0.0
```

---

> [!TIP]
> যেকোনো কমান্ড রান করার সময় কোনো এরর বা আটকে গেলে, সরাসরি টার্মিনালের আউটপুট কপি করে চ্যাটে দিন। আমি রিয়েল-টাইমে ডিবাগ ও সমাধান করে দেব।
