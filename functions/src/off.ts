/**
 * Contributing new products to Open Food Facts with Gleba's app account.
 * Docs: https://openfoodfacts.github.io/openfoodfacts-server/api (Write API).
 * - writes need a login; apps use one global account plus a salted per-user
 *   `app_uuid`, so moderators can ban a single abuser, not the whole app;
 * - we only ADD products OFF doesn't know – existing ones are never touched.
 */
import { createHash } from 'node:crypto';

/** Gleba category → OFF category tag (English taxonomy). */
export const offCategory: Record<string, string> = {
  frozen: 'en:frozen-foods', leftovers: 'en:meals', readyMeal: 'en:meals', yogurt: 'en:yogurts',
  cheeseSoft: 'en:fresh-cheeses', cheeseHard: 'en:cheeses', butter: 'en:butters', milkUht: 'en:milks',
  milk: 'en:milks', eggs: 'en:eggs', deli: 'en:prepared-meats', poultry: 'en:poultries', fish: 'en:fishes',
  meat: 'en:meats', rootVeg: 'en:vegetables', vegetables: 'en:vegetables', fruit: 'en:fruits', bread: 'en:breads',
  drinks: 'en:beverages', sauces: 'en:sauces', canned: 'en:canned-foods', dry: 'en:groceries', sweets: 'en:snacks',
};

export interface OffContribution {
  ean: string;
  name: string;
  brand?: string | null;
  categoryId?: string | null;
  quantity?: string | null;
  lang: 'cs' | 'en';
}

export interface OffAccount { user: string; password: string; server?: string }

/** Salted per-user id, stable but not reversible to the Firebase uid. */
export function appUuid(uid: string, salt: string): string {
  return createHash('sha256').update(`${salt}:${uid}`).digest('hex').slice(0, 32);
}

export function contributionForm(c: OffContribution, account: OffAccount, uuid: string): URLSearchParams {
  const f = new URLSearchParams({
    code: c.ean,
    user_id: account.user,
    password: account.password,
    lang: c.lang,
    [`product_name_${c.lang}`]: c.name.trim().slice(0, 200),
    app_name: 'Gleba',
    app_version: '1',
    app_uuid: uuid,
    comment: 'Added from the Gleba app (user-entered name/brand/category)',
  });
  if (c.brand?.trim()) f.set('brands', c.brand.trim().slice(0, 100));
  const cat = c.categoryId ? offCategory[c.categoryId] : undefined;
  if (cat) f.set('categories', cat);
  if (c.quantity?.trim()) f.set('quantity', c.quantity.trim().slice(0, 50));
  // Sold in Czechia – it's where Gleba users shop.
  f.set('countries', 'en:czech-republic');
  return f;
}

const base = (a: OffAccount) => a.server || 'https://world.openfoodfacts.org';
const headers = { 'User-Agent': 'Gleba/1.0 (open-source pantry app)' };

/** true when OFF already knows the product (then we don't touch it). */
export async function offHasProduct(ean: string, account: OffAccount): Promise<boolean> {
  const res = await fetch(`${base(account)}/api/v2/product/${ean}.json?fields=code`, { headers });
  if (!res.ok) return false;
  const json: any = await res.json().catch(() => ({}));
  return json?.status === 1;
}

export async function submitToOff(c: OffContribution, account: OffAccount, uuid: string): Promise<void> {
  const res = await fetch(`${base(account)}/cgi/product_jqm2.pl`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/x-www-form-urlencoded' },
    body: contributionForm(c, account, uuid),
  });
  const json: any = await res.json().catch(() => ({}));
  if (!res.ok || json?.status !== 1) throw new Error(json?.status_verbose ?? `HTTP ${res.status}`);
}
