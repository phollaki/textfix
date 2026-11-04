import { readFileSync } from "node:fs";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";
import type { Config } from "./config.ts";

export type Subscription = { originalTransactionId: string };

export type SubscriptionVerifier = (jws: string) => Promise<Subscription | null>;

export const appleVerifier = (config: Config): SubscriptionVerifier => {
  const roots = [readFileSync(new URL("../certs/AppleRootCA-G3.cer", import.meta.url))];
  const sandbox = new SignedDataVerifier(roots, true, Environment.SANDBOX, config.APPLE_BUNDLE_ID);
  const verifiers =
    config.APPLE_ENVIRONMENT === "Xcode"
      ? [new SignedDataVerifier(roots, false, Environment.XCODE, config.APPLE_BUNDLE_ID)]
      : config.APPLE_APP_ID
        ? [
            new SignedDataVerifier(
              roots,
              true,
              Environment.PRODUCTION,
              config.APPLE_BUNDLE_ID,
              config.APPLE_APP_ID,
            ),
            sandbox,
          ]
        : [sandbox];

  return async (jws) => {
    for (const verifier of verifiers) {
      try {
        const transaction = await verifier.verifyAndDecodeTransaction(jws);
        const active =
          !transaction.revocationDate && (transaction.expiresDate ?? 0) > Date.now();
        if (!active || !transaction.originalTransactionId) return null;
        return { originalTransactionId: transaction.originalTransactionId };
      } catch (error) {
        const wrongEnvironment =
          error instanceof VerificationException &&
          error.status === VerificationStatus.INVALID_ENVIRONMENT;
        if (!wrongEnvironment) return null;
      }
    }
    return null;
  };
};
