const CONFIG = {
  VLESS_UUID: '1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1',
  TROJAN_PASSWORD: '1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1',
  VLESS_SERVICE_NAME: 'vless-service',
  TROJAN_SERVICE_NAME: 'trojan-service',
  BACKEND_URL: 'https://YOUR-DOMAIN.COM',
  RATE_LIMIT: {
    MAX_REQUESTS: 100,
    WINDOW_MS: 60 * 1000, // 1 minute
  },
};

const uuidRegex = /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}|00000000-0000-0000-0000-000000000000)$/i;

// In-memory rate limiting store
const rateLimitStore = new Map();

function validateUUID(uuid) {
  return typeof uuid === 'string' && uuidRegex.test(uuid);
}

function applySecurityHeaders(response) {
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('X-Frame-Options', 'DENY');
  response.headers.set('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
  return response;
}

function checkRateLimit(clientIP) {
  const now = Date.now();
  const clientData = rateLimitStore.get(clientIP) || { count: 0, resetTime: now };
  
  if (now > clientData.resetTime) {
    clientData.count = 0;
    clientData.resetTime = now + CONFIG.RATE_LIMIT.WINDOW_MS;
  }
  
  clientData.count += 1;
  rateLimitStore.set(clientIP, clientData);
  
  return clientData.count <= CONFIG.RATE_LIMIT.MAX_REQUESTS;
}

async function handleHealthCheck() {
  return applySecurityHeaders(new Response('OK', { 
    status: 200,
    headers: { 'Content-Type': 'text/plain' }
  }));
}

async function validateRequest(request) {
  const url = new URL(request.url);
  const path = url.pathname;

  // Log request details for debugging
  console.log('Request:', {
    path: path,
    contentType: request.headers.get('content-type'),
    headers: [...request.headers],
    method: request.method,
    url: request.url
  });

  // Relaxed gRPC validation
  const contentType = request.headers.get('content-type') || '';
  const isGrpc = contentType.includes('application/grpc') || contentType.includes('application/octet-stream'); // Fallback for some clients
  if (!isGrpc) {
    console.warn('Non-gRPC content-type:', contentType);
  }

  // Verify service name
  const isVless = path.includes(CONFIG.VLESS_SERVICE_NAME);
  const isTrojan = path.includes(CONFIG.TROJAN_SERVICE_NAME);
  if (!isVless && !isTrojan) {
    throw new Error(`Invalid gRPC service name: ${path}`);
  }

  // Log Trojan auth header
  if (isTrojan) {
    const authHeader = request.headers.get('authorization') || 'none';
    console.log('Trojan auth header:', authHeader);
  }

  return { url, path, isTrojan };
}

async function forwardToBackend(request, path) {
  const backendUrl = `${CONFIG.BACKEND_URL}${path}`;
  console.log('Forwarding to:', backendUrl);
  try {
    const response = await fetch(backendUrl, {
      method: request.method,
      headers: {
        ...request.headers,
        'X-Forwarded-For': request.headers.get('CF-Connecting-IP') || '',
      },
      body: request.body,
      signal: AbortSignal.timeout(10000) // 10s timeout
    });
    return response;
  } catch (error) {
    console.error('Backend fetch error:', error.message);
    throw error;
  }
}

async function handleRequest(request) {
  try {
    // Rate limiting
    const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
    if (!checkRateLimit(clientIP)) {
      return applySecurityHeaders(new Response('Rate limit exceeded', { 
        status: 429,
        headers: { 'Retry-After': `${CONFIG.RATE_LIMIT.WINDOW_MS / 1000}` }
      }));
    }

    // Health check
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return await handleHealthCheck();
    }

    // Validate request
    const { path } = await validateRequest(request);

    // Forward request
    const response = await forwardToBackend(request, path);
    return applySecurityHeaders(response);

  } catch (error) {
    console.error('Request handling error:', {
      message: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });
    return applySecurityHeaders(new Response(`Error: ${error.message}`, { 
      status: 500,
      headers: { 'Content-Type': 'text/plain' }
    }));
  }
}

export default {
  async fetch(request, env, ctx) {
    // Validate configuration
    if (!validateUUID(CONFIG.VLESS_UUID)) {
      return applySecurityHeaders(new Response('Invalid VLESS_UUID configuration', { 
        status: 500,
        headers: { 'Content-Type': 'text/plain' }
      }));
    }
    if (!validateUUID(CONFIG.TROJAN_PASSWORD)) {
      return applySecurityHeaders(new Response('Invalid TROJAN_PASSWORD configuration', { 
        status: 500,
        headers: { 'Content-Type': 'text/plain' }
      }));
    }

    return handleRequest(request);
  },
};
