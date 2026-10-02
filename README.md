# MetricsHub Helm Charts

Helm charts for deploying [MetricsHub](https://metricshub.com) on Kubernetes.

## Usage

```bash
helm repo add metricshub https://metricshub.github.io/helm-charts
helm repo update
helm search repo metricshub
```

Charts are also published as OCI artifacts, no `helm repo add` needed:

```bash
helm show values oci://ghcr.io/metricshub/charts/m8b-stack
```

## Charts

| Chart                         | Description                                                                                    |
| ----------------------------- | ---------------------------------------------------------------------------------------------- |
| [m8b-stack](charts/m8b-stack) | MetricsHub Enterprise, Prometheus, SearXNG and the M8B Slack bot, installed in explicit stages |

New to Helm? Start with the [m8b-stack getting-started guide](charts/m8b-stack/GETTING-STARTED.md).
Each chart's README documents prerequisites, required Secrets and values.
Charts never embed credentials: they reference Kubernetes Secrets you create.

## Development

```
charts/<name>/        one directory per chart (Chart.yaml, values.yaml, values.schema.json, templates/, examples/)
tests/<name>/         unit tests for scripts shipped inside a chart
scripts/test.sh       offline checks run by CI: helm lint, render matrix, rejected values, unit tests
```

```bash
./scripts/test.sh   # requires helm and node
```

Bump `version` in `Chart.yaml` for every chart change; CI enforces it on pull requests.
Releases are manual: in GitHub, **Actions > Release > Run workflow** on `main`. The workflow runs the tests, then
publishes every chart whose version has no release yet to GitHub Releases, the `gh-pages` index and GHCR.
Pushing to `main` alone never publishes anything.

## License

The charts in this repository are released under the [MIT License](LICENSE). The container images they deploy
(MetricsHub Enterprise, M8B) are distributed under their own terms and require registry credentials.
