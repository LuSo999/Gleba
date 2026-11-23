# Plán vývoje

## Fáze 0: Základ
- [ ] Flutter projekt (Android + web), struktura podle funkcí, Riverpod, go_router
- [ ] Firebase projekt (Auth, Firestore, Hosting), `flutterfire configure`
- [ ] Lokalizace CZ/EN (ARB), Material 3 téma světlé/tmavé
- [ ] CI v GitHub Actions: analýza, testy, build APK + web, nasazení webu na Firebase Hosting
- [ ] Firestore pravidla + testy pravidel v emulátoru

## Fáze 1: MVP
- [ ] Přihlášení (Google, e-mail/heslo), profil
- [ ] Domácnosti: vytvoření, přepínání, pozvánka odkazem/kódem, odchod
- [ ] Skener: EAN-13/8, UPC, GS1 DataMatrix/QR/128 (parsování AI 15/17), hromadný režim
- [ ] Vyhledání produktu: cache → domácnost → sdílená DB → Open Food Facts → ručně
- [ ] Datum: ručně, OCR fotky (ML Kit), návrh podle kategorie (FoodKeeper tabulka)
- [ ] Položky: kategorie, umístění s auto-návrhem, množství, typ data, otevřeno, zamraženo, zbytky
- [ ] Hlavní obrazovka „lednice“ s animacemi + seznam „Spotřebuj nejdřív“
- [ ] Upozornění: vrstvená pravidla, ranní souhrn, tlačítka v upozornění, synchronizace na pozadí
- [ ] Offline režim
- [ ] Alergeny, Nutri-Score

## Fáze 2: Chytré funkce
- [ ] AI: Gemini, OpenAI, Claude. Klíč v zařízení / sdílený (Cloud Functions, Blaze)
- [ ] Účtenky, recepty (+ „zkopírovat zadání“), AI fallback na datum
- [ ] Statistiky, nákupní seznam, minimální zásoby
- [ ] Inventurní režim
- [ ] Widget
- [ ] Web push (FCM + Cloud Functions)

## Fáze 3: Volitelné
- [ ] Health Connect / Samsung Health
- [ ] NFC štítek pro rychlou inventuru
