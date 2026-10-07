export const audioTypes: Record<string, string> = {
  'audio/webm': 'webm', 'audio/mp4': 'mp4', 'audio/ogg': 'ogg', 'audio/wav': 'wav', 'audio/mpeg': 'mp3',
};
export function validateAudio(raw: any) {
  if (!raw || Object.keys(raw).sort().join(',') !== 'account_id,audio_base64,mime_type,request_id'
    || !Number.isSafeInteger(raw.account_id) || raw.account_id < 1
    || typeof raw.request_id !== 'string' || !/^[a-f0-9-]{36}$/i.test(raw.request_id)
    || !Object.hasOwn(audioTypes, raw.mime_type) || typeof raw.audio_base64 !== 'string'
    || raw.audio_base64.length > 5592408 || !/^[A-Za-z0-9+/]+={0,2}$/.test(raw.audio_base64)) throw new Error('Invalid audio');
  const bytes = Buffer.from(raw.audio_base64, 'base64');
  if (bytes.length < 16 || bytes.length > 4194304 || bytes.toString('base64') !== raw.audio_base64) throw new Error('Invalid audio');
  return { ...raw, bytes };
}

export async function transcribeAudio(raw: any, config: { mode: string; apiKey?: string; baseUrl?: string; transcriptionModel?: string }, signal?: AbortSignal) {
  const input = validateAudio(raw);
  if (config.mode !== 'provider' || !config.apiKey) throw new Error('Transcription requires provider');
  const base = new URL(config.baseUrl || 'https://api.openai.com/v1/');
  if (base.protocol !== 'https:') throw new Error('Provider requires HTTPS');
  const model = config.transcriptionModel || process.env.NICO_TRANSCRIPTION_MODEL || 'gpt-4o-mini-transcribe';
  const form = new FormData();
  form.append('file', new Blob([new Uint8Array(input.bytes)], { type: input.mime_type }), `command.${audioTypes[input.mime_type]}`);
  form.append('model', model);
  form.append('language', 'pt');
  form.append('response_format', 'json');
  const response = await fetch(`${base.href.replace(/\/$/, '')}/audio/transcriptions`, {
    method: 'POST', body: form, redirect: 'error', headers: { Authorization: `Bearer ${config.apiKey}` },
    signal: AbortSignal.any([AbortSignal.timeout(45000), ...(signal ? [signal] : [])]),
  });
  if (!response.ok || !response.body) throw new Error('Transcription unavailable');
  const reader = response.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 32768) throw new Error('Transcription too large');
      parts.push(value);
    }
  } finally { await reader.cancel(); }
  const body = JSON.parse(Buffer.concat(parts).toString('utf8'));
  const usage = body.usage;
  if (typeof body.text !== 'string' || body.text.length > 4000 || !usage || usage.type !== 'tokens'
    || ![usage.input_tokens, usage.output_tokens, usage.total_tokens].every(n => Number.isSafeInteger(n) && n >= 0 && n <= 270000)
    || usage.input_tokens + usage.output_tokens !== usage.total_tokens) throw new Error('Invalid transcription response');
  return { text: body.text, model, mode: 'provider', usage: {
    input_tokens: usage.input_tokens, output_tokens: usage.output_tokens, total_tokens: usage.total_tokens,
  } };
}
