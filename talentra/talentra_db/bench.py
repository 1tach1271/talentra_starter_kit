import json, re, os, statistics, subprocess, sys, csv

# Connection — can be overridden by env vars
db   = sys.argv[1] if len(sys.argv) > 1 else "talentra"
runs = int(sys.argv[2]) if len(sys.argv) > 2 else 30
out  = sys.argv[3] if len(sys.argv) > 3 else "benchmark_results.csv"

# Build psql connection args from env vars (mirrors psql behaviour)
host = os.environ.get("PGHOST", "localhost")
port = os.environ.get("PGPORT", "5432")
user = os.environ.get("PGUSER", "talentra")

PSQL = ["psql", "-h", host, "-p", port, "-U", user, "-d", db, "-At", "-v", "ON_ERROR_STOP=1"]

blocks = re.findall(r"-- (Q\d+) ([^\n]*)\n(@tx )?([^\n]+)", open("13_benchmark.sql").read())

def psql(sql):
    return subprocess.run(PSQL + ["-c", sql], capture_output=True, text=True, check=True).stdout

def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(round(p / 100 * (len(v) - 1))))]

rows = []
for qid, desc, tx, sql in blocks:
    sql     = sql.strip().rstrip(";")
    explain = f"explain (analyze, format json) {sql}"
    times   = []
    for _ in range(runs):
        if tx:
            res = subprocess.run(
                ["psql", "-h", host, "-p", port, "-U", user, "-d", db, "-At",
                 "-c", "begin", "-c", explain, "-c", "rollback"],
                capture_output=True, text=True, check=True
            ).stdout
        else:
            res = psql(explain)
        m    = re.search(r"\[.*\]", res, re.S)
        plan = json.loads(m.group(0))[0]
        times.append(plan["Execution Time"] + plan.get("Planning Time", 0))

    plan_text = subprocess.run(
        ["psql", "-h", host, "-p", port, "-U", user, "-d", db, "-At",
         "-c", "begin", "-c", f"explain (analyze, buffers) {sql}", "-c", "rollback"],
        capture_output=True, text=True
    ).stdout
    open(f"plan_{qid}.txt", "w").write(plan_text)

    rows.append([qid, desc,
                 round(pct(times, 50), 3),
                 round(pct(times, 95), 3),
                 round(pct(times, 99), 3)])
    print(qid, desc, rows[-1][2:], flush=True)

with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["query", "description", "p50_ms", "p95_ms", "p99_ms"])
    w.writerows(rows)

print(f"\nResults written to {out}")
