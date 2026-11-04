import OpenAI from "openai";
import type { Config } from "./config.ts";
import { type Language, type Mode, systemPrompt } from "./prompts.ts";

export type Rewrite = { text: string; usd: number };

export type Rewriter = (mode: Mode, language: Language, text: string) => Promise<Rewrite>;

export const openAIRewriter = (config: Config): Rewriter => {
  const client = new OpenAI({ apiKey: config.OPENAI_API_KEY, timeout: 20_000, maxRetries: 2 });

  return async (mode, language, text) => {
    const response = await client.chat.completions.create({
      model: config.OPENAI_MODEL,
      reasoning_effort: config.OPENAI_REASONING_EFFORT as OpenAI.ReasoningEffort,
      messages: [
        { role: "system", content: systemPrompt(mode, language) },
        { role: "user", content: text },
      ],
    });
    const output = response.choices[0]?.message.content;
    if (!output) throw new Error("OpenAI returned no text");

    const inputTokens = response.usage?.prompt_tokens ?? 0;
    const outputTokens = response.usage?.completion_tokens ?? 0;
    const usd =
      (inputTokens * config.OPENAI_INPUT_USD_PER_MILLION +
        outputTokens * config.OPENAI_OUTPUT_USD_PER_MILLION) /
      1_000_000;
    return { text: output, usd };
  };
};
