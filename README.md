# The Deathstar

Dockerized **target sharding** for parallel recon workflows.

Given a list of targets, The Deathstar splits them into shards (default: 10 per shard), launches one container per shard, copies the shard into each container, and executes a configurable command inside each container (default: `python start.py`).

## Why it matters
When you have authorized scope that’s large enough, the bottleneck is often orchestration: getting repeatable, parallel workers stood up quickly and collecting results consistently. This project is a lightweight, hackable orchestrator for that job.

## Scope / ethics
This tool is intended for **authorized security testing and lab environments**. You are responsible for ensuring you have explicit permission to scan any targets you provide.

## Quick start (reproducible demo)
The repo includes a toy worker image that simply reads targets and writes a small output file.

```bash
# 1) Build the demo worker image
cd docker/demo-worker
docker build -t deathstar-demo:latest .

# 2) Create a targets file
printf "10.0.0.1\n10.0.0.2\n" > ./targets.txt

# 3) Run
IP_LIST="$PWD/targets.txt" \
IMAGE="deathstar-demo:latest" \
OUTPUT_DIR="$PWD/SCAN-RESULTS" \
ruby ./DeathStar.rb
```

Outputs land under `OUTPUT_DIR/deathstar<N>-results/`.

## Configuration (environment variables)
Defaults preserve the original behavior.

- `IP_LIST` (default: `/home/ubuntu/IPlist.txt`)
- `OUTPUT_DIR` (default: `/home/ubuntu/SCAN-RESULTS/`)
- `IMAGE` (default: `ubuntu:v10`)
- `SHARD_SIZE` (default: `10`)
- `EXEC_CMD` (default: `python start.py`)
- `MAX_MINUTES` (default: `30`) — how many minutes to keep copying results
- `CONFIRM` (optional) — set to `YES` to bypass the public-target confirmation prompt

## How it works (high level)
1. Read `IP_LIST`
2. Split into shards of `SHARD_SIZE`
3. Start `N` containers from `IMAGE` named `deathstar1..N`
4. Copy shard file into each container as `/IPlist.txt`
5. Run `EXEC_CMD` inside each container
6. Every minute, copy `/home/` from each container into `OUTPUT_DIR/deathstar<N>-results/`
7. Clean up containers created by this tool

## Notes on worker images
The original workflow assumed an image (e.g., `ubuntu:v10`) that already contained your scanning tools and a `start.py` that performs the work. The included demo worker is a safe template you can extend.

## About
Inputs a list of targets and creates Docker worker containers to parallelize recon/scanning workflows.

---

> "I think it is time we demonstrated the full power of this station. Set your course for Alderaan." — Governor Tarkin
