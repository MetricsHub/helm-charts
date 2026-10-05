---
date_published: 2026-10-05
date_modified: 2026-10-05
canonical_url: https://metricshub.org/helm-charts/charts/m8b-stack/KNOWLEDGE-BASE.html
---

# Knowledge base

The M8B bot answers documentation questions with `search_knowledge_base`, a local index stored on the bot volume. The `index` stage builds it with a Job that runs the indexer shipped in the M8B image itself, with the bot's configuration, volume and runtime Secret. No other crawler is installed. Starting from an empty volume, the indexer fetches and indexes the official MetricsHub documentation; the M8B image decides what that corpus contains, so the number of documents and the duration (about 20 minutes on the reference lab) are not guaranteed.

## Configuration

```yaml
m8b:
  embeddings:
    baseUrl: http://vllm.example.internal:8000/v1   # OpenAI-compatible endpoint, ending in /v1
    model: embedding-model                          # exact embedding model ID
  knowledgeBase:
    bootstrap:
      enabled: true
      mode: if-missing       # keep an existing non-empty index; "always" rebuilds it
      timeoutSeconds: 3600   # Job deadline, separate from the Helm timeout
```

- The embedding endpoint needs network egress: `m8b.ai.egress` covers it when it is the same server as the chat endpoint, otherwise set `m8b.embeddings.egress` (or `podEgress` for an in-cluster server).
- If the embedding endpoint needs a different key than the chat endpoint, add it to the `m8b-runtime` Secret as `AI_EMBEDDING_API_KEY`.
- The index records the embedding configuration. After changing the embedding model or endpoint, rebuild it.
- Embedding prefixes and input types, described in the bot's [configuration reference](https://metricshub.org/m8b-slack/CONFIGURATION.html#knowledge-base), are set with `m8b.embeddings.queryPrefix`, `documentPrefix`, `queryInputType` and `documentInputType`. The chart rejects the corresponding variables in `m8b.extraConfig`, because it manages them.

## Build, rebuild

Follow [GETTING-STARTED.md](GETTING-STARTED.html), step 11: stop the bot, run `stage=index`, save the Job logs, delete the Job, then `stage=run`. The bot and the Job must never use the volume at the same time, which is why the bot is stopped explicitly first: do not upgrade a running bot straight into `index` and expect Helm to wait for its Pod.

To **force a rebuild** of an existing index, run the same step 11 with `--set m8b.knowledgeBase.bootstrap.mode=always` on the `stage=index` command only. The previous index is backed up next to the new one, and restored if the rebuild fails. The final `stage=run` command, without that flag, returns to `if-missing`.

## Good to know

- A bot restart does **not** reindex: a new bot Pod loads the existing index from the volume.
- The index file may only be written at the end; no visible progress on disk is not a sign of a hang. Follow the Job log instead.
- On failure, the Job and its log are kept and the bot stays stopped. Read the log, fix the cause, delete the Job (Helm does not remove a Job created by a failed revision), then run `stage=index` again.
- Do not `helm rollback` to an `index` revision: that would stop the bot and start an indexer again.
- A Ready bot does not prove the index works: finish with a Slack question that only the documentation answers.
- The index Job has no Kubernetes API credentials.
