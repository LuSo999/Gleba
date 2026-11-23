import { test } from 'node:test';
import assert from 'node:assert/strict';

import { appUuid, contributionForm, offCategory } from './off.js';

test('contribution form for a new Czech product', () => {
  const f = contributionForm(
    { ean: '8594001021499', name: ' Jogurt bílý Clever ', brand: 'Clever', categoryId: 'yogurt', quantity: '150 g', lang: 'cs' },
    { user: 'gleba-app', password: 'secret' },
    'abc',
  );
  assert.equal(f.get('code'), '8594001021499');
  assert.equal(f.get('product_name_cs'), 'Jogurt bílý Clever');
  assert.equal(f.get('brands'), 'Clever');
  assert.equal(f.get('categories'), 'en:yogurts');
  assert.equal(f.get('countries'), 'en:czech-republic');
  assert.equal(f.get('app_name'), 'Gleba');
  assert.equal(f.get('app_uuid'), 'abc');
  assert.equal(f.get('user_id'), 'gleba-app');
});

test('app uuid is stable, salted and not the uid', () => {
  assert.equal(appUuid('uid1', 's'), appUuid('uid1', 's'));
  assert.notEqual(appUuid('uid1', 's'), appUuid('uid1', 't'));
  assert.ok(!appUuid('uid1', 's').includes('uid1'));
  assert.equal(appUuid('uid1', 's').length, 32);
});

test('every Gleba category except "other" maps to an OFF tag', () => {
  for (const v of Object.values(offCategory)) assert.match(v, /^en:[a-z-]+$/);
});
