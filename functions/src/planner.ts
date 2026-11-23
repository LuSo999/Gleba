/**
 * Decides which notifications are due for one user right now.
 * Pure function – the scheduled Cloud Function feeds it data and sends the result.
 *
 * Mirrors the app's rules: default → category → product (most specific wins),
 * a date-type-specific rule beats a rule for both types.
 */
import { addDays, daysBetween, localDate, localMinutes, zonedTime } from './time.js';

export type DateType = 'useBy' | 'bestBefore';

export interface Item {
  id: string;
  householdId: string;
  name: string;
  categoryId: string;
  ean?: string | null;
  /** Local date "YYYY-MM-DD". */
  expiry: string;
  dateType: DateType;
}

export interface Rule {
  scope: 'defaults' | 'category' | 'product';
  targetId?: string | null;
  dateType?: DateType | null;
  enabled: boolean;
  daysBefore: number;
  hour: number;
  minute: number;
}

export interface Prefs {
  itemNotifications: boolean;
  morningDigest: boolean;
  digestHour: number;
  digestMinute: number;
  /** Remind about expired items every day until they are dealt with. */
  repeatExpired: boolean;
  /** Summary of what other household members did (sent by index.ts). */
  othersActivity: boolean;
  quietEnabled: boolean;
  /** Minutes since midnight. */
  quietFrom: number;
  quietTo: number;
}

export const defaultPrefs: Prefs = {
  itemNotifications: true, morningDigest: false, digestHour: 7, digestMinute: 30,
  repeatExpired: true, othersActivity: false, quietEnabled: false, quietFrom: 22 * 60, quietTo: 7 * 60,
};

export const builtInRule: Rule = { scope: 'defaults', enabled: true, daysBefore: 2, hour: 9, minute: 0 };

export type Kind = 'soon' | 'expired' | 'snooze' | 'digest';

export interface Due {
  /** Idempotency key – each key is sent at most once. */
  key: string;
  kind: Kind;
  items: Item[];
  /** Days left (negative = expired) for single-item notifications. */
  daysLeft?: number;
}

export function resolveRule(item: Item, rules: Rule[]): Rule {
  const pick = (scope: Rule['scope'], target: (r: Rule) => boolean) => {
    const m = rules.filter((r) => r.scope === scope && target(r) && (r.dateType == null || r.dateType === item.dateType));
    return m.find((r) => r.dateType != null) ?? m[0];
  };
  return (
    pick('product', (r) => r.targetId === item.id || (item.ean != null && r.targetId === item.ean)) ??
    pick('category', (r) => r.targetId === item.categoryId) ??
    pick('defaults', () => true) ??
    builtInRule
  );
}

/** Is a local time inside the quiet window (which may wrap past midnight)? */
export function inQuiet(minutes: number, p: Prefs): boolean {
  if (!p.quietEnabled || p.quietFrom === p.quietTo) return false;
  return p.quietFrom < p.quietTo
    ? minutes >= p.quietFrom && minutes < p.quietTo
    : minutes >= p.quietFrom || minutes < p.quietTo;
}

export interface PlanInput {
  now: Date;
  tz: string;
  items: Item[];
  rules: Rule[];
  prefs: Prefs;
  /** itemId → snoozed until. */
  snoozes: Record<string, Date>;
  alreadySent: Set<string>;
}

export function plan({ now, tz, items, rules, prefs, snoozes, alreadySent }: PlanInput): Due[] {
  const nowMin = localMinutes(now, tz);
  if (inQuiet(nowMin, prefs)) return []; // everything waits until the quiet window ends
  const today = localDate(now, tz);
  const passed = (day: string, minutes: number) => zonedTime(day, minutes, tz).getTime() <= now.getTime();
  const due: Due[] = [];
  const add = (d: Due) => {
    if (!alreadySent.has(d.key)) due.push(d);
  };

  if (prefs.itemNotifications) {
    for (const item of items) {
      const rule = resolveRule(item, rules);
      if (!rule.enabled) continue;
      const at = rule.hour * 60 + rule.minute;
      const left = daysBetween(today, item.expiry);

      const snoozed = snoozes[item.id];
      if (snoozed) {
        if (snoozed.getTime() > now.getTime()) continue;
        add({ key: `snooze:${item.id}:${snoozed.getTime()}`, kind: 'snooze', items: [item], daysLeft: left });
        continue;
      }

      if (left >= 0) {
        // Once per item and expiry date. An item added late (already inside the
        // window) is announced on the next run rather than never.
        const first = addDays(item.expiry, -rule.daysBefore);
        if (first <= today && passed(first < today ? today : first, first < today ? 0 : at)) {
          add({ key: `soon:${item.id}:${item.expiry}`, kind: 'soon', items: [item], daysLeft: left });
        }
      } else if (passed(today, at)) {
        const key = prefs.repeatExpired ? `expired:${item.id}:${today}` : `expired:${item.id}:${item.expiry}`;
        add({ key, kind: 'expired', items: [item], daysLeft: left });
      }
    }
  }

  if (prefs.morningDigest && passed(today, prefs.digestHour * 60 + prefs.digestMinute)) {
    const list = items.filter((i) => {
      const r = resolveRule(i, rules);
      const left = daysBetween(today, i.expiry);
      return r.enabled && left <= r.daysBefore && (left >= 0 || prefs.repeatExpired || left === -1);
    });
    if (list.length) {
      list.sort((a, b) => a.expiry.localeCompare(b.expiry));
      add({ key: `digest:${today}`, kind: 'digest', items: list });
    }
  }
  return due;
}
