FROM ubuntu:22.04

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY start.py /work/start.py

# The orchestrator will copy /IPlist.txt into the container.
CMD ["sleep", "infinity"]
