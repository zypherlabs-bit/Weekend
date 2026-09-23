// realtime_check.mjs - verifies Supabase Realtime end-to-end.
//
// Subscribes (as user B) to postgres_changes on public.messages for one
// conversation, then has user A POST a message through the REST API and waits
// for the INSERT to be delivered over the websocket.
//
// Usage:
//   node tool/realtime_check.mjs
// Env (all required):
//   SUPABASE_URL, SUPABASE_ANON_KEY, USER_B_TOKEN, CONVERSATION_ID, USER_A_TOKEN, SENDER_ID
const {
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  USER_B_TOKEN,
  CONVERSATION_ID,
  USER_A_TOKEN,
  SENDER_ID,
} = process.env;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !USER_B_TOKEN || !CONVERSATION_ID || !USER_A_TOKEN || !SENDER_ID) {
  console.error('missing env vars');
  process.exit(2);
}

const topic = 'realtime:public:messages';
const marker = `realtime-probe-${Date.now()}`;

const wsUrl =
  `${SUPABASE_URL.replace('https://', 'wss://')}/realtime/v1/websocket` +
  `?apikey=${SUPABASE_ANON_KEY}&vsn=1.0.0&access_token=${encodeURIComponent(USER_B_TOKEN)}`;

const ws = new WebSocket(wsUrl);

let sent = false;
const timeout = setTimeout(() => {
  console.error('TIMEOUT: no postgres_changes event received within 30s');
  try { ws.close(); } catch {}
  process.exit(1);
}, 30000);

ws.addEventListener('open', () => {
  console.log('[ws] connected');
  ws.send(JSON.stringify({
    topic,
    event: 'phx_join',
    payload: {
      config: {
        broadcast: { self: false },
        presence: { key: '' },
        postgres_changes: [
          { event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${CONVERSATION_ID}` },
        ],
      },
      access_token: USER_B_TOKEN,
    },
    ref: '1',
  }));
});

ws.addEventListener('message', async (event) => {
  let msg;
  try { msg = JSON.parse(typeof event.data === 'string' ? event.data : await event.data.text()); } catch { return; }

  if (msg.event === 'phx_reply' && msg.payload?.status === 'ok') {
    console.log('[ws] channel joined:', msg.topic);
    if (!sent) {
      sent = true;
      const res = await fetch(`${SUPABASE_URL}/rest/v1/messages`, {
        method: 'POST',
        headers: {
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${USER_A_TOKEN}`,
          'Content-Type': 'application/json',
          Prefer: 'return=minimal',
        },
        body: JSON.stringify({
          conversation_id: CONVERSATION_ID,
          sender_id: SENDER_ID,
          text: marker,
        }),
      });
      console.log('[rest] A sent message, status', res.status);
    }
    return;
  }

  if (msg.event === 'postgres_changes') {
    console.log('[ws] postgres_changes payload:', JSON.stringify(msg.payload).slice(0, 600));
    const record = msg.payload?.data?.record ?? msg.payload?.record;
    if (record?.text === marker) {
      console.log('[REALTIME OK] received INSERT for message id', record.id);
      clearTimeout(timeout);
      ws.close();
      process.exit(0);
    }
  }

  if (msg.event === 'phx_error' || msg.event === 'system') {
    console.log('[ws]', msg.event, JSON.stringify(msg.payload));
  }
});

ws.addEventListener('error', (e) => {
  console.error('[ws] error', e?.message ?? e);
});
