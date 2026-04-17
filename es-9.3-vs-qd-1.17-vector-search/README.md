# Elasticsearch 9.3 vs Qdrant 1.17: Vector search performance

This benchmark compares approximate nearest neighbor (ANN) vector search between **Elasticsearch 9.3** (BBQ disk-backed vectors) and **Qdrant 1.17** (HNSW with binary quantization and rescore oversampling) under matched hardware and the same query workload.

## Configuration

| | Elasticsearch 9.3 | Qdrant 1.17 |
| --- | --- | --- |
| **Vector index** | `dense_vector` with `index_options.type: bbq_disk` | HNSW + **binary** quantization (`always_ram: true`) |
| **HNSW (graph)** | BBQ / server defaults for the template | `m` = 16, `ef_construct` = 100 |
| **Similarity** | Cosine | Cosine |
| **Sharding** | 3 shards, 1 replica | 3 shards, replication factor 2 |

## Dataset

- **wiki-dpr-e5-768** — DPR/Wikipedia-style passages with **768-dimensional** E5 embeddings (cosine)
- **recall@100** sweep over engine-specific tuning parameters (Elasticsearch: `k` / `visit_percentage` / `oversample`; Qdrant: `hnsw_ef` / `oversampling`)
- Pre-computed ground truth in the query parquet for recall calculation

## Infrastructure

- **6 data nodes** per engine cluster (`workerCount` in `variables/k8s.yml`; pool `n2d-standard-16` in `variables/terraform.tfvars`, `pd-balanced` boot disk)
- **200 Gi** persistent volume per data pod (`premium-rwo` in `variables/k8s.yml`)
- GKE on GCP (**us-central1-a** in `variables/terraform.tfvars`)
- Separate clusters for Elasticsearch and Qdrant (`engines/<stack>/terraform/`)

## Key results (recall@100)

Matched **recall** tiers from `analyze/output/recall@100_summary.csv` (Jingra **average latency**, ms). Values are from the committed analysis run; rerun `make analyze` after new evaluations to refresh.

| ~Recall | Elasticsearch 9.3 | Avg latency (ms) | Qdrant 1.17 | Avg latency (ms) |
| --- | --- | ---: | --- | ---: |
| ~80% | 79.6% | 10 | 80.3% | 144 |
| ~88% | 88.3% | 14 | 88.3% | 306 |
| ~92% | 91.9% | 17 | 92.1% | 494 |
| ~96% | 96.1% | 28 | 95.8% | 941 |
| ~98% | 97.6% | 38 | 97.8% | 1633 |
| ~99% | 98.6% | 53 | 98.5% | 2260 |

Full per-parameter rows: `analyze/output/recall@100_full_results.csv`. Plots (if generated for that run): `analyze/output/`.

## Summary

- On this workload, Elasticsearch 9.3 with BBQ delivers **much lower average latency** than Qdrant 1.17 with binary quantization + oversampling at similar recall@100 (for example **~53 ms vs ~2260 ms** near **~99%** recall in the table above).
- The gap is already large at moderate recall (~**14×** at ~80% recall: ~10 ms vs ~144 ms).
- Raw timings and CSV exports for your own runs live under `analyze/output/` after `make analyze`.

## Reproducing the benchmark

Run from this directory. Copy and fill `secrets/.secrets.env.example` → `secrets/.secrets.env` and `secrets/terraform.tfvars.example` → `secrets/terraform.tfvars` first. Use the same `JINGRA_IMAGE` value everywhere you pass it below (your registry’s Jingra image tag). Further targets and env vars: `make help`.

```bash
make qdrant terraform-apply
make qdrant k8s-apply
make qdrant jingra-load JINGRA_IMAGE=<jingra-image>
make qdrant jingra-eval JINGRA_IMAGE=<jingra-image>

make elasticsearch terraform-apply
make elasticsearch k8s-apply
make elasticsearch jingra-load JINGRA_IMAGE=<jingra-image>
make elasticsearch jingra-eval JINGRA_IMAGE=<jingra-image>

make analyze JINGRA_IMAGE=<jingra-image>
```

`make analyze` writes CSVs (and plots, if configured) under `analyze/output/`.

## Infrastructure setup

Terraform for provisioning each GKE cluster:

- `engines/elasticsearch/terraform/` — Elasticsearch cluster
- `engines/qdrant/terraform/` — Qdrant cluster
