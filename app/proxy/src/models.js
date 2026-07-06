// Model providers (task C1, server half). Each provider is an async generator
// of ink-text deltas; the exchange route translates them to SSE chunks. Which
// provider a Book uses comes from its definition (books.js) — swappable
// without an app release. No API keys in the environment → echo mode.
//
// The Book prompt is injected HERE, server-side; the client never sees
// prompts or keys.

export function createTextProviderFactory(env = process.env) {
  return function textProviderFor(book) {
    const model = book.models.text;
    if (model.startsWith('gemini') && env.GEMINI_API_KEY) {
      return geminiProvider(model, env.GEMINI_API_KEY);
    }
    if (model.startsWith('gpt') && env.OPENAI_API_KEY) {
      return openAIProvider(model, env.OPENAI_API_KEY);
    }
    return null; // echo mode
  };
}

/** Builds the server-side instruction block: Book prompt + Plus memory. */
export function composeSystemPrompt(book, context = {}) {
  const parts = [book.prompt];
  if (context.memorySummaries?.length) {
    parts.push(`The notebook remembers:\n- ${context.memorySummaries.join('\n- ')}`);
  }
  if (context.sessionSummary) {
    parts.push(`Session so far: ${context.sessionSummary}`);
  }
  return parts.join('\n\n');
}

function geminiProvider(model, apiKey) {
  return async function* stream({ system, imageBase64 }) {
    const body = {
      systemInstruction: { parts: [{ text: system }] },
      contents: [
        {
          role: 'user',
          parts: [
            ...(imageBase64 ? [{ inlineData: { mimeType: 'image/jpeg', data: imageBase64 } }] : []),
            { text: 'Read the handwriting on this page and answer as the Book instructs.' },
          ],
        },
      ],
    };
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify(body),
      },
    );
    if (!res.ok) throw new Error(`gemini ${res.status}`);
    for await (const data of sseDataLines(res.body)) {
      const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('');
      if (text) yield text;
    }
  };
}

function openAIProvider(model, apiKey) {
  return async function* stream({ system, imageBase64 }) {
    const content = [
      ...(imageBase64
        ? [{ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } }]
        : []),
      { type: 'text', text: 'Read the handwriting on this page and answer as the Book instructs.' },
    ];
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model,
        stream: true,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content },
        ],
      }),
    });
    if (!res.ok) throw new Error(`openai ${res.status}`);
    for await (const data of sseDataLines(res.body)) {
      const text = data?.choices?.[0]?.delta?.content;
      if (text) yield text;
    }
  };
}

/** Parses `data: {...}` lines out of a streamed SSE body; skips [DONE]. */
async function* sseDataLines(body) {
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true });
    let newline;
    while ((newline = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line.startsWith('data:')) continue;
      const payload = line.slice(5).trim();
      if (payload === '[DONE]') return;
      try {
        yield JSON.parse(payload);
      } catch {
        // Partial/garbled data line — skip; the stream continues.
      }
    }
  }
}
