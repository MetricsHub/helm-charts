# Local KB lifecycle - standalone chart

The index Job runs the M8B image's indexer using the bot image, PVC, ConfigMap, runtime Secret and embedding
configuration. It does not install an additional crawler. In the supplied operator run, M8B initialized its
official corpus from an initially empty directory; the upstream image controls that source behavior.
Corpus count and runtime are not fixed guarantees. Budget a separate long timeout.

Set `m8b.embeddings.baseUrl`, `m8b.embeddings.model` and `m8b.knowledgeBase.bootstrap.enabled: true` in the
site profile. Default mode `if-missing` preserves an existing nonempty index. Configure explicit model egress.
The generic example shows these keys. Tokens belong in the runtime Secret; an embedding-specific key is optional.

## Direct Helm maintenance

The following assumes a successful Doctor and the variables NS, RELEASE, SITE, CHART and L set as in README.
Do NOT upgrade a running bot directly into index and assume Helm waits for its Pods before starting the Job.
Stop it explicitly and verify all consumers first:

```bash
kubectl -n "$NS" scale deployment -l "$L,app.kubernetes.io/component=m8b" --replicas=0
kubectl -n "$NS" wait --for=delete pod -l "$L,app.kubernetes.io/component=m8b" --timeout=300s
kubectl -n "$NS" get pods,jobs -l "$L" -o wide
# Stop here if another Pod/Job uses the bot PVC; do not start simultaneous indexers.
helm upgrade "$RELEASE" "$CHART" -n "$NS" -f "$SITE"   --set stage=index --wait --wait-for-jobs --timeout 65m
kubectl -n "$NS" logs -l "$L,app.kubernetes.io/component=knowledge" -c index --tail=-1 > kb-index.log
# Continue only on Job success. Keep the failed Job and bot stopped on error.
# Delete the finished Job first so its Pod releases the bot PVC before the new bot starts.
kubectl -n "$NS" delete job -l "$L,app.kubernetes.io/component=knowledge" --wait=true
helm upgrade "$RELEASE" "$CHART" -n "$NS" -f "$SITE"   --set stage=run --wait --timeout 15m
```

The Job name carries the Helm revision, so re-running `stage=index` after a failure never hits the
"Job spec is immutable" error: Helm replaces the previous Job.

The Job validates the resulting index. For a forced rebuild change bootstrap.mode deliberately, save backups
and return it to if-missing afterwards. A plain bot restart does NOT require reindexing. The index may be
written only at completion; absent growth during indexing is not proof of a hang. The new bot process loads
the cached index. Finish with a real Slack request using `search_knowledge_base`; readiness alone is insufficient.
Do not blindly `helm rollback` to an old index maintenance revision. The Job has no Kubernetes API credentials.
