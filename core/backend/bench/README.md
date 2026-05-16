# bench — vector store bake-off

three-way comparison: **qdrant** vs **clickhouse** vs **duckdb-vss**.
local only; the winner gets promoted into `infra/` after phase 7.

## quickstart (once phase 2 lands)

```bash
# bring qdrant + clickhouse up locally
docker compose up -d

# load: writes the same vector set into all three stores
cargo run -p bench --bin bench-load -- --source synthetic --n 100000
cargo run -p bench --bin bench-load -- --source real      # uses transcripts produced by phase 1/2

# query: runs identical k-nn + filtered k-nn against each
cargo run -p bench --bin bench-query -- --queries data/queries.txt --report report.md

# teardown
docker compose down -v
```

## what we measure

| metric                            | why                                                   |
|-----------------------------------|-------------------------------------------------------|
| insert throughput (vectors / sec) | how long ingest takes at scale                        |
| query p50 / p95 / p99             | tail latency under realistic concurrency              |
| **filtered** query p50/p95/p99    | with `media_kind` + `folder` predicate — usually the splitter |
| recall@10                         | vs brute-force ground truth                           |
| on-disk size                      | storage cost per million vectors                      |
| rss at idle                       | memory baseline                                       |
| cold-query latency                | first query after restart — matters for low-traffic   |

Output: `report.md` — committed alongside the choice.

## phase 0 status

scaffold + compose only. binaries are stubs until phase 2 produces
real embeddings via fastembed + bge-m3.
