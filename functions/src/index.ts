/**
 * Gleba Cloud Functions.
 *
 *  - notify: every 15 minutes, works out which expiry notifications are due for
 *    every user (their own rules, all their households) and sends them via FCM.
 *    Members who opted in also get one summary of what the others in the
 *    household added / ate / threw away since the last summary.
 *
 * Only a scheduled function (no Firestore triggers), so it works whatever
 * region the Firestore database is in.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

import { AiError, callProvider, defaultModels, listModels, type Provider } from './ai.js';
import { activityText, langOf, texts } from './i18n.js';
import { appUuid, offHasProduct, submitToOff, type OffAccount } from './off.js';
import { defaultPrefs, plan, type Item, type Prefs, type Rule } from './planner.js';
import { localDate, localMinutes } from './time.js';
import { inQuiet } from './planner.js';

initializeApp();
const db = getFirestore();
const REGION = 'europe-west3';
const SENT_TTL_DAYS = 45;

interface Device { token: string; tz?: string; locale?: string }

function toDate(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  return null;
}

async function sendToUser(uid: string, devices: { id: string; data: Device }[], data: Record<string, string>) {
  const tokens = devices.map((d) => d.data.token).filter(Boolean);
  if (!tokens.length) return;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    data,
    android: { priority: 'high', ttl: 6 * 3600 * 1000 },
  });
  // Forget devices whose token is no longer valid (app uninstalled, etc.).
  await Promise.all(res.responses.map((r, i) => {
    const code = r.error?.code ?? '';
    if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
      const dev = devices.find((d) => d.data.token === tokens[i]);
      return dev ? db.doc(`users/${uid}/devices/${dev.id}`).delete() : null;
    }
    return null;
  }));
}

async function processUser(uid: string, now: Date) {
  const userRef = db.doc(`users/${uid}`);
  const [devSnap, prefsSnap, rulesSnap, snoozeSnap, households] = await Promise.all([
    userRef.collection('devices').get(),
    userRef.collection('preferences').doc('notifications').get(),
    userRef.collection('notificationRules').get(),
    userRef.collection('snoozes').get(),
    db.collection('households').where('memberIds', 'array-contains', uid).get(),
  ]);
  const devices = devSnap.docs.map((d) => ({ id: d.id, data: d.data() as Device })).filter((d) => d.data.token);
  if (!devices.length) return;
  const tz = devices[0].data.tz || 'Europe/Prague';
  const lang = langOf(devices[0].data.locale);
  const prefs: Prefs = { ...defaultPrefs, ...(prefsSnap.data() as Partial<Prefs> | undefined) };
  const rules = rulesSnap.docs.map((d) => d.data() as Rule);
  const snoozes: Record<string, Date> = {};
  for (const s of snoozeSnap.docs) {
    const until = toDate(s.get('until'));
    if (until) snoozes[s.id] = until;
  }

  const items: Item[] = [];
  for (const h of households.docs) {
    const snap = await h.ref.collection('items').where('status', '==', 'active').get();
    for (const d of snap.docs) {
      const exp = toDate(d.get('expiryDate'));
      if (!exp) continue;
      items.push({
        id: d.id, householdId: h.id, name: d.get('name') ?? '', categoryId: d.get('categoryId') ?? 'other',
        ean: d.get('ean') ?? null, expiry: localDate(exp, tz),
        dateType: d.get('dateType') === 'bestBefore' ? 'bestBefore' : 'useBy',
      });
    }
  }

  // Which of the candidate keys were already sent?
  const candidates = plan({ now, tz, items, rules, prefs, snoozes, alreadySent: new Set() });
  const sentRefs = candidates.map((c) => userRef.collection('sent').doc(c.key.replace(/\//g, '_')));
  const sentDocs = sentRefs.length ? await db.getAll(...sentRefs) : [];
  const alreadySent = new Set(candidates.filter((_, i) => sentDocs[i].exists).map((c) => c.key));
  const due = candidates.filter((c) => !alreadySent.has(c.key));

  for (const [i, d] of due.entries()) {
    const t = texts(lang, d);
    const single = d.kind === 'soon' || d.kind === 'expired' || d.kind === 'snooze';
    await sendToUser(uid, devices, {
      kind: d.kind,
      title: t.title,
      body: t.body,
      tag: d.key,
      householdId: single ? d.items[0].householdId : '',
      itemId: single ? d.items[0].id : '',
    });
    const expireAt = Timestamp.fromMillis(now.getTime() + SENT_TTL_DAYS * 86400000);
    await sentRefs[candidates.indexOf(d)].set({ key: d.key, at: FieldValue.serverTimestamp(), expireAt });
    if (d.kind === 'snooze') await userRef.collection('snoozes').doc(d.items[0].id).delete();
    logger.debug('sent', { uid, key: d.key, i });
  }

  // Household activity summary (opt-in), outside quiet hours.
  const stateRef = userRef.collection('state').doc('notify');
  if (prefs.othersActivity && !inQuiet(localMinutes(now, tz), prefs)) {
    const since = toDate((await stateRef.get()).get('activitySince')) ?? now;
    const activity: { byName: string; type: string }[] = [];
    for (const h of households.docs) {
      const ev = await h.ref.collection('events').where('at', '>', Timestamp.fromDate(since))
        .where('at', '<=', Timestamp.fromDate(now)).get();
      for (const e of ev.docs) {
        if (e.get('by') !== uid && ['added', 'consumed', 'discarded'].includes(e.get('type'))) {
          activity.push({ byName: e.get('byName') ?? '', type: e.get('type') });
        }
      }
    }
    if (activity.length) {
      const t = activityText(lang, activity);
      await sendToUser(uid, devices, { kind: 'activity', title: t.title, body: t.body, tag: 'activity' });
    }
    await stateRef.set({ activitySince: Timestamp.fromDate(now) }, { merge: true });
  } else if (!prefs.othersActivity) {
    await stateRef.set({ activitySince: Timestamp.fromDate(now) }, { merge: true });
  }

  // Housekeeping: drop old idempotency records.
  const old = await userRef.collection('sent').where('expireAt', '<', Timestamp.fromDate(now)).limit(200).get();
  if (!old.empty) {
    const batch = db.batch();
    old.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

export const notify = onSchedule(
  { schedule: 'every 15 minutes', region: REGION, timeZone: 'Europe/Prague', memory: '256MiB', maxInstances: 1 },
  async () => {
    const now = new Date();
    // Users with at least one registered phone.
    const devices = await db.collectionGroup('devices').select().get();
    const uids = new Set(devices.docs.map((d) => d.ref.parent.parent!.id));
    for (const uid of uids) {
      try {
        await processUser(uid, now);
      } catch (e) {
        logger.error('notify failed', { uid, error: String(e) });
      }
    }
    logger.info('notify done', { users: uids.size, at: localDate(now, 'Europe/Prague') });
  },
);

// ---------------------------------------------------------------------------
// AI with the household's shared API key (key stays on the server).

const providers = ['gemini', 'openai', 'anthropic'] as const;

async function requireMember(uid: string | undefined, hid: unknown) {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (typeof hid !== 'string' || !hid) throw new HttpsError('invalid-argument', 'householdId missing');
  const h = await db.doc(`households/${hid}`).get();
  if (!h.exists || !(h.get('memberIds') ?? []).includes(uid)) {
    throw new HttpsError('permission-denied', 'Not a member of this household.');
  }
  return h;
}

/** Saves (or with key = null removes) a provider key shared by the household. */
export const aiSetKey = onCall({ region: REGION }, async (req) => {
  const { householdId, provider, key, model } = req.data ?? {};
  await requireMember(req.auth?.uid, householdId);
  if (!providers.includes(provider)) throw new HttpsError('invalid-argument', 'Unknown provider');
  const secretRef = db.doc(`households/${householdId}/secrets/ai`);
  const hRef = db.doc(`households/${householdId}`);
  if (key == null || key === '') {
    await secretRef.set({ [provider]: FieldValue.delete() }, { merge: true });
    await hRef.update({ [`ai.${provider}`]: FieldValue.delete() });
    return { ok: true };
  }
  if (typeof key !== 'string' || key.length > 500) throw new HttpsError('invalid-argument', 'Bad key');
  const m = typeof model === 'string' && model ? model : defaultModels[provider as Provider];
  await secretRef.set({ [provider]: { key, model: m, by: req.auth!.uid } }, { merge: true });
  // Members only see that a shared key exists, never the key itself.
  await hRef.update({ [`ai.${provider}`]: { model: m } });
  return { ok: true };
});

/** Runs an AI request with the household's shared key. */
export const aiProxy = onCall({ region: REGION, timeoutSeconds: 120, memory: '512MiB' }, async (req) => {
  const { householdId, provider, prompt, images, schema, maxTokens, model } = req.data ?? {};
  await requireMember(req.auth?.uid, householdId);
  if (!providers.includes(provider)) throw new HttpsError('invalid-argument', 'Unknown provider');
  if (typeof prompt !== 'string' || prompt.length > 20000) throw new HttpsError('invalid-argument', 'Bad prompt');
  const secret = (await db.doc(`households/${householdId}/secrets/ai`).get()).get(provider);
  if (!secret?.key) throw new HttpsError('failed-precondition', 'No shared key for this provider.');
  try {
    // A per-feature model chosen in the app wins over the key's default.
    const useModel = typeof model === 'string' && /^[\w.\-:/]{1,100}$/.test(model) ? model : secret.model;
    const text = await callProvider(provider, secret.key, useModel, {
      prompt,
      images: Array.isArray(images) ? images.slice(0, 4) : [],
      schema: schema ?? null,
      maxTokens: typeof maxTokens === 'number' ? Math.min(maxTokens, 16000) : undefined,
    });
    return { text };
  } catch (e) {
    logger.warn('ai call failed', { provider, error: String(e) });
    throw new HttpsError('unavailable', e instanceof AiError ? e.message : 'AI request failed');
  }
});

/** Models the household's shared key can use (the key never leaves the server). */
export const aiListModels = onCall({ region: REGION, timeoutSeconds: 30 }, async (req) => {
  const { householdId, provider } = req.data ?? {};
  await requireMember(req.auth?.uid, householdId);
  if (!providers.includes(provider)) throw new HttpsError('invalid-argument', 'Unknown provider');
  const secret = (await db.doc(`households/${householdId}/secrets/ai`).get()).get(provider);
  if (!secret?.key) throw new HttpsError('failed-precondition', 'No shared key for this provider.');
  try {
    return { models: await listModels(provider, secret.key) };
  } catch (e) {
    throw new HttpsError('unavailable', e instanceof AiError ? e.message : 'Could not list models');
  }
});

// ---------------------------------------------------------------------------
// Open Food Facts contributions (opt-in per user, new products only).

const OFF_DAILY_LIMIT = 30;

export const offContribute = onCall({ region: REGION, timeoutSeconds: 30 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const { ean, name, brand, categoryId, quantity, lang } = req.data ?? {};
  if (typeof ean !== 'string' || !/^(\d{8}|\d{13})$/.test(ean) || /^2\d/.test(ean)) {
    throw new HttpsError('invalid-argument', 'Not a shareable EAN');
  }
  if (typeof name !== 'string' || !name.trim() || name.length > 200) throw new HttpsError('invalid-argument', 'Bad name');

  // Gleba's OFF app account, written by the deploy workflow (never readable by clients).
  const cfg = (await db.doc('config/off').get()).data() as (OffAccount & { salt?: string }) | undefined;
  if (!cfg?.user || !cfg.password) throw new HttpsError('failed-precondition', 'off-not-configured');

  // Per-user daily limit (spam protection on top of OFF's own).
  const today = new Date().toISOString().slice(0, 10);
  const limitRef = db.doc(`users/${uid}/state/off`);
  const ok = await db.runTransaction(async (tx) => {
    const s = (await tx.get(limitRef)).data();
    const count = s?.day === today ? (s.count as number) : 0;
    if (count >= OFF_DAILY_LIMIT) return false;
    tx.set(limitRef, { day: today, count: count + 1 });
    return true;
  });
  if (!ok) throw new HttpsError('resource-exhausted', 'Daily limit reached');

  if (await offHasProduct(ean, cfg)) return { status: 'exists' };
  try {
    await submitToOff(
      { ean, name, brand, categoryId, quantity, lang: lang === 'en' ? 'en' : 'cs' },
      cfg,
      appUuid(uid, cfg.salt ?? 'gleba'),
    );
  } catch (e) {
    logger.warn('OFF contribution failed', { ean, error: String(e) });
    throw new HttpsError('unavailable', 'Open Food Facts did not accept the product');
  }
  logger.info('OFF contribution', { ean });
  return { status: 'added' };
});

// ---------------------------------------------------------------------------
// Account deletion (required by Google Play): the user's own data, their
// membership in shared households, households where they were the only
// member, and the sign-in account itself.

export const deleteAccount = onCall({ region: REGION, timeoutSeconds: 120 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const households = await db.collection('households').where('memberIds', 'array-contains', uid).get();
  for (const h of households.docs) {
    const members: string[] = h.get('memberIds') ?? [];
    if (members.length <= 1) {
      await db.recursiveDelete(h.ref); // nobody else uses it
    } else {
      await h.ref.update({ memberIds: FieldValue.arrayRemove(uid) });
    }
  }
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await getAuth().deleteUser(uid);
  logger.info('account deleted', { households: households.size });
  return { ok: true };
});
