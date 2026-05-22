# iii Distributed Inference — AWS Deployment

Deploys the [iii quickstart](https://iii.dev/docs/quickstart) across two private AWS VMs with a public API gateway. A Python worker loads a small language model and exposes inference as an RPC function. A TypeScript worker receives HTTP requests, calls the Python worker via RPC, and returns the result as JSON. The two workers run on separate machines and communicate only through the private subnet — never over the public internet.

---

## Architecture

```
                        Internet
                            │
                     HTTP :80 only
                            │
              ┌─────────────▼──────────────────┐
              │         AWS VPC 10.0.0.0/16     │
              │                                 │
              │  Public Subnet 10.0.1.0/24      │
              │  ┌──────────────────────────┐   │
              │  │  gateway-vm (t3.small)   │   │
              │  │  Private IP: 10.0.1.10   │   │
              │  │  Public IP: <assigned>   │   │
              │  │                          │   │
              │  │  nginx       :80  ──┐    │   │
              │  │  iii engine  :3111 ◄┘    │   │
              │  │              :49134 ─────┼───┼──┐
              │  │  caller-worker           │   │  │
              │  └──────────────────────────┘   │  │
              │                                 │  │ WebSocket RPC
              │  Private Subnet 10.0.2.0/24     │  │ ws://10.0.1.10:49134
              │  ┌──────────────────────────┐   │  │
              │  │  inference-worker-vm     │◄──┼──┘
              │  │  (t3.large)              │   │
              │  │  No public IP            │   │
              │  │  Python + Qwen model     │   │
              │  └──────────┬───────────────┘   │
              │             │                   │
              │         NAT Gateway             │
              │    (outbound only — pip/model)  │
              └─────────────────────────────────┘
```

### RPC Call Flow

```
curl POST /v1/chat/completions
    │
    ▼
nginx :80 (gateway-vm)
    │
    ▼
iii HTTP API :3111
    │
    ▼
http::run_inference_over_http  (caller-worker, TypeScript)
    │
    ▼
inference::get_response        (caller-worker, TypeScript)
    │  WebSocket RPC over private subnet
    ▼
inference::run_inference       (inference-worker, Python)
    │
    ▼
Qwen2.5-0.5B model generates response
    │
    ▼
JSON response returned to caller
```

---

## VM Summary

| VM | Instance | Subnet | Public IP | Runs |
|---|---|---|---|---|
| `gateway-vm` | t3.small | Public 10.0.1.0/24 | Yes | iii engine + caller-worker + nginx |
| `inference-worker-vm` | t3.micro | Private 10.0.2.0/24 | No | Python inference worker + model |

> **Note:** t3.micro (1GB RAM) works because the userdata script allocates 4GB swap.
> Model loading uses swap during initialisation then settles into RAM.
> t3.large is preferred if your account allows it.

### Why these sizes
- **t3.small (2GB)** — gateway runs iii engine + Node.js caller-worker + nginx. t2.micro (1GB) OOMs under combined load.
- **t3.micro (1GB + 4GB swap)** — inference worker loads Qwen2.5-0.5B (~500MB) with PyTorch overhead managed via swap space allocated in the bootstrap script.

---

## API Reference

### Endpoint

```
POST http://<GATEWAY_PUBLIC_IP>/v1/chat/completions
Content-Type: application/json
```

### Request

```json
{
  "messages": [
    {"role": "user", "content": "Your message here"}
  ]
}
```

### Response

```json
{
  "result": {
    "response": "2 + 2 equals 4.",
    "success": "You've connected two workers and they're interoperating seamlessly..."
  }
}
```

### curl command

```bash
curl -X POST http://<GATEWAY_PUBLIC_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is 2+2?"}]}'
```

> **Note:** Inference runs on CPU. Expect 15–60 seconds response time.

---

## Prerequisites

Before deploying, make sure you have:

- [ ] AWS account with billing enabled (free tier or credits)
- [ ] [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured
- [ ] [Terraform ≥ 1.6](https://developer.hashicorp.com/terraform/install) installed
- [ ] Git installed

Verify everything works:

```bash
aws sts get-caller-identity   # should return your account ID
terraform --version            # should show 1.6+
```

### Configure AWS credentials

```bash
aws configure
```

You will be prompted for:

```
AWS Access Key ID:     your-access-key-id
AWS Secret Access Key: your-secret-access-key
Default region name:   ap-south-1
Default output format: json
```

**To get your credentials:**
1. Go to AWS Console → IAM → Users → your user
2. Security credentials tab → Create access key
3. Choose CLI as the use case
4. Copy the Access Key ID and Secret Access Key

> Never commit credentials to Git. They live only in your local AWS config.

---

## Redeploy from Scratch

### Step 1 — Clone the repo

```bash
git clone https://github.com/Vasanth1602/iii-distributed-inference.git
cd iii-distributed-inference
```

### Step 2 — Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_region   = "ap-south-1"    # your preferred AWS region
project_name = "iii-inference"
github_repo  = "https://github.com/YOUR_USERNAME/iii-distributed-inference.git"
```

All other values (CIDR blocks, instance types, disk sizes) have sensible defaults and can be left as-is.

### Step 3 — Deploy

```bash
terraform init
terraform plan    # review what will be created
terraform apply   # type yes when prompted
```

Terraform creates 17 resources:
- VPC, public subnet, private subnet
- Internet Gateway, NAT Gateway, route tables
- IAM role + instance profile (SSM access)
- Two security groups
- Two EC2 instances

### Step 4 — Wait for bootstrap

**Wait 10–12 minutes** after `terraform apply` completes. Both VMs run startup scripts on first boot that install all dependencies and download the model (~500MB). You will see the outputs immediately but the services need time to come up.

```bash
# Get your public IP
terraform output gateway_public_ip

# Get instance IDs for debugging
terraform output gateway_instance_id
terraform output inference_instance_id
```

### Step 5 — Verify services are running

Shell into each VM using AWS SSM (no SSH keys needed):

```bash
# Gateway VM
aws ssm start-session --target <gateway_instance_id> --region ap-south-1

# Check services
sudo systemctl status iii-engine
sudo systemctl status caller-worker
sudo systemctl status nginx
```

```bash
# Inference VM
aws ssm start-session --target <inference_instance_id> --region ap-south-1

# Check service
sudo systemctl status inference-worker
sudo journalctl -u inference-worker -n 50
```

### Step 6 — Test the API

```bash
curl -X POST http://$(terraform output -raw gateway_public_ip)/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is 2+2?"}]}'
```

### Tear down

```bash
terraform destroy
```

Removes all 17 resources. NAT Gateway charges ~$0.045/hr so destroy when done.

---

## Security Groups

| Port | Gateway VM | Inference VM |
|---|---|---|
| 80 | ✅ Open to internet | ❌ Not applicable |
| 443 | ✅ Open to internet | ❌ Not applicable |
| 49134 (iii engine WS) | ✅ From private subnet only | ❌ No inbound |
| 3111 (iii HTTP) | ❌ Internal only — nginx handles this | ❌ No inbound |
| 22 (SSH) | ❌ Not open — SSM used instead | ❌ Not open |

Workers are completely unreachable from the public internet. The inference-worker-vm has zero inbound rules — it only makes outbound connections to the engine on the gateway.

---

## Debugging

### Check worker logs

```bash
# On gateway VM via SSM
sudo journalctl -u iii-engine -f
sudo journalctl -u caller-worker -f

# On inference VM via SSM
sudo journalctl -u inference-worker -f
```

### Check bootstrap log (if services didn't start)

```bash
# Gateway VM
sudo cat /var/log/gateway-userdata.log

# Inference VM
sudo cat /var/log/inference-userdata.log
```

### Check registered functions

```bash
# On gateway VM
curl http://localhost:3111/api/engine/functions/list \
  -H "Content-Type: application/json" -d '{}'
```

You should see `inference::run_inference`, `inference::get_response`, and `http::run_inference_over_http` in the list. If not, the inference-worker is still loading the model — wait and retry.

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `404` from curl | Workers not registered yet | Wait 2–3 more minutes and retry |
| `inference-worker` inactive | Model still downloading | `journalctl -u inference-worker -f` and watch |
| `nc -z 10.0.1.10 49134` fails | Engine not up yet | `systemctl restart iii-engine` on gateway |
| Gateway services not started | Bootstrap script failed | Check `/var/log/gateway-userdata.log` |

---

## Deployment Changes Made

These changes were required to make the quickstart code work in a cloud deployment environment. All are documented here so the reasoning is clear.

### 1. Model changed — gemma-3-270m → Qwen2.5-0.5B

**Original:** `ggml-org/gemma-3-270m-GGUF`
**Changed to:** `Qwen/Qwen2.5-0.5B-Instruct-GGUF`

The original Gemma 3 GGUF model uses the `gemma3` architecture which is not supported by `transformers` for GGUF loading. Every version of `transformers` tested raised:
```
ValueError: GGUF model with architecture gemma3 is not supported yet.
```
The Qwen2.5-0.5B model is the same size class, also quantized GGUF Q8, and is fully supported. The developer had already included it as a commented alternative in the original `inference_worker.py`.

### 2. iii sandbox bypassed — workers run as direct systemd processes

**Original approach:** `iii --config config.yaml` with `worker_path` entries auto-starts workers inside iii's sandbox runtime.

**Why it doesn't work:** The iii sandbox requires KVM virtualization. Standard cloud VMs (and Docker containers) do not expose `/dev/kvm` to processes by default. When tested locally in Docker, the symptoms were:
- Workers appeared to start
- Functions never registered with the engine
- All API requests returned 404

**Fix:** Removed `worker_path` entries from `config.yaml`. Workers are started as separate systemd services that connect directly to the engine over WebSocket. The engine and workers are decoupled — the engine does not need to know about or manage the worker processes.

This is actually the cleaner production approach: each component managed independently by systemd with its own restart policy, logging to journald, and health checks.

### 3. Dependency versions pinned

**Original `requirements.txt`:** No versions pinned — latest packages pulled at install time.

**Problem:** `pip install transformers` pulled `transformers==5.9.0` which conflicted with `gguf==0.10.0`'s version reporting. `pip install gguf` pulled `gguf==0.10.0` which used `np.ndarray.newbyteorder()` removed in NumPy 2.x.

**Fix:** Pinned stable working combination:
```
transformers==4.50.0
gguf==0.10.0
numpy==1.26.4
torch==2.4.1+cpu  (CPU-only build — no CUDA libraries)
sentencepiece
```

The CPU-only torch build (`+cpu`) is critical — the standard `torch` package downloads 2GB+ of NVIDIA CUDA libraries that are useless on CPU-only instances and filled the 20GB disk.

### 4. iii-http host binding changed

**Original:** `host: 127.0.0.1` (localhost only)
**Changed to:** `host: 0.0.0.0` (all interfaces)

Required so nginx on the same VM can proxy requests to port 3111. With `127.0.0.1`, the iii HTTP API only accepted connections from localhost.

### 5. config.yaml worker_path entries removed

The original `config.yaml` had hardcoded absolute paths pointing to the developer's laptop:
```yaml
worker_path: /Users/anuran/Alchemyst/hiring/...
```
These are removed. Workers are managed by systemd, not by the iii engine directly.

---

## Production Hardening

### Network
- Add TLS. Currently traffic is plain HTTP. Use ACM with an Application Load Balancer or Certbot on the gateway VM to terminate HTTPS.
- Tighten security groups further. The gateway's port 49134 allows from the entire private subnet. Locking it to the inference VM's specific security group is more precise.
- Remove the NAT Gateway after initial deployment. Workers only need internet access during bootstrap to download packages and the model. After that, NAT Gateway is an unnecessary cost and attack surface. Use a VPC endpoint for S3 if the model is moved there.

### Authentication
- Add an API key to the nginx layer. Currently anyone who knows the IP can call the inference API.
- Lock down SSM with IAM condition keys so only specific IAM users can start sessions.

### Reliability
- Wrap both VMs in Auto Scaling Groups with a minimum of 1. If a VM terminates, ASG replaces it automatically.
- Add an ALB health check on `/health`. Currently there is no automated detection of a failed inference worker.
- The model download happens on every fresh VM. Pre-bake an AMI with the model already loaded so new VMs start in under 2 minutes instead of 10+.

### Observability
- The iii engine already exposes Prometheus metrics on `:9464`. Scrape this with CloudWatch Agent or a managed Prometheus service.
- Ship journald logs to CloudWatch Logs for centralized visibility across both VMs.

---

## What I Would Do Differently at 100x Model Size

A 100x larger model (roughly 27B parameters) changes almost everything about the deployment.

**Compute:** CPU inference is no longer viable. At this scale you need GPU instances — at minimum a `g4dn.xlarge` (1× T4, 16GB VRAM) or `g5.xlarge` (1× A10G, 24GB VRAM) on AWS. The model itself at Q8 would be ~27GB, requiring tensor parallelism across multiple GPUs or a multi-node setup.

**Inference server:** Replace the raw `transformers` generate call with a purpose-built inference server like **vLLM** or **TGI (Text Generation Inference)**. These handle continuous batching, KV-cache management, and multi-GPU tensor parallelism — none of which the current setup does. The iii worker would become a thin wrapper that POSTs to the vLLM HTTP API rather than running the model in-process.

**Scaling:** At this size, inference is the bottleneck. The iii engine and caller-worker can stay on small VMs. The inference tier needs an Auto Scaling Group of GPU instances behind a load balancer, scaled on GPU utilization. Add a queue (SQS or Redis) in front so traffic spikes don't drop requests — workers pull from the queue at their own pace.

**Cost:** GPU instances cost $0.50–$3.50/hr. Use spot instances for batch workloads (60–80% cheaper) and on-demand for latency-sensitive paths. Pre-bake the model weights into a custom AMI so spot instance replacements start in under 60 seconds.

**Storage:** The model weights (~27GB) should live in S3 and be pulled to instance-local NVMe on startup, not baked into every AMI. Use `s5cmd` for fast parallel S3 downloads.