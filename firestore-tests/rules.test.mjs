// Security-rule tests for ../firestore.rules, run against the emulator:
//   npm test   (firebase emulators:exec … node --test)
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp, doc, getDoc, increment, arrayUnion, arrayRemove, setDoc, updateDoc, writeBatch, collection, getDocs } from 'firebase/firestore';

let env;
const day = 24 * 3600 * 1000;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-gleba',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8181 },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  // Seed with rules disabled: Jana's household with an invite.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'households/h1'), { name: 'Domov', memberIds: ['jana'], createdBy: 'jana' });
    await setDoc(doc(db, 'households/h1/items/i1'), { name: 'Mléko', status: 'active' });
    await setDoc(doc(db, 'households/h1/secrets/ai'), { gemini: { key: 'secret' } });
    await setDoc(doc(db, 'invites/ABCDEFGH'), {
      householdId: 'h1', householdName: 'Domov', createdBy: 'jana', uses: 0, maxUses: 10,
      expiresAt: Timestamp.fromMillis(Date.now() + 7 * day),
    });
    await setDoc(doc(db, 'invites/OLDOLDOL'), {
      householdId: 'h1', householdName: 'Domov', createdBy: 'jana', uses: 0, maxUses: 10,
      expiresAt: Timestamp.fromMillis(Date.now() - day),
    });
    await setDoc(doc(db, 'config/off'), { user: 'gleba-app', password: 'x' });
    await setDoc(doc(db, 'products/8594001021499'), {
      name: 'Jogurt', categoryId: 'yogurt', source: 'gleba', shelfLifeStats: { count: 1, avgDays: 14 },
    });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

test('nobody outside the household sees it', async () => {
  await assertFails(getDoc(doc(anon(), 'households/h1')));
  await assertFails(getDoc(doc(as('eve'), 'households/h1')));
  await assertFails(getDoc(doc(as('eve'), 'households/h1/items/i1')));
  await assertSucceeds(getDoc(doc(as('jana'), 'households/h1/items/i1')));
});

test('members manage items; AI secrets are never readable', async () => {
  await assertSucceeds(setDoc(doc(as('jana'), 'households/h1/items/i2'), { name: 'Sýr', status: 'active' }));
  await assertSucceeds(setDoc(doc(as('jana'), 'households/h1/meals/m1'), { date: '2026-11-24', title: 'Guláš' }));
  await assertFails(getDoc(doc(as('eve'), 'households/h1/meals/m1')));
  await assertFails(setDoc(doc(as('eve'), 'households/h1/items/i3'), { name: 'Hack' }));
  await assertFails(getDoc(doc(as('jana'), 'households/h1/secrets/ai')));
  await assertFails(setDoc(doc(as('jana'), 'households/h1/secrets/ai'), { gemini: { key: 'mine' } }));
});

test('a household can only be created for yourself, with its locations in one batch', async () => {
  const db = as('lubos');
  const b = writeBatch(db);
  b.set(doc(db, 'households/h2'), { name: 'Chata', memberIds: ['lubos'], createdBy: 'lubos' });
  b.set(doc(db, 'households/h2/locations/fridge'), { type: 'fridge', order: 0 });
  await assertSucceeds(b.commit());
  await assertFails(setDoc(doc(as('lubos'), 'households/h3'), { name: 'X', memberIds: ['jana'], createdBy: 'lubos' }));
});

test('joining with a valid invite works only together with using it up', async () => {
  const db = as('lubos');
  const join = (code) => {
    const b = writeBatch(db);
    b.update(doc(db, `invites/${code}`), { uses: increment(1) });
    b.update(doc(db, 'households/h1'), { memberIds: arrayUnion('lubos'), lastJoinCode: code });
    return b.commit();
  };
  await assertFails(join('OLDOLDOL')); // expired
  await assertFails(updateDoc(doc(db, 'households/h1'), { memberIds: arrayUnion('lubos'), lastJoinCode: 'ABCDEFGH' })); // no use
  await assertSucceeds(join('ABCDEFGH'));
  await assertSucceeds(getDoc(doc(db, 'households/h1/items/i1')));
});

test('you cannot add someone else, but you can leave', async () => {
  const db = as('eve');
  const b = writeBatch(db);
  b.update(doc(db, 'invites/ABCDEFGH'), { uses: increment(1) });
  b.update(doc(db, 'households/h1'), { memberIds: arrayUnion('mallory'), lastJoinCode: 'ABCDEFGH' });
  await assertFails(b.commit());
  await assertFails(updateDoc(doc(as('eve'), 'households/h1'), { memberIds: arrayRemove('jana') }));
  await assertSucceeds(updateDoc(doc(as('jana'), 'households/h1'), { memberIds: arrayRemove('jana') }));
});

test('invites: get by code only, created only by members', async () => {
  await assertSucceeds(getDoc(doc(as('eve'), 'invites/ABCDEFGH')));
  await assertFails(getDocs(collection(as('eve'), 'invites')));
  const invite = { householdId: 'h1', householdName: 'Domov', uses: 0, maxUses: 10, expiresAt: Timestamp.fromMillis(Date.now() + day) };
  await assertSucceeds(setDoc(doc(as('jana'), 'invites/QWERTYUP'), { ...invite, createdBy: 'jana' }));
  await assertFails(setDoc(doc(as('eve'), 'invites/ZXCVBNMK'), { ...invite, createdBy: 'eve' }));
});

test('users only see their own data; server config is private', async () => {
  await assertSucceeds(setDoc(doc(as('jana'), 'users/jana/devices/d1'), { token: 't' }));
  await assertFails(getDoc(doc(as('eve'), 'users/jana/devices/d1')));
  await assertFails(getDoc(doc(as('jana'), 'config/off')));
});

test('shared products: add new, add a shelf-life sample, never rename', async () => {
  const db = as('eve');
  await assertSucceeds(setDoc(doc(db, 'products/96385074'), {
    name: 'Rohlík', categoryId: 'bread', source: 'gleba', shelfLifeStats: { count: 1, avgDays: 2 },
  }));
  await assertFails(setDoc(doc(db, 'products/abc'), { name: 'X', categoryId: 'other', shelfLifeStats: { count: 0, avgDays: 0 } }));
  await assertFails(updateDoc(doc(db, 'products/8594001021499'), { name: 'Spam' }));
  await assertSucceeds(updateDoc(doc(db, 'products/8594001021499'), { shelfLifeStats: { count: 2, avgDays: 15 } }));
  await assertFails(updateDoc(doc(db, 'products/8594001021499'), { shelfLifeStats: { count: 9, avgDays: 15 } }));
  await assertFails(getDoc(doc(anon(), 'products/8594001021499')));
});
