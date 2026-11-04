import Fastify from "fastify";
import { z } from "zod";
import { limits } from "./config.ts";
import { languages, modes } from "./prompts.ts";
import type { Rewriter } from "./rewriter.ts";
import type { SubscriptionVerifier } from "./subscription.ts";
import { RateLimiter, UsageStore, currentMonth } from "./usage.ts";

export type Dependencies = {
  store: UsageStore;
  rewrite: Rewriter;
  verifySubscription: SubscriptionVerifier;
  monthlyBudgetUsd: number;
  rateLimiter?: RateLimiter;
  now?: () => Date;
};

const headersSchema = z.object({
  "x-install-id": z.uuid(),
  "x-transaction": z.string().max(20_000).optional(),
});

const rewriteSchema = z.object({
  mode: z.enum(modes),
  text: z.string().trim().min(1, "No text selected"),
  targetLanguage: z.enum(languages).default("English"),
});

export const buildApp = (deps: Dependencies) => {
  const app = Fastify({ logger: { level: "info" }, bodyLimit: 64 * 1024, trustProxy: true });
  const rateLimiter = deps.rateLimiter ?? new RateLimiter(limits.requestsPerMinute);
  const now = deps.now ?? (() => new Date());

  const account = async (headers: unknown) => {
    const parsed = headersSchema.safeParse(headers);
    if (!parsed.success) return null;
    const jws = parsed.data["x-transaction"];
    const subscription = jws ? await deps.verifySubscription(jws) : null;
    return subscription
      ? {
          installId: parsed.data["x-install-id"],
          subject: `transaction:${subscription.originalTransactionId}`,
          plan: "pro" as const,
          limit: limits.proPerMonth,
        }
      : {
          installId: parsed.data["x-install-id"],
          subject: `install:${parsed.data["x-install-id"]}`,
          plan: "free" as const,
          limit: limits.freePerMonth,
        };
  };

  app.get("/api/health", async () => ({ ok: true }));

  app.get("/api/usage", async (request, reply) => {
    const user = await account(request.headers);
    if (!user) return reply.code(400).send({ error: "Missing install ID" });
    const used = deps.store.used(user.subject, currentMonth(now()));
    return { used, limit: user.limit, plan: user.plan };
  });

  app.post("/api/rewrite", async (request, reply) => {
    const user = await account(request.headers);
    if (!user) return reply.code(400).send({ error: "Missing install ID" });

    const body = rewriteSchema.safeParse(request.body);
    if (!body.success) {
      return reply.code(400).send({ error: body.error.issues[0]?.message ?? "Invalid request" });
    }
    const { mode, text, targetLanguage } = body.data;
    if (text.length > limits.maxCharacters) {
      return reply.code(413).send({
        error: `The text is too long. TextFix works with up to ${limits.maxCharacters.toLocaleString("en")} characters at a time.`,
      });
    }
    if (!rateLimiter.allow(user.installId)) {
      return reply.code(429).send({ error: "Too many requests. Please wait a minute." });
    }

    const month = currentMonth(now());
    const used = deps.store.used(user.subject, month);
    if (used >= user.limit) {
      const error =
        user.plan === "free"
          ? `You used all ${user.limit} free rewrites this month. Upgrade to Pro for ${limits.proPerMonth.toLocaleString("en")} rewrites a month.`
          : `You used all ${user.limit.toLocaleString("en")} rewrites this month. Your limit resets on the 1st.`;
      return reply.code(402).send({ error, used, limit: user.limit, plan: user.plan });
    }
    if (deps.store.spent(month) >= deps.monthlyBudgetUsd) {
      request.log.error({ month }, "Monthly OpenAI budget reached");
      return reply.code(503).send({ error: "TextFix is busy right now. Please try again later." });
    }

    try {
      const result = await deps.rewrite(mode, targetLanguage, text);
      const usedNow = deps.store.record(user.subject, month, result.usd);
      request.log.info({ mode, plan: user.plan, usd: result.usd }, "Rewrite done");
      return { text: result.text, used: usedNow, limit: user.limit, plan: user.plan };
    } catch (error) {
      request.log.error({ err: error, mode }, "Rewrite failed");
      return reply.code(502).send({ error: "Could not rewrite the text. Please try again." });
    }
  });

  return app;
};
