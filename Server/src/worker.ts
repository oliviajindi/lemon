/**
 * AI Menu — Gemini proxy.
 *
 * Two endpoints the iOS app calls:
 *   POST /api/identify   - { text?, imageBase64?, imageMimeType? } -> { dishes: [{name, shortDescription}, ...] }
 *   POST /api/illustrate - { name, description?, style?, aspectRatio?, artDirection? } -> raw image bytes
 *   GET  /api/health     - liveness probe
 *
 * Auth: every request must include header `x-aimenu-secret: <PROXY_SHARED_SECRET>`.
 * The Gemini API key never leaves the Worker — clients only ever see the proxy URL + shared secret.
 *
 * Required Worker secrets (set via `npx wrangler secret put`):
 *   GEMINI_API_KEY
 *   PROXY_SHARED_SECRET
 *
 * Optional Worker vars (set in wrangler.jsonc):
 *   GEMINI_TEXT_MODEL    default "gemini-2.5-flash"
 *   GEMINI_IMAGE_MODEL   default "gemini-2.5-flash-image"
 */

interface Env {
  GEMINI_API_KEY: string;
  PROXY_SHARED_SECRET: string;
  GEMINI_TEXT_MODEL?: string;
  GEMINI_IMAGE_MODEL?: string;
}

interface IdentifyBody {
  text?: string;
  imageBase64?: string;
  imageMimeType?: string;
}

interface IllustrateBody {
  name?: string;
  description?: string;
  style?: string;
  aspectRatio?: string;
  /** Optional user hint when redrawing (e.g. "warmer palette, overhead shot"). */
  artDirection?: string;
}

const DEFAULT_TEXT_MODEL = "gemini-2.5-flash";
const DEFAULT_IMAGE_MODEL = "gemini-2.5-flash-image";

const DEFAULT_STYLE =
  "loose hand-drawn ink line illustration on cream paper, single subject centered, " +
  "soft watercolor wash, minimal palette, food illustration in the style of a personal recipe journal, " +
  "playful, charming, no text, no labels, no border";

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, GET, OPTIONS",
  "access-control-allow-headers": "content-type, x-aimenu-secret",
} as const;

function json(data: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", ...CORS_HEADERS, ...extra },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === "/api/health" && request.method === "GET") {
      return json({ ok: true });
    }

    if (!env.GEMINI_API_KEY) {
      return json({ error: "server misconfigured: GEMINI_API_KEY missing" }, 500);
    }

    if (env.PROXY_SHARED_SECRET) {
      const provided = request.headers.get("x-aimenu-secret") ?? "";
      if (!constantTimeEqual(provided, env.PROXY_SHARED_SECRET)) {
        return json({ error: "unauthorized" }, 401);
      }
    }

    if (request.method !== "POST") {
      return json({ error: "method not allowed" }, 405);
    }

    try {
      switch (url.pathname) {
        case "/api/identify":   return await identify(request, env);
        case "/api/illustrate": return await illustrate(request, env);
        default:                return json({ error: "not found" }, 404);
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return json({ error: "internal", detail: msg }, 500);
    }
  },
};

// ----------------------------------------------------------------------------
// /api/identify
// ----------------------------------------------------------------------------

async function identify(request: Request, env: Env): Promise<Response> {
  const body = (await safeJson(request)) as IdentifyBody;
  const text = (body.text ?? "").trim();
  const hasImage = typeof body.imageBase64 === "string" && body.imageBase64.length > 0;

  if (!text && !hasImage) {
    return json({ error: "provide text or imageBase64" }, 400);
  }

  const promptLines: string[] = [
    "You are helping someone keep a personal menu of dishes they cook or eat.",
    "Identify every distinct dish in the input and return concise JSON matching the schema.",
  ];
  if (hasImage) {
    promptLines.push(
      "A photo is provided. List every separately-served dish you can see (a bowl of soup, a plate of entrée, a side salad, a drink, a dessert, etc.).",
      "Do not list ingredients — only assembled, served dishes.",
      "If only one dish is visible, return an array with a single element.",
    );
  }
  if (text) {
    promptLines.push(
      `The user also wrote: "${text}". Use it as a hint; if it conflicts with the photo, prefer the photo but mention the hint in shortDescription.`,
    );
  }
  promptLines.push(
    "For each dish:",
    "- name: short, human-friendly Title Case, max 4 words.",
    "- shortDescription: 1 sentence, max 12 words, no trailing period.",
  );

  const parts: unknown[] = [{ text: promptLines.join("\n") }];
  if (hasImage) {
    parts.push({
      inline_data: {
        mime_type: body.imageMimeType ?? "image/jpeg",
        data: body.imageBase64,
      },
    });
  }

  const model = env.GEMINI_TEXT_MODEL || DEFAULT_TEXT_MODEL;
  const upstream = await callGemini(env, model, "generateContent", {
    contents: [{ role: "user", parts }],
    generationConfig: {
      temperature: 0.3,
      response_mime_type: "application/json",
      response_schema: {
        type: "object",
        properties: {
          dishes: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name:             { type: "string" },
                shortDescription: { type: "string" },
              },
              required: ["name", "shortDescription"],
            },
          },
        },
        required: ["dishes"],
      },
    },
  });

  if (!upstream.ok) return upstream;

  const data = (await upstream.json()) as GeminiTextResponse;
  const inner = data?.candidates?.[0]?.content?.parts?.find((p) => "text" in p && p.text)?.text ?? "";
  let parsed: { dishes?: Array<{ name?: string; shortDescription?: string }> } = {};
  try {
    parsed = JSON.parse(inner);
  } catch {
    /* fall through, we'll use the fallback */
  }

  const cleaned = (parsed.dishes ?? [])
    .map((d) => ({
      name: (d?.name ?? "").trim(),
      shortDescription: (d?.shortDescription ?? "").trim(),
    }))
    .filter((d) => d.name.length > 0);

  if (cleaned.length > 0) {
    return json({ dishes: cleaned });
  }
  if (text) {
    return json({ dishes: [{ name: text, shortDescription: "" }] });
  }
  return json({ error: "Gemini returned no dishes" }, 502);
}

// ----------------------------------------------------------------------------
// /api/illustrate
// ----------------------------------------------------------------------------

async function illustrate(request: Request, env: Env): Promise<Response> {
  const body = (await safeJson(request)) as IllustrateBody;
  const name = (body.name ?? "").trim();
  if (!name) return json({ error: "name required" }, 400);

  const description = (body.description ?? "").trim();
  const artDirection = (body.artDirection ?? "").trim();
  const style = (body.style && body.style.trim().length > 0 ? body.style : DEFAULT_STYLE).trim();
  const aspectRatio = body.aspectRatio || "1:1";

  let subject = description ? `${name} — ${description}` : name;
  if (artDirection) {
    subject += `. User-requested changes for the illustration: ${artDirection}`;
  }
  const prompt = `${style}. Subject: ${subject}.`;

  const model = env.GEMINI_IMAGE_MODEL || DEFAULT_IMAGE_MODEL;
  const upstream = await callGemini(env, model, "generateContent", {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      responseModalities: ["IMAGE"],
      imageConfig: { aspectRatio },
    },
  });

  if (!upstream.ok) return upstream;

  const data = (await upstream.json()) as GeminiImageResponse;
  const parts = data?.candidates?.[0]?.content?.parts ?? [];
  const inline = parts
    .map((p) => p.inlineData ?? p.inline_data)
    .find((d): d is InlineData => !!d?.data);
  if (!inline?.data) {
    return json({ error: "Gemini returned no image" }, 502);
  }

  const bytes = base64ToBytes(inline.data);
  const headers = new Headers(CORS_HEADERS);
  headers.set("content-type", inline.mimeType ?? "image/png");
  return new Response(new Uint8Array(bytes), { status: 200, headers });
}

// ----------------------------------------------------------------------------
// Upstream + helpers
// ----------------------------------------------------------------------------

interface InlineData {
  mimeType?: string;
  data?: string;
}
interface GeminiPart {
  text?: string;
  inlineData?: InlineData;
  inline_data?: InlineData;
}
interface GeminiCandidate {
  content?: { parts?: GeminiPart[] };
}
interface GeminiTextResponse  { candidates?: GeminiCandidate[] }
interface GeminiImageResponse { candidates?: GeminiCandidate[] }

async function callGemini(
  env: Env,
  model: string,
  action: "generateContent",
  payload: unknown,
): Promise<Response> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
    model,
  )}:${action}?key=${encodeURIComponent(env.GEMINI_API_KEY)}`;

  const resp = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (resp.ok) return resp;

  const detail = await resp.text();
  return json({ error: "gemini", status: resp.status, detail }, 502);
}

async function safeJson(req: Request): Promise<Record<string, unknown>> {
  try {
    return (await req.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Constant-time string comparison so timing leaks can't reveal the secret. */
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
