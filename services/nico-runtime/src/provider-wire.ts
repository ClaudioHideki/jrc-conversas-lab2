import { NicoError } from './errors.ts';

export type ProviderType = 'openai' | 'custom' | 'anthropic' | 'google_gemini';

// One internal structured contract; credentials use each provider's native protocol.
export function providerRequest(url: string, apiKey: string, body: Record<string, any>, type: ProviderType = 'openai', workspaceId?: string): { url: string; headers: Record<string, string>; body: Record<string, any> } {
  const base = url.replace(/\/chat\/completions$/, '');
  const system = body.messages.filter((m: any) => m.role === 'system').map((m: any) => m.content).join('\n\n');
  const messages = body.messages.filter((m: any) => m.role !== 'system');
  const schema = body.response_format?.json_schema?.schema;
  if (type === 'anthropic') return {
    url: `${base}/messages`, headers: { Authorization: `Bearer ${apiKey}`, 'anthropic-version': '2026-10-21', ...(workspaceId ? { 'anthropic-workspace-id': workspaceId } : {}) },
    body: { model: body.model, max_tokens: body.max_completion_tokens, system, messages,
      output_config: { format: { type: 'json_schema', schema } } },
  };
  if (type === 'google_gemini') return {
    url: `${base}/models/${encodeURIComponent(body.model)}:generateContent`, headers: { 'x-goog-api-key': apiKey },
    body: { systemInstruction: { parts: [{ text: system }] },
      contents: messages.map((m: any) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })),
      generationConfig: { maxOutputTokens: body.max_completion_tokens, responseMimeType: 'application/json', responseJsonSchema: schema } },
  };
  return { url, headers: { Authorization: `Bearer ${apiKey}` }, body };
}

export function providerReceipt(body: any, type: ProviderType = 'openai') {
  let input: number, output: number, total: number, content: unknown;
  if (type === 'anthropic') {
    const u = body?.usage;
    if (!u || ![u.input_tokens, u.output_tokens, u.cache_creation_input_tokens ?? 0, u.cache_read_input_tokens ?? 0]
      .every(n => Number.isSafeInteger(n) && n >= 0)) throw new NicoError('provider_usage_invalid');
    input = u.input_tokens + (u.cache_creation_input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0);
    output = u.output_tokens;
    total = input + output;
    content = body.content?.filter((block: any) => block.type === 'text').map((block: any) => block.text).join('');
  } else if (type === 'google_gemini') {
    const u = body?.usageMetadata;
    if (!u || ![u.promptTokenCount, u.candidatesTokenCount ?? 0, u.thoughtsTokenCount ?? 0,
      u.toolUsePromptTokenCount ?? 0, u.totalTokenCount].every(n => Number.isSafeInteger(n) && n >= 0)) throw new NicoError('provider_usage_invalid');
    input = u.promptTokenCount + (u.toolUsePromptTokenCount ?? 0);
    output = (u.candidatesTokenCount ?? 0) + (u.thoughtsTokenCount ?? 0);
    total = u.totalTokenCount;
    content = body.candidates?.[0]?.content?.parts?.filter((part: any) => !part.thought).map((part: any) => part.text || '').join('');
  } else {
    input = body?.usage?.prompt_tokens;
    output = body?.usage?.completion_tokens;
    total = body?.usage?.total_tokens;
    content = body?.choices?.[0]?.message?.content;
  }
  if (![input, output, total].every(n => Number.isSafeInteger(n) && n >= 0 && n <= 270000)
    || input + output !== total) throw new NicoError('provider_usage_invalid');
  return { input, output, total, content };
}
