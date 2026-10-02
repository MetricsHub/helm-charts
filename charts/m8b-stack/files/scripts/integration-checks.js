'use strict';
async function request(base, path) {
  const r = await fetch(base.replace(/\/$/, '') + path, {signal: AbortSignal.timeout(30000)});
  if (!r.ok) throw new Error('HTTP ' + r.status + ' on ' + path.split('?')[0]);
  return r;
}
(async () => {
  const p = process.env.M8B_PROMETHEUS_URL;
  if (p) {
    await request(p, '/-/ready');
    const flags = await (await request(p, '/api/v1/status/flags')).json();
    if (flags.status !== 'success' || flags.data['web.enable-otlp-receiver'] !== 'true') throw new Error('Prometheus OTLP receiver is not enabled');
    if (process.env.REQUIRE_METRICSHUB_METRICS === 'true') {
      const q = encodeURIComponent('count(metricshub_agent_info)');
      const body = await (await request(p, '/api/v1/query?query=' + q)).json();
      const samples = body.data?.result || [];
      if (body.status !== 'success' || !samples.some(x => Number(x.value?.[1]) > 0)) throw new Error('No current metricshub_agent_info sample; wait for collection/export');
    }
    console.log('Prometheus: ready; OTLP enabled; required metric check passed');
  }
  if (process.env.WEB_SEARCH_PROVIDER === 'searxng') {
    const base = process.env.SEARXNG_URL;
    if (!base) throw new Error('SEARXNG_URL missing');
    await request(base, '/healthz');
    const q = encodeURIComponent(process.env.SEARCH_CHECK_QUERY || 'MetricsHub documentation');
    const body = await (await request(base, '/search?q=' + q + '&format=json')).json();
    if (!Array.isArray(body.results) || body.results.length < 1) throw new Error('SearXNG returned no search results');
    console.log('SearXNG: JSON API, results=' + body.results.length);
  }
})().catch(e => { console.error(e.message); process.exit(1); });
