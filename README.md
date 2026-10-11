# The Deathstar

The Deathstar splits a list of IP addresses into small shards, runs one Docker worker per shard, and collects each worker's files. It is a small orchestrator for authorized recon jobs; the worker image decides what work to do.

## Quick start

You need Ruby 3.1 or newer and a running Docker daemon. The included worker is a harmless demo: it records the IPs it received.

```bash
docker build -t deathstar-demo:latest docker/demo-worker
printf '10.0.0.1\n10.0.0.2\n' > targets.txt
ruby DeathStar.rb --ip-list targets.txt --image deathstar-demo:latest \
  --output-dir SCAN-RESULTS --command 'python3 start.py'
```

A run creates `SCAN-RESULTS/<run-id>/manifest.json`, plus one `worker-0001/` directory per shard. Each worker directory contains `targets.txt`, `stdout.log`, `stderr.log`, and `results/` copied from `/home/` in the container. Existing runs are never overwritten.

Preview the shards without Docker:

```bash
ruby DeathStar.rb --ip-list targets.txt --output-dir SCAN-RESULTS --dry-run
```

## Configuration

Command line options override environment variables. Run `ruby DeathStar.rb --help` for the full list.

| Option | Environment variable | Default | Purpose |
| --- | --- | --- | --- |
| `--ip-list` | `IP_LIST` | `/home/ubuntu/IPlist.txt` | Input file |
| `--output-dir` | `OUTPUT_DIR` | `/home/ubuntu/SCAN-RESULTS` | Per-run output parent |
| `--image` | `IMAGE` | `ubuntu:v10` | Worker image |
| `--command` | `EXEC_CMD` | `python start.py` | Worker command, run through `sh -lc` |
| `--shard-size` | `SHARD_SIZE` | `10` | IPs per worker |
| `--max-parallel` | `MAX_PARALLEL` | `4` | Maximum simultaneous workers |
| `--timeout` | `TIMEOUT` | `1800` | Seconds allowed for a worker command |
| `--docker-timeout` | `DOCKER_TIMEOUT` | `60` | Seconds allowed for each Docker setup, copy, or removal command |
| `--confirm-public` | `CONFIRM=YES` | Off | Confirm authorization for public IPs |
| `--dry-run` | — | Off | Validate and write a plan without Docker |
| `--keep-containers` | — | Off | Keep the run's containers for inspection |

Input supports IPv4 and IPv6 addresses, blank lines, and `#` comments. Duplicate addresses are removed while preserving order. Hostnames and CIDR ranges are rejected so the number of workers is predictable. Public IPs require an explicit confirmation; interactive runs can type `YES`, or automation can pass `--confirm-public`/`CONFIRM=YES`. Only use this tool on targets you are authorized to test.

The worker image must stay running when started with `docker run -d` and include `sh`. The orchestrator copies the shard to `/IPlist.txt`, runs the configured command, then copies `/home/` to the worker's `results/` directory. The demo Dockerfile shows a working image.

The manifest records worker status, exit code, timeout, and any setup or copy error. A failed worker does not stop other shards. The process exits `0` when all workers succeed, `1` when any worker fails, `2` on invalid setup, and `130` on interruption. By default it removes only containers created for the current run. With `--keep-containers`, the names to inspect or remove are recorded in the manifest.

## Development

```bash
ruby -c DeathStar.rb
ruby test/deathstar_test.rb
```

Tests use a fake Docker runner, so they do not need a daemon. A real Docker integration run still requires Docker.
