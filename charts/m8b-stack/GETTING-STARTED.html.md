---
date_published: 2026-10-06
date_modified: 2026-10-06
canonical_url: https://metricshub.org/helm-charts/charts/m8b-stack/GETTING-STARTED.html
---

# Getting started with the m8b-stack chart

A complete, step-by-step installation for someone who has never used Helm, from an empty cluster to a bot that answers in Slack. It follows a typical on-premises lab and uses [examples/lab-values-example.yaml](examples/lab-values-example.yaml). Values marked **CHANGE ME** in that file are examples: replace them with yours.

| Item | Example value used in this guide |
| --- | --- |
| Cluster | kubeadm, 3 nodes: kube-01 (192.0.2.11), kube-02 (192.0.2.12), kube-03 (192.0.2.13) |
| Pod / Service CIDR | 10.244.0.0/16 / 10.96.0.0/12 |
| Storage | no StorageClass → local volumes on kube-01 |
| Namespace, release | `m8b-metricshub`, `m8b-stack` |
| LLM (vLLM) | `http://vllm.example.internal:8000/v1` (192.0.2.50), models `chat-model` / `embedding-model` |
| Slack workspace | `T0000000000` |
| Admin networks | LAN 198.51.100.0/24, VPN 203.0.113.0/24 |
| MetricsHub Web UI | [https://192.0.2.11:31888](https://192.0.2.11:31888) |
| Prometheus | [http://192.0.2.11:30909](http://192.0.2.11:30909) (no authentication, no TLS) |

Every command runs **on kube-01 as root, in one SSH session**: later steps reuse variables set earlier. kube-01 is a control-plane node, so it already has `kubectl` and `/etc/kubernetes/admin.conf`, and it is the node that holds the local volumes. If the session drops, re-run [the session variables](#session-variables).

Time: about 45 minutes, plus about 20 minutes of knowledge-base indexing.

**What you need at hand:**

- registry credentials for the private registry `docker.metricshub.com` (from your MetricsHub onboarding email, or [support.metricshub.com](https://support.metricshub.com));
- the Slack bot token (`xoxb-…`) and app-level token (`xapp-…`, Socket Mode) of your M8B Slack app. To create the app, see [Create the Slack app](https://metricshub.org/m8b-slack/#1-create-the-slack-app);
- the API key of your OpenAI-compatible (vLLM) endpoint. Check that your backend and models are supported in [AI backends](https://metricshub.org/m8b-slack/BACKENDS.html).

---

## Step 1 — Session variables and cluster facts

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=m8b-metricshub
RELEASE=m8b-stack
CHART=metricshub/m8b-stack        # from the MetricsHub Helm repository, added in step 3
VALUES=/root/my-values.yaml
L="app.kubernetes.io/instance=$RELEASE"
S=/root/.m8b-secrets
kubectl get nodes -o wide          # all nodes Ready; note their names and INTERNAL-IP
```

Note the answers to these commands; the values file needs them:

```bash
# Pod and Service ranges -> network.podCidrs / network.serviceCidrs
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep -E 'podSubnet|serviceSubnet'
# Network plugin: it must enforce NetworkPolicies (Cilium, Calico... yes; Flannel alone: no, policies are ignored)
kubectl -n kube-system get pods -o name | grep -E 'cilium|calico|flannel|weave' | head -3
# Storage: "No resources found" -> local volumes (this guide); a StorageClass -> see examples/portable.yaml
kubectl get storageclass
```

## Step 2 — Install Helm

Skip this step if `helm version` already works.

```bash
HELM_VERSION=v4.3.0
cd /tmp
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"
sha256sum -c "helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"     # must print: OK
tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
install -m 755 linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 helm-${HELM_VERSION}-linux-amd64.tar.gz*
cd /root
helm version
```

Helm uses the `KUBECONFIG` set in step 1. There is nothing else to configure.

## Step 3 — Get the chart and write your values file

```bash
helm repo add metricshub https://metricshub.github.io/helm-charts
helm repo update
helm search repo "$CHART" --versions        # every published version
# Pin the latest version: every helm command below installs exactly this one
CHART_VERSION=$(helm search repo "$CHART" -o yaml | sed -n 's/^  version: //p' | head -1); echo "$CHART_VERSION"
# A local copy, only to read the examples and docs
rm -rf /tmp/m8b-chart && helm pull "$CHART" --version "$CHART_VERSION" --untar --untardir /tmp/m8b-chart
cp -n /tmp/m8b-chart/m8b-stack/examples/lab-values-example.yaml "$VALUES"
```

Edit `$VALUES` and replace **every `CHANGE ME`** value with yours, using the facts from step 1:

- `storage.local.node`: the node that holds the data (here kube-01, the node you are on);
- `network.podCidrs`, `network.serviceCidrs`: the ranges from step 1;
- `metricshub.egress`: the networks the agent monitors. **Empty means nothing is monitored**. Which hosts it monitors, and how, is the agent configuration (`metricshub.config.text`): see [Resource settings](https://metricshub.com/docs/latest/configuration/resource-settings);
- `exposure.adminCidrs`: the networks allowed to open the Web UI and Prometheus;
- `m8b.slackTeamId`: your workspace ID, from the Slack browser URL `app.slack.com/client/T…/…`;
- `m8b.ai` / `m8b.embeddings`: endpoint URL, exact model IDs (`curl -s <baseUrl>/models`), and the endpoint IP and port in `ai.egress`.

Check the file offline. Nothing is applied to the cluster, and errors name the value to fix:

```bash
for st in core check run index; do
  helm template "$RELEASE" "$CHART" --version "$CHART_VERSION" -n "$NS" -f "$VALUES" --set stage=$st > /dev/null && echo "$st OK"
done
```

## Step 4 — Enter the credentials

This script asks for each value without echoing it, then writes one file per credential to `$S`, readable by root only. Nothing ends up in the shell history.

```bash
cat > /root/m8b-secrets.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
S=${S:-/root/.m8b-secrets}
install -d -m 700 "$S" "$S/runtime"
umask 077

ask() {  # ask <prompt> <variable> [required prefix]
  local v
  while :; do
    read -rsp "$1: " v; echo
    [ -n "$v" ] || { echo '  empty, try again'; continue; }
    [ -z "${3:-}" ] || [[ $v == "$3"* ]] || { echo "  must start with $3"; continue; }
    printf -v "$2" '%s' "$v"; return
  done
}

read -rp 'docker.metricshub.com username: ' RU
ask 'docker.metricshub.com password' RP
printf '{"auths":{"docker.metricshub.com":{"auth":"%s"}}}' "$(printf '%s:%s' "$RU" "$RP" | base64 -w0)" \
  > "$S/.dockerconfigjson"
unset RU RP

ask 'Slack bot token (xoxb-...)' V xoxb-; printf '%s' "$V" > "$S/runtime/SLACK_BOT_TOKEN"
ask 'Slack app token (xapp-...)' V xapp-; printf '%s' "$V" > "$S/runtime/SLACK_APP_TOKEN"
ask 'LLM API key' V;                      printf '%s' "$V" > "$S/runtime/AI_API_KEY"
unset V

python3 -m json.tool "$S/.dockerconfigjson" > /dev/null && echo 'dockerconfigjson: valid JSON'
wc -c "$S"/runtime/*      # no file may be 0 bytes
SCRIPT
chmod 700 /root/m8b-secrets.sh
/root/m8b-secrets.sh
```

If the embedding endpoint uses a different key, also write it: `read -rsp 'Embedding API key: ' V; echo; printf '%s' "$V" > "$S/runtime/AI_EMBEDDING_API_KEY"; unset V`.

## Step 5 — Namespace and Secrets

The chart never contains credentials: it reads these Kubernetes Secrets.

```bash
kubectl create namespace "$NS"
kubectl -n "$NS" create secret generic registry-pull --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="$S/.dockerconfigjson"
kubectl -n "$NS" create secret generic m8b-runtime --from-file="$S/runtime/"
kubectl -n "$NS" create secret generic searxng-runtime \
  --from-literal=SEARXNG_SECRET="$(head -c 48 /dev/urandom | base64 | tr -d '\n=')"
kubectl -n "$NS" get secrets
```

### 5b. Check access to the private images

Run this before going further: it proves the registry credentials can pull both private images, the MetricsHub Enterprise agent and the M8B bot, in the versions of the chart you pinned. `--image-pull-policy=Always` forces a real download: without it, a node that already has an image reuses it without contacting the registry, and the credentials are not tested at all.

```bash
for img in $(helm show values "$CHART" --version "$CHART_VERSION" | grep -oE 'docker\.metricshub\.com/[^ ]+'); do
  kubectl -n "$NS" delete pod pull-test --ignore-not-found --wait=true > /dev/null
  kubectl -n "$NS" run pull-test --image="$img" --restart=Never --image-pull-policy=Always \
    --overrides='{"spec":{"imagePullSecrets":[{"name":"registry-pull"}]}}' --command -- sleep 5 > /dev/null
  sleep 60; echo "== $img"
  kubectl -n "$NS" describe pod pull-test | grep -Ei 'pulled|failed|errimage|denied|unauthorized'
done
kubectl -n "$NS" delete pod pull-test --ignore-not-found
```

- `Successfully pulled image` for both images: continue.
- `denied` or `unauthorized`: the credentials do not cover that image. Get the right ones, re-run step 4, then `kubectl -n "$NS" delete secret registry-pull` and the `create` command above.
- `already present on machine`: the download was not forced. Check that the command contains `--image-pull-policy=Always`.

When the stack works, delete the credential files with `rm -rf "$S"`. The values then live only in the cluster.

## Step 6 — Local volume folders

The chart expects `<basePath>/<namespace>/<release>/<component>`, on the node named in `storage.local.node`. The owners must match the user IDs the containers run as.

```bash
DIR=/var/lib/m8b-stack/$NS/$RELEASE
install -d -m 750 -o 1000 -g 1000 "$DIR/agent" "$DIR/bot"
install -d -m 750 -o 65534 -g 65534 "$DIR/prometheus"
ls -ln "$DIR"       # agent and bot: 1000 1000; prometheus: 65534 65534
```

## Step 7 — Stage `core`: agent, Prometheus, SearXNG

The chart installs in **stages**. Each `helm upgrade` applies exactly one stage, and **the last one you ran decides the state**: `check` and `index` keep the bot stopped, and only `run` starts it.

| Stage | Runs | Bot |
| --- | --- | --- |
| `core` | agent, Prometheus, SearXNG | stopped |
| `check` | the above + Doctor Job | stopped |
| `run` | the above + bot, admin NodePorts | running |
| `index` | the above + knowledge-base index Job | stopped |

```bash
helm upgrade --install "$RELEASE" "$CHART" --version "$CHART_VERSION" -n "$NS" -f "$VALUES" \
  --set stage=core --wait --timeout 15m
kubectl -n "$NS" get pods -o wide
```

Expected:

- `m8b-stack-agent-…`, `m8b-stack-prometheus-…` and `m8b-stack-searxng-…` are `Running`;
- the agent and Prometheus run on kube-01, because their volumes are local to that node.

The embedded OpenTelemetry Collector runs inside the agent container. Check that it uses the chart's config:

```bash
kubectl -n "$NS" exec -c metricshub deploy/m8b-stack-agent -- sh -c \
  'for p in /proc/[0-9]*; do tr "\0" " " < $p/cmdline 2>/dev/null | grep -o "otelcol-contrib --config [^ ]*"; done' | sort -u
```

It should print `otelcol-contrib --config /opt/metricshub/lib/app/../otel/otel-config.yaml`.

## Step 8 — Web UI user and MCP API key

The bot talks to the agent with an API key that **this** agent must issue. In the Enterprise image, the `user` and `apikey` tools live in `/opt/metricshub/bin/`; `-c metricshub` targets the agent container directly.

`apikey create` prints `API key created for alias '…': <uuid> (No expiration)`. Only the UUID (36 characters) may go into the Secret. With the `(No expiration)` suffix, the agent answers **401** to the bot.

```bash
AGENT=deploy/m8b-stack-agent
X="kubectl -n $NS exec -c metricshub"
$X "$AGENT" -- ls /opt/metricshub/bin/    # must list "user" and "apikey"

# Web UI user "admin" (password read without echo)
read -rsp 'Web UI password for admin: ' PW; echo
printf '%s\n' "$PW" | $X -i "$AGENT" -- sh -c \
  'IFS= read -r p; exec /opt/metricshub/bin/user create "$1" --password "$p" --role rw' _ admin
unset PW
$X "$AGENT" -- /opt/metricshub/bin/user list

# MCP API key for the bot, stored in the Secret without being printed
OUT=$($X "$AGENT" -- /opt/metricshub/bin/apikey create "m8b-helm-$(date +%s)")
KEY=$(printf '%s\n' "$OUT" | sed -n "s/.*API key created for alias ['\"][^'\"]*['\"]: *\([A-Za-z0-9_.-]*\).*/\1/p")
if [ -n "$KEY" ]; then
  printf '{"stringData":{"MCP_AGENT_TOKEN":"%s"}}' "$KEY" \
    | kubectl -n "$NS" patch secret m8b-runtime --type merge --patch-file /dev/stdin
else
  echo 'Unexpected output:'; printf '%s\n' "$OUT" | sed -E 's/[A-Za-z0-9_.-]{20,}/<MASKED>/g'
fi
unset OUT KEY
kubectl -n "$NS" get secret m8b-runtime -o go-template='{{index .data "MCP_AGENT_TOKEN" | base64decode}}' | wc -c   # must print 36
```

- **Not 36** (for example 52): the key itself is valid, only the stored value is wrong. Repair it without creating another key:
  
  ```bash
  T=$(kubectl -n "$NS" get secret m8b-runtime -o go-template='{{index .data "MCP_AGENT_TOKEN" | base64decode}}' | cut -d' ' -f1)
  printf '{"stringData":{"MCP_AGENT_TOKEN":"%s"}}' "$T" \
    | kubectl -n "$NS" patch secret m8b-runtime --type merge --patch-file /dev/stdin
  unset T
  ```
- **`Unexpected output`**: the key was still created. Do **not** run `create` again, it would add a second key. Note the printed line, where the key is masked. To list keys: `$X "$AGENT" -- /opt/metricshub/bin/apikey list`. To remove a spare key: `… apikey revoke <alias>`.
- **`user create` fails because the user exists** (step re-run): keep the existing one (`user list`).

## Step 9 — Stage `check`: the Doctor

With the bot still stopped, the Doctor checks:

- the Slack tokens, scopes and workspace;
- Prometheus and its OTLP receiver, and that MetricsHub metrics arrive;
- SearXNG;
- the M8B Doctor itself: LLM chat and embeddings, the MCP connection to the agent, the data directories and the Python sandbox.

```bash
helm upgrade "$RELEASE" "$CHART" --version "$CHART_VERSION" -n "$NS" -f "$VALUES" \
  --set stage=check --wait --wait-for-jobs --timeout 15m
kubectl -n "$NS" logs -l "$L,app.kubernetes.io/component=doctor" --all-containers=true --tail=-1
```

- **Success:** the log ends with `0 failed`. A warning about `M8B_MEDIA_BASE_URL` is expected: images sent to the bot are then passed inline as base64. To configure a media store, see [Images and the media store](https://metricshub.org/m8b-slack/CONFIGURATION.html#images-and-the-media-store) and set the variables through `m8b.extraConfig`.
- **Failure:** fix the cause (see [Troubleshooting](#troubleshooting)), delete the failed Job, then run the same `helm upgrade` again. Each attempt gets a new Job name (`m8b-stack-doctor-<revision>`). Helm does **not** remove a Job created by a failed revision, so delete it yourself:
  
  ```bash
  kubectl -n "$NS" delete job -l "$L,app.kubernetes.io/component=doctor"
  ```
- **`No current metricshub_agent_info sample`** on the very first try: the agent has not exported yet (its collect period is about 1 minute). Wait two minutes and retry.

## Step 10 — Stage `run`: start the bot

```bash
helm upgrade "$RELEASE" "$CHART" --version "$CHART_VERSION" -n "$NS" -f "$VALUES" \
  --set stage=run --wait --timeout 15m
kubectl -n "$NS" get pods
kubectl -n "$NS" logs deploy/m8b-stack-bot -c m8b --tail=50
```

Expected in the bot log:

- `[MCP] Connected to m8b-stack-agent.m8b-metricshub.svc.cluster.local using sse`;
- `[MCP] Indexed N hosts`.

At this stage the log still says `Local knowledge base is empty or not indexed`: step 11 fixes that.

Tests:

- **Slack:** invite the bot to a channel (`/invite @<bot name>`) and ask it a question about your infrastructure.
- **Web UI:** [https://192.0.2.11:31888](https://192.0.2.11:31888) from an admin network. Accept the self-signed certificate, then log in as `admin`. With `externalTrafficPolicy: Local`, use the IP of the node running the agent (kube-01 here).
- **Prometheus:** [http://192.0.2.11:30909](http://192.0.2.11:30909), query `metricshub_agent_info`, which must return at least one series. From the node: `curl -s 'http://192.0.2.11:30909/api/v1/query?query=metricshub_agent_info'`.

## Step 11 — Build the knowledge base (about 20 minutes)

The index Job needs the bot volume to itself, so the bot is stopped first:

```bash
kubectl -n "$NS" scale deployment -l "$L,app.kubernetes.io/component=m8b" --replicas=0
kubectl -n "$NS" wait --for=delete pod -l "$L,app.kubernetes.io/component=m8b" --timeout=300s
helm upgrade "$RELEASE" "$CHART" --version "$CHART_VERSION" -n "$NS" -f "$VALUES" \
  --set stage=index --wait --wait-for-jobs --timeout 65m
```

To follow the indexing, open a **second** SSH session, re-run [the session variables](#session-variables), then:

```bash
kubectl -n "$NS" logs -l "$L,app.kubernetes.io/component=knowledge" -c index -f
```

When the `helm upgrade` returns:

```bash
kubectl -n "$NS" logs -l "$L,app.kubernetes.io/component=knowledge" -c index --tail=-1 > /root/kb-index.log
tail -5 /root/kb-index.log         # must contain "action":"indexed" with a document count
kubectl -n "$NS" delete job -l "$L,app.kubernetes.io/component=knowledge" --wait=true
helm upgrade "$RELEASE" "$CHART" --version "$CHART_VERSION" -n "$NS" -f "$VALUES" \
  --set stage=run --wait --timeout 15m
```

Test: ask the bot something only the MetricsHub documentation answers. It should use `search_knowledge_base`. A typical run indexes several hundred documents. Details: [KNOWLEDGE-BASE.md](KNOWLEDGE-BASE.html), and the bot's [knowledge-base settings](https://metricshub.org/m8b-slack/CONFIGURATION.html#knowledge-base).

---

## Session variables

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=m8b-metricshub; RELEASE=m8b-stack; CHART=metricshub/m8b-stack; VALUES=/root/my-values.yaml
CHART_VERSION=$(helm get metadata "$RELEASE" -n "$NS" -o yaml | sed -n 's/^version: //p')   # the installed version
L="app.kubernetes.io/instance=$RELEASE"; S=/root/.m8b-secrets
```

## Everyday operations

```bash
helm get values "$RELEASE" -n "$NS" --all | grep '^stage:'   # current stage: must be "run" for the bot to run
helm list -n "$NS"                              # release, revision, chart version
helm history "$RELEASE" -n "$NS"                # every upgrade
kubectl -n "$NS" get pods,pvc,svc -o wide
kubectl -n "$NS" logs deploy/m8b-stack-bot -c m8b -f
kubectl -n "$NS" logs deploy/m8b-stack-agent -c metricshub -f
kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -20
```

**Restart the bot.** This only works in stage `run`, because restarting a Deployment scaled to 0 starts nothing. Helm has no restart command; `kubectl rollout restart` is the standard way and does not conflict with Helm.

```bash
kubectl -n "$NS" rollout restart deployment/m8b-stack-bot
kubectl -n "$NS" rollout status deployment/m8b-stack-bot --timeout=10m
```

The new Pod runs its start-up checks again (about 1–2 minutes). The knowledge base is reloaded from disk, not rebuilt.

**Add custom connectors.** The agent's connectors folder is on its volume: copy yours into a folder of their own, then restart the agent. Bundled connectors are refreshed from the image at every start, so do not edit them.

```bash
POD=$(kubectl -n "$NS" get pod -l "$L,app.kubernetes.io/component=metricshub" -o jsonpath='{.items[0].metadata.name}')
kubectl -n "$NS" cp ./my-connectors "$POD":/opt/metricshub/lib/connectors/custom -c metricshub
kubectl -n "$NS" rollout restart deployment/m8b-stack-agent
```

**Change a value.** Edit `$VALUES`, then re-run step 9 if an endpoint or a token changed, and **always** finish with step 10. A configuration change restarts the bot automatically.

**Update the chart.** Look for a newer version and read its `CHANGELOG.md`, then pin it and run steps 9 and 10:

```bash
helm repo update
helm search repo "$CHART" --versions
CHART_VERSION=2.1.0          # example: the version you picked in the list above
```

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| Bot Deployment `0/0`, no bot Pod | The last `helm upgrade` was `check` or `index`: run step 10 |
| Agent `ErrImagePull` / `ImagePullBackOff` | Registry credentials (step 5b) |
| Pod or PVC `Pending` | Missing folders or wrong node: step 6, `kubectl -n "$NS" describe pvc` |
| Pod `CrashLoopBackOff` right after start | Wrong folder owner: `ls -ln "$DIR"` (step 6) |
| Doctor: `Workspace mismatch: received T…` | `m8b.slackTeamId` is wrong: use the ID printed, then re-run step 9 |
| Doctor: HTTP 401 from the LLM | Wrong `AI_API_KEY`: re-run step 4, recreate `m8b-runtime` (step 5), then step 8 |
| Doctor: `MCP … SSE error: Non-200 status code (401)` | `MCP_AGENT_TOKEN` is not the bare 36-character UUID: repair it (end of step 8), then step 9 |
| Doctor: no `metricshub_agent_info` after 5 minutes | Collector: step 7 check, `kubectl -n "$NS" logs deploy/m8b-stack-agent -c metricshub` |
| Doctor: timeouts to the LLM, Slack or monitored hosts | A network policy blocks it: add the destination to `m8b.ai.egress` or `metricshub.egress` |
| `helm template`: `overlaps cluster range` | A `metricshub.egress` CIDR includes the Pod/Service ranges: narrow it or add them to its `except` list |
| Failed `m8b-stack-doctor-N` Job remains | Expected after a failed revision: `kubectl -n "$NS" delete job -l "$L,app.kubernetes.io/component=doctor"` |
| Web UI (:31888) or Prometheus (:30909) unreachable | Source IP outside `adminCidrs`, or wrong node IP (use the node running the Pod); NodePorts exist in `run` and `index` only |
| `helm upgrade`: `another operation is in progress` | Interrupted command: `helm history`, then `helm rollback "$RELEASE" <last good revision> -n "$NS"` |

## Remove everything

Irreversible: metrics, knowledge base, API keys, users, Secrets and images. `helm uninstall` alone keeps the PVCs and PVs on purpose (`helm.sh/resource-policy: keep`), and it never touches the Secrets it did not create.

```bash
# Cluster
helm uninstall "$RELEASE" -n "$NS" --wait --ignore-not-found
kubectl delete namespace "$NS" --wait=true --ignore-not-found
kubectl get pv -o name | grep "$NS-" | xargs -r kubectl delete

# Data and working files on kube-01
rm -rf /var/lib/m8b-stack /tmp/m8b-chart "$S" "$VALUES" /root/m8b-secrets.sh /root/kb-index.log
```

Images: run this on **each** node (kube-01, kube-02, kube-03). It uses `ctr`, which ships with containerd; with `crictl` installed, `crictl rmi` works too.

```bash
ctr -n k8s.io images ls -q | grep -E 'metricshub|m8b-slack|searxng/searxng|prom/prometheus' \
  | xargs -r ctr -n k8s.io images rm
```

Check: the commands below must print nothing.

```bash
kubectl get namespace "$NS" --ignore-not-found
kubectl get pv | grep -i m8b
ctr -n k8s.io images ls -q | grep -E 'metricshub|m8b-slack|searxng|prometheus'
```

Optional, to remove Helm as well: `rm -rf /usr/local/bin/helm /root/.cache/helm /root/.config/helm /root/.local/share/helm`.
