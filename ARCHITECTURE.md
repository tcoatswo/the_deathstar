# Architecture

`DeathStar.rb` validates and deduplicates the IP list, then splits it into fixed-size shards. A bounded thread pool processes the shards independently. Each worker starts a uniquely named Docker container labeled with the run ID, copies its `targets.txt` to `/IPlist.txt`, executes the configured command, and copies `/home/` into its own results directory.

Each run receives a unique output directory. `manifest.json` is replaced atomically as workers change state, so completed and failed shards are visible while a run is in progress. Worker stdout and stderr are saved separately. Container cleanup uses the exact names created by the run; it does not scan for or remove unrelated containers.

The demo worker only writes the received targets to `/home/output/demo.txt`.
