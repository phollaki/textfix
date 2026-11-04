import { buildApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { openAIRewriter } from "./rewriter.ts";
import { appleVerifier } from "./subscription.ts";
import { UsageStore, monthsAgo } from "./usage.ts";

const config = loadConfig();
const store = new UsageStore(config.DATABASE_PATH);
const deleteOldUsage = () => store.deleteBefore(monthsAgo(12));
deleteOldUsage();
setInterval(deleteOldUsage, 24 * 60 * 60 * 1000).unref();

const app = buildApp({
  store,
  rewrite: openAIRewriter(config),
  verifySubscription: appleVerifier(config),
  monthlyBudgetUsd: config.MONTHLY_BUDGET_USD,
});

try {
  await app.listen({ host: config.HOST, port: config.PORT });
} catch (error) {
  app.log.error({ err: error }, "Failed to start server");
  process.exit(1);
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => void app.close().then(() => process.exit(0)));
}
