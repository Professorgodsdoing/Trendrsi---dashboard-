// ============================================================
//  api/signal.js  — Vercel Serverless API Route
//  Receives signals from your MT5 TrendRSI EA
//  Deploy this in your GitHub repo as: api/signal.js
// ============================================================

// In-memory store (use Vercel KV / Redis / Supabase for production)
let latestSignal = {
  signal: 'HOLD',
  symbol: 'EURUSD',
  price: null,
  rsi: 50,
  ema_fast: null,
  ema_slow: null,
  sl: null,
  tp: null,
  strength: 0,
  reason: 'No signal yet',
  timestamp: new Date().toISOString()
};

const signalHistory = [];
const SECRET = process.env.WEBHOOK_SECRET || 'YOUR_SECRET_KEY';

export default async function handler(req, res) {
  // ── CORS headers (allow your dashboard domain) ──
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-EA-Secret');

  if (req.method === 'OPTIONS') return res.status(200).end();

  // ── GET: Return latest signal ──
  if (req.method === 'GET') {
    return res.status(200).json({
      latest: latestSignal,
      history: signalHistory.slice(-20)
    });
  }

  // ── POST: Receive signal from MT5 EA ──
  if (req.method === 'POST') {
    // Validate secret
    const incomingSecret = req.headers['x-ea-secret'] || req.body?.secret;
    if (incomingSecret !== SECRET) {
      return res.status(401).json({ error: 'Unauthorized — invalid secret' });
    }

    const body = req.body;

    // Validate required fields
    if (!body.signal || !body.symbol) {
      return res.status(400).json({ error: 'Missing required fields: signal, symbol' });
    }

    // Sanitize and store
    latestSignal = {
      signal:    body.signal,
      symbol:    body.symbol,
      timeframe: body.timeframe || 'M15',
      price:     parseFloat(body.price)    || null,
      rsi:       parseFloat(body.rsi)      || 50,
      ema_fast:  parseFloat(body.ema_fast) || null,
      ema_slow:  parseFloat(body.ema_slow) || null,
      sl:        parseFloat(body.sl)       || null,
      tp:        parseFloat(body.tp)       || null,
      lots:      parseFloat(body.lots)     || null,
      strength:  parseFloat(body.strength) || 0,
      reason:    String(body.reason || '').slice(0, 500),
      timestamp: new Date().toISOString(),
      ea_time:   body.timestamp || null
    };

    // Add to history (keep last 100)
    signalHistory.push({ ...latestSignal });
    if (signalHistory.length > 100) signalHistory.shift();

    console.log(`[TrendRSI EA] ${latestSignal.signal} on ${latestSignal.symbol} | RSI: ${latestSignal.rsi}`);

    return res.status(200).json({
      ok: true,
      received: latestSignal.signal,
      timestamp: latestSignal.timestamp
    });
  }

  return res.status(405).json({ error: 'Method not allowed' });
}
