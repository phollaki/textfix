import { z } from "zod";

const schema = z.object({
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().default(3000),
  DATABASE_PATH: z.string().default("data/textfix.db"),
  OPENAI_API_KEY: z.string().min(1),
  OPENAI_MODEL: z.string().default("gpt-6-luna"),
  OPENAI_REASONING_EFFORT: z.string().default("none"),
  OPENAI_INPUT_USD_PER_MILLION: z.coerce.number().default(0.1),
  OPENAI_OUTPUT_USD_PER_MILLION: z.coerce.number().default(0.5),
  MONTHLY_BUDGET_USD: z.coerce.number().default(50),
  APPLE_BUNDLE_ID: z.string().default("com.puteanihollakos.textfix"),
  APPLE_APP_ID: z.coerce.number().int().optional(),
  APPLE_ENVIRONMENT: z.enum(["Production", "Xcode"]).default("Production"),
});

export type Config = z.infer<typeof schema>;

export const loadConfig = (): Config => schema.parse(process.env);

export const limits = {
  freePerMonth: 30,
  proPerMonth: 2000,
  maxCharacters: 4000,
  requestsPerMinute: 10,
};
