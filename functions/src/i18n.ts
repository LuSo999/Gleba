/** Notification texts (CZ / EN), kept in sync with the app's wording. */
import type { Due } from './planner.js';

type Lang = 'cs' | 'en';

const emoji: Record<string, string> = {
  frozen: '🧊', leftovers: '🍲', readyMeal: '🍱', yogurt: '🍶', cheeseSoft: '🧀', cheeseHard: '🧀', butter: '🧈',
  milkUht: '🥛', milk: '🥛', eggs: '🥚', deli: '🥓', poultry: '🍗', fish: '🐟', meat: '🥩', rootVeg: '🧅',
  vegetables: '🥬', fruit: '🍎', bread: '🍞', drinks: '🧃', sauces: '🫙', canned: '🥫', dry: '🌾', sweets: '🍫',
};

function csPlural(n: number, one: string, few: string, many: string) {
  return n === 1 ? one : n >= 2 && n <= 4 ? few : many;
}

function relative(lang: Lang, left: number): string {
  if (lang === 'cs') {
    if (left === 0) return 'dnes';
    if (left === 1) return 'zítra';
    if (left > 1) return `za ${left} ${csPlural(left, 'den', 'dny', 'dní')}`;
    if (left === -1) return 'prošlo včera';
    return `prošlo před ${-left} dny`;
  }
  if (left === 0) return 'today';
  if (left === 1) return 'tomorrow';
  if (left > 1) return `in ${left} days`;
  if (left === -1) return 'expired yesterday';
  return `expired ${-left} days ago`;
}

export function langOf(locale?: string | null): Lang {
  return locale?.toLowerCase().startsWith('cs') ? 'cs' : 'en';
}

export function texts(lang: Lang, d: Due): { title: string; body: string } {
  if (d.kind === 'digest') {
    const n = d.items.length;
    const names = d.items.slice(0, 5).map((i) => i.name).join(', ') + (n > 5 ? '…' : '');
    return lang === 'cs'
      ? { title: '🧊 Co dnes v lednici spěchá', body: `${n} ${csPlural(n, 'věc', 'věci', 'věcí')} brzy projde: ${names}` }
      : { title: '🧊 What needs eating today', body: `${n} ${n === 1 ? 'thing expires' : 'things expire'} soon: ${names}` };
  }
  const item = d.items[0];
  const dateLabel = lang === 'cs'
    ? (item.dateType === 'useBy' ? 'Spotřebujte do' : 'Minimální trvanlivost')
    : (item.dateType === 'useBy' ? 'Use by' : 'Best before');
  return {
    title: `${emoji[item.categoryId] ?? '📦'} ${item.name}`,
    body: `${dateLabel}: ${relative(lang, d.daysLeft ?? 0)}`,
  };
}

export interface Activity { byName: string; type: string }

/** "Jana: přidala 6, snědla 2" */
export function activityText(lang: Lang, list: Activity[]): { title: string; body: string } {
  const by = new Map<string, Record<string, number>>();
  for (const a of list) {
    const m = by.get(a.byName) ?? {};
    m[a.type] = (m[a.type] ?? 0) + 1;
    by.set(a.byName, m);
  }
  const words = lang === 'cs'
    ? { added: 'přidáno', consumed: 'snědeno', discarded: 'vyhozeno' }
    : { added: 'added', consumed: 'eaten', discarded: 'thrown away' };
  const lines = [...by.entries()].map(([name, m]) =>
    `${name || '?'}: ` + (['added', 'consumed', 'discarded'] as const)
      .filter((t) => m[t]).map((t) => `${words[t]} ${m[t]}`).join(', '));
  return { title: lang === 'cs' ? '🏠 Novinky v domácnosti' : '🏠 Household updates', body: lines.join('\n') };
}
