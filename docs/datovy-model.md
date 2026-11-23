# Datový model (Cloud Firestore)

```
users/{uid}
  displayName, email, locale ('cs'|'en'), activeHouseholdId, createdAt
  /devices/{deviceId}      fcmToken, platform, lastSeenAt
  /notificationRules/{id}  scope: 'default'|'category'|'product', targetId?,
                           enabled, daysBefore, hour, dateType?: 'useBy'|'bestBefore'
  /preferences/main        morningDigest {enabled, hour}, quietHours, animations, partialConsumption

households/{hid}
  name, memberIds[], createdBy, createdAt
  settings { locationsEnabled, currency, aiMode: 'device'|'shared'|'off', aiProvider }
  /invites/{code}          createdBy, expiresAt, maxUses, uses
  /locations/{lid}         name, type: 'fridge'|'freezer'|'pantry'|'other', order, icon
  /categories/{cid}        (jen vlastní; standardní jsou v aplikaci) name, parentId, shelfLife{...}
  /items/{iid}             ean?, name, brand?, imageUrl?, categoryId, locationId?,
                           quantity, unit, dateType, expiryDate, originalExpiryDate,
                           openedAt?, frozenAt?, price?, source: 'scan'|'gs1'|'receipt'|'manual'|'leftover',
                           status: 'active'|'consumed'|'discarded', addedBy, addedAt, updatedAt
  /events/{eid}            itemId, type: 'added'|'consumed'|'discarded'|'opened'|'frozen'|'qty',
                           quantity, price?, by, at          ← zdroj statistik
  /products/{ean}          naučené per domácnost: name, categoryId, locationId, shelfLifeDays, lastPrice
  /shoppingList/{sid}      name, quantity, done, addedBy, fromItemId?
  /stockRules/{rid}        productKey, minQuantity
  /secrets/ai              (jen přes Cloud Function, klient nemá přístup) šifrované API klíče

products/{ean}             sdílená databáze: name, brand, categoryId, imageUrl,
                           shelfLifeStats {count, medianDays}, source, updatedAt
```

## Bezpečnostní pravidla (princip)
- `households/{hid}/**` čte a zapisuje jen uid v `memberIds`.
- **Připojení přes pozvánku bez serveru:** uživatel smí do `memberIds` přidat **pouze sebe**, a to jen pokud v téže dávce (batch) odkazuje na existující, neexpirovanou pozvánku a zvýší jí `uses`. Pravidla to ověří přes `getAfter()`.
- `users/{uid}/**` jen vlastník.
- `products/{ean}`: čtení pro přihlášené, zápis s validací polí (bez osobních údajů).
- `secrets`: klient nemá přístup vůbec.

## Indexy
- `items`: `status ASC, expiryDate ASC` (+ `locationId`)
- `events`: `type, at DESC`
