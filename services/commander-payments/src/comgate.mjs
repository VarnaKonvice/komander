const DEFAULT_BASE = 'https://payments.comgate.cz';

export function loadComgateConfig(env = process.env) {
  return {
    merchant: env.COMGATE_MERCHANT || '',
    secret: env.COMGATE_SECRET || '',
    test: String(env.COMGATE_TEST ?? 'true').toLowerCase() !== 'false',
    apiBase: (env.COMGATE_API_BASE || DEFAULT_BASE).replace(/\/$/, ''),
  };
}

export function hasComgateCredentials(config) {
  return Boolean(config?.merchant && config?.secret);
}

function basicAuth(config) {
  if (!hasComgateCredentials(config)) {
    throw new Error('Comgate credentials are not configured');
  }
  return `Basic ${Buffer.from(`${config.merchant}:${config.secret}`).toString('base64')}`;
}

async function readJson(response) {
  const text = await response.text();
  let body;
  try { body = text ? JSON.parse(text) : {}; }
  catch { body = { message: text || response.statusText }; }
  if (!response.ok || (body.code !== undefined && Number(body.code) !== 0)) {
    const error = new Error(body.message || `Comgate HTTP ${response.status}`);
    error.status = response.status;
    error.comgate = body;
    throw error;
  }
  return body;
}

export async function createComgatePayment(input, { config = loadComgateConfig(), fetchImpl = fetch } = {}) {
  const payload = {
    test: config.test,
    country: input.country || 'CZ',
    price: input.priceMinor,
    curr: input.currency,
    label: input.label,
    refId: input.refId,
    method: input.method || 'ALL',
    email: input.email,
    name: input.productCode,
  };

  const response = await fetchImpl(`${config.apiBase}/v2.0/payment.json`, {
    method: 'POST',
    headers: {
      Authorization: basicAuth(config),
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(payload),
  });
  return readJson(response);
}

export async function getComgatePaymentStatus(transId, { config = loadComgateConfig(), fetchImpl = fetch } = {}) {
  if (!transId) throw new Error('transId is required');
  const response = await fetchImpl(`${config.apiBase}/v2.0/payment/transId/${encodeURIComponent(transId)}.json`, {
    method: 'GET',
    headers: {
      Authorization: basicAuth(config),
      Accept: 'application/json',
    },
  });
  return readJson(response);
}
