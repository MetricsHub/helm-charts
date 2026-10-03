# Network portability

## Explicit provider; no CNI installation

```yaml
network:
  enabled: true
  provider: kubernetes  # Default; alternatively cilium.
  defaultDenyWholeNamespace: false
```

`kubernetes` renders only `networking.k8s.io/v1` NetworkPolicies. A networking implementation that
**actually enforces** this API is a prerequisite. Creating a policy successfully does not prove enforcement.
The chart never installs, replaces or reconfigures a CNI. The API cannot reliably detect enforcement on its own.
`cilium` opts into `cilium.io/v2` CiliumNetworkPolicies and therefore requires Cilium plus its CRD.
Check it exists (`kubectl get crd ciliumnetworkpolicies.cilium.io`). No Cilium CRD is needed for a standard-policy install.

`enabled: false` emits no policies, including no default deny and no admin CIDR allows. The platform owns
network isolation in this mode. Other policies already selecting the Pods still apply; this is neither a
promise of connectivity nor a firewall configuration. `adminCidrs` has no enforcement effect by itself.

## Policy scope and traffic

The default deny selects only this release's labelled Pods. `defaultDenyWholeNamespace: true` deliberately
selects every Pod in the dedicated namespace. Everything else is denied; the allow policies cover exactly:

| From                         | To                                                                         |
| ---------------------------- | -------------------------------------------------------------------------- |
| every component              | DNS (`network.dns`)                                                        |
| bot, Doctor and index Jobs   | agent 31888 (MCP), Prometheus 9090, SearXNG 8080                           |
| bot, Doctor and index Jobs   | public Internet on 443 (Slack); LLM and embedding endpoints (`m8b.ai`, `m8b.embeddings`); `network.m8bAdditionalEgress` |
| SearXNG                      | public Internet on 80/443 (search engines); `network.searxngAdditionalEgress` |
| agent (and its collector)    | Prometheus 9090; `metricshub.egress` (monitored hosts, collector exporters) |
| `exposure.adminCidrs`        | agent 31888 and Prometheus 9090, when the NodePorts are enabled            |
| `metricshub.otel.ingressCidrs` | agent collector 13133 (health) and 24375 (Prometheus exporter)           |

"Public Internet" excludes the private/reserved ranges and the configured Pod/Service CIDRs.
A same-namespace Pod selector is not broadened to every namespace. Cross-namespace model rules put the
namespace AND Pod selectors into one peer. Public egress excludes the configured private/reserved, Pod
and Service CIDRs; supply your actual cluster ranges when these are not covered by the private exclusions.

The scope of this release is IPv4 Linux Kubernetes. It does not claim universal support for every CNI,
Windows node, dual-stack cluster, distribution security policy or host-network topology. Kubernetes versions
must also be compatible with the chosen application images. No restrictive admission setting is disabled.

## External IPs and in-cluster model servers

`m8b.ai.egress` and `m8b.embeddings.egress` are CIDR/port rules for external endpoints. They are not DNS-name
rules. If an address changes, update the rules. For models running as ordinary Pods use namespace/Pod selectors:

```yaml
m8b:
  ai:
    podEgress:
      - namespace: ai
        matchLabels:
          app: chat
        ports:
          - port: '8000'
            protocol: TCP
```

The equivalent `embeddings.podEgress` exists for a separate embedding backend. No permission on the destination
namespace is granted: its own ingress policy must also allow the connection. See `examples/in-cluster-ai.yaml`.

DNS defaults target `kube-system` Pods labelled `k8s-app: kube-dns`. Change `network.dns.namespace` and
`network.dns.labels` for other DNS layouts. `network.dns.ipBlocks` can add actual NodeLocal DNSCache addresses,
but host-network rules and enforcement depend on the CNI. Test DNS from the workload, not just from a node.

## Limits that are NOT silently translated

`metricshub.monitorKubernetesNodes.enabled: true` uses Cilium's host/remote-node entities; it is rejected when
standard policies are enabled. Do not assume that putting node IPs in `ipBlock` gives equivalent access.
An empty CIDR-rule `ports` list removes the L4 restriction; ICMP behavior is not guaranteed by the standard
API. Cilium-specific node or L7/FQDN features are not claimed as portable equivalents.

## NodePort / VPN administration

Exposure allows target Pod ports (31888 for MetricsHub, 9090 for Prometheus), not the external NodePort
number in the Pod policy. Restrict `exposure.adminCidrs` to trusted source networks as seen at enforcement,
which can be a VPN pool or a NAT gateway. `externalTrafficPolicy: Local` requires a node with a local ready
endpoint. Network routing, upstream firewalls and source translation still need validation.

Prometheus exposure adds neither TLS nor authentication and also reaches its enabled HTTP APIs, including
the OTLP receiver. Do not expose it to untrusted networks without an authentication/reverse-proxy strategy.

## Changing provider

Merely adding standard policies does not neutralize existing Cilium allows: policy permissions are additive.
Changing provider is a reviewed network migration, not a routine values toggle. Plan maintenance, protect
access independently, identify old policies by release ownership, apply and test the replacement policies,
and remove only obsolete owned objects. Helm offers no migration guard. Do not use
`network.enabled: false` as a workaround: it intentionally delegates/removes the chart's isolation.

After apply, check that no CiliumNetworkPolicy reports `Valid=False`. Standard policies
have no equivalent portable enforcement-success status. Perform allowed AND denied connectivity tests from
representative clients and Pods. API success is not a security acceptance test.

## Primary references

- https://kubernetes.io/docs/concepts/services-networking/network-policies/
- https://docs.cilium.io/en/stable/network/kubernetes/policy/
- https://kubernetes.io/docs/tutorials/services/source-ip/
- https://prometheus.io/docs/operating/security/
