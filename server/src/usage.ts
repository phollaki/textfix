import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";

export const currentMonth = (now = new Date()): string => now.toISOString().slice(0, 7);

export const monthsAgo = (months: number, now = new Date()): string =>
  currentMonth(new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - months, 1)));

export class UsageStore {
  private db: DatabaseSync;

  constructor(path: string) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS usage (
        subject TEXT NOT NULL,
        month TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (subject, month)
      );
      CREATE TABLE IF NOT EXISTS spend (
        month TEXT PRIMARY KEY,
        usd REAL NOT NULL DEFAULT 0
      );
    `);
  }

  used(subject: string, month: string): number {
    const row = this.db
      .prepare("SELECT count FROM usage WHERE subject = ? AND month = ?")
      .get(subject, month) as { count: number } | undefined;
    return row?.count ?? 0;
  }

  spent(month: string): number {
    const row = this.db.prepare("SELECT usd FROM spend WHERE month = ?").get(month) as
      | { usd: number }
      | undefined;
    return row?.usd ?? 0;
  }

  deleteBefore(month: string): void {
    this.db.prepare("DELETE FROM usage WHERE month < ?").run(month);
  }

  record(subject: string, month: string, usd: number): number {
    this.db
      .prepare(
        "INSERT INTO usage (subject, month, count) VALUES (?, ?, 1) ON CONFLICT (subject, month) DO UPDATE SET count = count + 1",
      )
      .run(subject, month);
    this.db
      .prepare(
        "INSERT INTO spend (month, usd) VALUES (?, ?) ON CONFLICT (month) DO UPDATE SET usd = usd + excluded.usd",
      )
      .run(month, usd);
    return this.used(subject, month);
  }
}

export class RateLimiter {
  private hits = new Map<string, number[]>();
  private perMinute: number;
  private now: () => number;

  constructor(perMinute: number, now = () => Date.now()) {
    this.perMinute = perMinute;
    this.now = now;
  }

  allow(key: string): boolean {
    const since = this.now() - 60_000;
    const recent = (this.hits.get(key) ?? []).filter((time) => time > since);
    if (recent.length >= this.perMinute) {
      this.hits.set(key, recent);
      return false;
    }
    recent.push(this.now());
    this.hits.set(key, recent);
    return true;
  }
}
