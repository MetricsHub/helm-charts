'use strict';
(async () => {
  const expected = process.env.EXPECTED_SLACK_TEAM_ID;
  if (!/^T[A-Z0-9]+$/.test(expected || '')) throw new Error('Expected Slack workspace ID is missing or invalid');
  if (!process.env.SLACK_BOT_TOKEN) throw new Error('SLACK_BOT_TOKEN is missing');
  const r = await fetch('https://slack.com/api/auth.test', {
    method: 'POST', headers: {Authorization: 'Bearer ' + process.env.SLACK_BOT_TOKEN},
    signal: AbortSignal.timeout(20000)
  });
  const b = await r.json();
  if (!r.ok || !b.ok) throw new Error('Slack auth.test failed: ' + (b.error || r.status));
  if (b.team_id !== expected) throw new Error('Workspace mismatch: received ' + b.team_id + ', expected ' + expected);
  console.log('Workspace verified:', b.team, b.team_id);
})().catch(e => { console.error(e.message); process.exit(1); });
