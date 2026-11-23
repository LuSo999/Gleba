import { test } from 'node:test';
import assert from 'node:assert/strict';

import { defaultPrefs, inQuiet, plan, resolveRule, type Item, type Rule } from './planner.js';
import { addDays, localDate, zonedTime } from './time.js';
import { activityText, texts } from './i18n.js';

const tz = 'Europe/Prague';
const at = (day: string, h: number, m = 0) => zonedTime(day, h * 60 + m, tz);
const item = (id: string, expiry: string, extra: Partial<Item> = {}): Item =>
  ({ id, householdId: 'h', name: id, categoryId: 'milk', expiry, dateType: 'useBy', ...extra });
const run = (now: Date, items: Item[], opts: Partial<Parameters<typeof plan>[0]> = {}) =>
  plan({ now, tz, items, rules: [], prefs: defaultPrefs, snoozes: {}, alreadySent: new Set(), ...opts });

test('time helpers handle Prague time incl. DST', () => {
  assert.equal(at('2026-11-23', 9).toISOString(), '2026-11-23T08:00:00.000Z'); // CET
  assert.equal(at('2026-07-01', 9).toISOString(), '2026-07-01T07:00:00.000Z'); // CEST
  assert.equal(localDate(new Date('2026-11-22T23:30:00Z'), tz), '2026-11-23');
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
});

test('two days before at 9:00, only once', () => {
  const milk = item('milk', '2026-11-25');
  assert.equal(run(at('2026-11-23', 8, 59), [milk]).length, 0);
  const due = run(at('2026-11-23', 9, 5), [milk]);
  assert.deepEqual(due.map((d) => d.key), ['soon:milk:2026-11-25']);
  assert.equal(run(at('2026-11-23', 9, 20), [milk], { alreadySent: new Set(['soon:milk:2026-11-25']) }).length, 0);
});

test('item added late is announced on the next run', () => {
  const due = run(at('2026-11-24', 20), [item('yog', '2026-11-25')]);
  assert.equal(due[0].kind, 'soon');
});

test('expired items repeat daily by default, once when disabled', () => {
  const ham = item('ham', '2026-11-20');
  assert.equal(run(at('2026-11-23', 9, 1), [ham])[0].key, 'expired:ham:2026-11-23');
  assert.equal(run(at('2026-11-23', 9, 1), [ham], { prefs: { ...defaultPrefs, repeatExpired: false } })[0].key,
    'expired:ham:2026-11-20');
});

test('quiet hours hold everything back', () => {
  const prefs = { ...defaultPrefs, quietEnabled: true, quietFrom: 22 * 60, quietTo: 7 * 60 };
  assert.equal(inQuiet(23 * 60, prefs), true);
  assert.equal(inQuiet(6 * 60 + 59, prefs), true);
  assert.equal(inQuiet(7 * 60, prefs), false);
  assert.equal(run(at('2026-11-24', 23), [item('a', '2026-11-25')], { prefs }).length, 0);
  assert.equal(run(at('2026-11-25', 7, 5), [item('a', '2026-11-25')], { prefs }).length, 1);
});

test('rules: product beats category beats default; disabled means silent', () => {
  const rules: Rule[] = [
    { scope: 'defaults', enabled: true, daysBefore: 2, hour: 9, minute: 0 },
    { scope: 'category', targetId: 'milk', enabled: true, daysBefore: 1, hour: 18, minute: 0 },
    { scope: 'product', targetId: '859', enabled: false, daysBefore: 2, hour: 9, minute: 0 },
  ];
  assert.equal(resolveRule(item('a', '2026-11-25'), rules).hour, 18);
  assert.equal(resolveRule(item('b', '2026-11-25', { categoryId: 'eggs' }), rules).daysBefore, 2);
  assert.equal(run(at('2026-11-24', 19), [item('c', '2026-11-25', { ean: '859' })], { rules }).length, 0);
});

test('snooze postpones, then fires once', () => {
  const a = item('a', '2026-11-25');
  const snoozes = { a: at('2026-11-24', 10) };
  assert.equal(run(at('2026-11-24', 9, 30), [a], { snoozes }).length, 0);
  assert.equal(run(at('2026-11-24', 10, 5), [a], { snoozes })[0].kind, 'snooze');
});

test('morning digest lists what is due, sorted by date', () => {
  const prefs = { ...defaultPrefs, morningDigest: true, itemNotifications: false };
  const due = run(at('2026-11-23', 7, 40), [item('later', '2026-12-20'), item('b', '2026-11-25'), item('a', '2026-11-24')], { prefs });
  assert.deepEqual(due.map((d) => d.key), ['digest:2026-11-23']);
  assert.deepEqual(due[0].items.map((i) => i.id), ['a', 'b']);
  assert.match(texts('cs', due[0]).body, /^2 věci brzy projde: a, b$/);
});

test('texts', () => {
  const t = texts('cs', { key: 'k', kind: 'soon', items: [item('Mléko', '2026-11-25')], daysLeft: 1 });
  assert.equal(t.title, '🥛 Mléko');
  assert.equal(t.body, 'Spotřebujte do: zítra');
  assert.equal(activityText('cs', [{ byName: 'Jana', type: 'added' }, { byName: 'Jana', type: 'added' }]).body,
    'Jana: přidáno 2');
});
