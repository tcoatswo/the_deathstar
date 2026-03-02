import os
from datetime import datetime

in_path = "/IPlist.txt"
out_dir = "/home/output"
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "demo.txt")

def main():
    try:
        with open(in_path, "r", encoding="utf-8") as f:
            targets = [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        targets = []

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(f"Deathstar demo run at {datetime.utcnow().isoformat()}Z\n")
        f.write(f"Targets ({len(targets)}):\n")
        for t in targets:
            f.write(f"- {t}\n")

if __name__ == "__main__":
    main()
