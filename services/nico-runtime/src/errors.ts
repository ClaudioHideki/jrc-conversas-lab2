export type ErrorCode = 'provider_outer_json_invalid' | 'tool_arguments_invalid' | 'provider_schema_invalid'
  | 'provider_timeout' | 'provider_unauthorized' | 'provider_forbidden' | 'provider_rate_limited'
  | 'provider_unavailable' | 'provider_transport_error' | 'provider_usage_invalid'
  | 'runtime_busy' | 'request_cancelled' | 'runtime_internal_error' | 'invalid_configuration'
  | 'account_ai_not_configured' | 'provider_quota_exceeded';

export class NicoError extends Error {
  readonly code: ErrorCode;
  constructor(code: ErrorCode) {
    super(code === 'runtime_busy' ? 'Runtime busy' : code);
    this.name = 'NicoError';
    this.code = code;
  }
}

export function errorResponse(error: unknown, route: string) {
  const code = error instanceof NicoError ? error.code : 'runtime_internal_error';
  const status = code === 'runtime_busy' || code === 'provider_rate_limited' ? 429
    : code === 'provider_timeout' ? 504 : code === 'request_cancelled' ? 499 : 502;
  const safeRoute = ['/v1/operate', '/v1/analyze', '/v1/transcribe', '/v1/sentiment'].includes(route) ? route : 'unknown';
  // Never serialize exception messages, stack traces, request headers or provider bodies.
  return { status, body: { error: code }, log: { event: 'nico_request_failed', route: safeRoute, code } };
}
