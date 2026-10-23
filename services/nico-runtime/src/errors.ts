export type ErrorCode = 'provider_outer_json_invalid' | 'tool_arguments_invalid' | 'provider_schema_invalid'
  | 'provider_timeout' | 'provider_unauthorized' | 'provider_forbidden' | 'provider_rate_limited'
  | 'provider_unavailable' | 'provider_transport_error' | 'provider_usage_invalid'
  | 'runtime_busy' | 'request_cancelled' | 'runtime_internal_error' | 'invalid_configuration'
  | 'account_ai_not_configured' | 'provider_quota_exceeded';

export type TerminalAccounting = {
  version: 1; complete: true; attempts: number; model: string;
  usage: { input_tokens: number; output_tokens: number; total_tokens: number }; usage_estimated?: true;
};

export class NicoError extends Error {
  readonly code: ErrorCode;
  readonly accounting?: TerminalAccounting;
  constructor(code: ErrorCode, accounting?: TerminalAccounting) {
    super(code === 'runtime_busy' ? 'Runtime busy' : code);
    this.name = 'NicoError';
    this.code = code;
    this.accounting = accounting;
  }
}

export function errorResponse(error: unknown, route: string, scope?: { account_id: number; request_id: string }) {
  const code = error instanceof NicoError ? error.code : 'runtime_internal_error';
  const status = code === 'runtime_busy' || code === 'provider_rate_limited' ? 429
    : code === 'provider_timeout' ? 504 : code === 'request_cancelled' ? 499 : 502;
  const safeRoute = ['/v1/operate', '/v1/analyze', '/v1/transcribe', '/v1/sentiment'].includes(route) ? route : 'unknown';
  const receipt = error instanceof NicoError ? error.accounting : undefined;
  const accounting = receipt && scope ? { version: receipt.version, complete: receipt.complete, attempts: receipt.attempts,
    model: receipt.model, mode: 'provider', account_id: scope.account_id, request_id: scope.request_id,
    usage: { input_tokens: receipt.usage.input_tokens, output_tokens: receipt.usage.output_tokens, total_tokens: receipt.usage.total_tokens },
    ...(receipt.usage_estimated ? { usage_estimated: true } : {}) } : undefined;
  // Never serialize exception messages, stack traces, request headers or provider bodies.
  return { status, body: { error: code, ...(accounting ? { accounting } : {}) }, log: { event: 'nico_request_failed', route: safeRoute, code } };
}
