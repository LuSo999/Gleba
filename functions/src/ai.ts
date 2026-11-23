/**
 * AI provider calls for the household-shared API key mode. The key never
 * leaves the server: the app sends the prompt and images, we call the
 * provider and return the text.
 */
import Anthropic from '@anthropic-ai/sdk';

export type Provider = 'gemini' | 'openai' | 'anthropic';

export interface AiImage { mime: string; data: string /* base64 */ }

export interface AiRequest {
  prompt: string;
  images?: AiImage[];
  /** JSON schema for structured output; when set the reply is a JSON string. */
  schema?: Record<string, unknown> | null;
  maxTokens?: number;
}

export const defaultModels: Record<Provider, string> = {
  gemini: 'gemini-flash-latest',
  openai: 'gpt-5-mini',
  anthropic: 'claude-opus-5-5',
};

export class AiError extends Error {}

async function postJson(url: string, headers: Record<string, string>, body: unknown): Promise<any> {
  const res = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });
  const json: any = await res.json().catch(() => ({}));
  if (!res.ok) throw new AiError(json?.error?.message ?? `HTTP ${res.status}`);
  return json;
}

async function callAnthropic(key: string, model: string, r: AiRequest): Promise<string> {
  const client = new Anthropic({ apiKey: key });
  const content: Anthropic.Beta.Messages.BetaContentBlockParam[] = [
    ...(r.images ?? []).map((i) => ({
      type: 'image' as const,
      source: { type: 'base64' as const, media_type: i.mime as 'image/jpeg', data: i.data },
    })),
    { type: 'text' as const, text: r.prompt },
  ];
  const msg = await client.beta.messages.create({
    model,
    max_tokens: r.maxTokens ?? 16000,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    // Extraction and suggestions are simple tasks: low effort keeps them fast and cheap.
    output_config: {
      effort: 'low',
      ...(r.schema ? { format: { type: 'json_schema' as const, schema: r.schema } } : {}),
    },
    messages: [{ role: 'user', content }],
  });
  if (msg.stop_reason === 'refusal') throw new AiError('refusal');
  return msg.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
}

async function callGemini(key: string, model: string, r: AiRequest): Promise<string> {
  const parts = [
    ...(r.images ?? []).map((i) => ({ inline_data: { mime_type: i.mime, data: i.data } })),
    { text: r.prompt },
  ];
  const json = await postJson(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    { 'x-goog-api-key': key },
    {
      contents: [{ role: 'user', parts }],
      generationConfig: r.schema ? { responseMimeType: 'application/json' } : {},
    },
  );
  return (json.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? '').join('');
}

async function callOpenAi(key: string, model: string, r: AiRequest): Promise<string> {
  const content = [
    { type: 'text', text: r.prompt },
    ...(r.images ?? []).map((i) => ({ type: 'image_url', image_url: { url: `data:${i.mime};base64,${i.data}` } })),
  ];
  const json = await postJson('https://api.openai.com/v1/chat/completions', { authorization: `Bearer ${key}` }, {
    model,
    messages: [{ role: 'user', content }],
    ...(r.schema ? { response_format: { type: 'json_object' } } : {}),
  });
  return json.choices?.[0]?.message?.content ?? '';
}

export function callProvider(provider: Provider, key: string, model: string | undefined, r: AiRequest): Promise<string> {
  const m = model || defaultModels[provider];
  switch (provider) {
    case 'anthropic': return callAnthropic(key, m, r);
    case 'gemini': return callGemini(key, m, r);
    case 'openai': return callOpenAi(key, m, r);
  }
}
