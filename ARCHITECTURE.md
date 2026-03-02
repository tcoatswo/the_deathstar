# Architecture (high-level)

```
IP_LIST (targets.txt)
      |
      v
  Sharder (Ruby)
      |
      +--> deathstar1 (Docker container) -- runs EXEC_CMD --> writes under /home/
      |
      +--> deathstar2 (Docker container) -- runs EXEC_CMD --> writes under /home/
      |
      ...
      |
      v
Collector loop (every 60s):
  docker cp deathstarN:/home/  -> OUTPUT_DIR/deathstarN-results/
```
