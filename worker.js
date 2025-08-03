const VLESS_UUID = '1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1';
const VLESS_SERVICE_NAME = 'vless-service';
const TROJAN_SERVICE_NAME = 'trojan-service';
const BACKEND_URL = 'https://YOUR-DOMAIN';

const uuidRegex = /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}|00000000-0000-0000-0000-000000000000)$/i;

function validateUUID(uuid) {
  return typeof uuid === 'string' && uuidRegex.test(uuid);
}

async function handleRequest(request) {
  const url = new URL(request.url);
  const path = url.pathname;

  // Health check endpoint
  if (path === '/health') {
    return new Response('OK', { status: 200 });
  }

  // Validate gRPC request
  const isGrpc = request.headers.get('content-type')?.includes('application/grpc');
  if (!isGrpc) {
    return new Response('gRPC request required', { status: 400 });
  }

  // Verify service name for either VLESS or Trojan
  if (!path.includes(VLESS_SERVICE_NAME) && !path.includes(TROJAN_SERVICE_NAME)) {
    return new Response('Invalid gRPC service name', { status: 400 });
  }

  // Forward to backend
  try {
    const response = await fetch(`${BACKEND_URL}${path}`, {
      method: request.method,
      headers: request.headers,
      body: request.body,
    });
    return response;
  } catch (error) {
    console.error('gRPC error:', error);
    return new Response(`gRPC connection failed: ${error.message}`, { status: 500 });
  }
}

export default {
  async fetch(request, env, ctx) {
    // This UUID validation only applies to the constant, you might remove or adapt it.
    if (!validateUUID(VLESS_UUID)) {
      return new Response('Invalid VLESS_UUID constant in worker', { status: 400 });
    }
    return handleRequest(request);
  },
};
