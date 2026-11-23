/** Time-zone helpers built on Intl (no dependencies). Dates are "YYYY-MM-DD" local dates. */

const dtf = new Map<string, Intl.DateTimeFormat>();
function fmt(tz: string): Intl.DateTimeFormat {
  let f = dtf.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-CA', {
      timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
    });
    dtf.set(tz, f);
  }
  return f;
}

interface Parts { y: number; m: number; d: number; h: number; mi: number; s: number }

export function partsIn(date: Date, tz: string): Parts {
  const p: Record<string, number> = {};
  for (const x of fmt(tz).formatToParts(date)) if (x.type !== 'literal') p[x.type] = Number(x.value);
  return { y: p.year, m: p.month, d: p.day, h: p.hour, mi: p.minute, s: p.second };
}

/** Local calendar date of an instant in a time zone. */
export function localDate(date: Date, tz: string): string {
  const p = partsIn(date, tz);
  return `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
}

/** Minutes since local midnight. */
export function localMinutes(date: Date, tz: string): number {
  const p = partsIn(date, tz);
  return p.h * 60 + p.mi;
}

/** The instant of a local wall-clock time (handles DST by re-checking the offset). */
export function zonedTime(day: string, minutes: number, tz: string): Date {
  const [y, m, d] = day.split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d, Math.floor(minutes / 60), minutes % 60);
  let t = guess;
  for (let i = 0; i < 2; i++) {
    const p = partsIn(new Date(t), tz);
    const asUtc = Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi);
    t = guess - (asUtc - t);
  }
  return new Date(t);
}

export function addDays(day: string, n: number): string {
  const [y, m, d] = day.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return t.toISOString().slice(0, 10);
}

export function daysBetween(from: string, to: string): number {
  const a = Date.parse(from + 'T00:00:00Z'), b = Date.parse(to + 'T00:00:00Z');
  return Math.round((b - a) / 86400000);
}
