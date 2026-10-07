import { NicoError } from './errors.ts';

export type ProviderConfig = { apiKey: string; model: string; baseUrl: string; transcriptionModel?: string };

// Service-authenticated envelope only; never forward it to model prompts or memory.
export function requestProvider(raw: unknown): ProviderConfig | undefined {
  if (raw === undefined) return undefined;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new NicoError('invalid_configuration');
  const value = raw as Record<string, unknown>;
  if (Object.keys(value).some(key => !['api_key', 'model', 'base_url', 'transcription_model'].includes(key))) throw new NicoError('invalid_configuration');
  if (typeof value.api_key !== 'string' || value.api_key.length < 1 || value.api_key.length > 8192
    || /[\r\n]/.test(value.api_key) || typeof value.model !== 'string' || value.model.length < 1 || value.model.length > 150
    || typeof value.base_url !== 'string') throw new NicoError('invalid_configuration');
  let url: URL;
  try { url = new URL(value.base_url); } catch { throw new NicoError('invalid_configuration'); }
  const hosts = (process.env.NICO_PROVIDER_ALLOWED_HOSTS || 'api.openai.com').split(',').map(host => host.trim().toLowerCase());
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash
    || (url.port && url.port !== '443') || !hosts.includes(url.hostname.toLowerCase())) throw new NicoError('invalid_configuration');
  if (value.transcription_model !== undefined && (typeof value.transcription_model !== 'string'
    || !value.transcription_model.length || value.transcription_model.length > 150)) throw new NicoError('invalid_configuration');
  return { apiKey: value.api_key, model: value.model, baseUrl: url.href,
    transcriptionModel: value.transcription_model as string | undefined };
}
