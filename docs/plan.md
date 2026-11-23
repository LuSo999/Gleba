# Plán vývoje

## Fáze 0: Základ
- [x] Flutter projekt (Android + web), struktura podle funkcí, Riverpod, go_router
- [ ] Firebase projekt (Auth, Firestore, Hosting), `flutterfire configure`
- [x] Lokalizace CZ/EN (ARB), Material 3 téma světlé/tmavé
- [x] CI v GitHub Actions: analýza, testy, build APK + web
- [ ] Automatické nasazení webu na Firebase Hosting
- [x] Firestore pravidla
- [ ] Testy pravidel v emulátoru

## Fáze 1: MVP
- [x] Přihlášení (Google, e-mail/heslo), profil
- [x] Domácnosti: vytvoření, přepínání, pozvánka odkazem/kódem, odchod
- [x] Skener: EAN-13/8, UPC, GS1 DataMatrix/QR/128 (parsování AI 15/17), hromadný režim
- [x] Vyhledání produktu: domácnost → Open Food Facts → ručně
- [ ] Sdílená databáze produktů Gleba
- [x] Datum: ručně, z GS1 kódu, návrh podle kategorie
- [x] Parser dat z textu (připraven pro OCR)
- [x] Focení data – ML Kit OCR (Android)
- [x] Položky: kategorie, umístění s auto-návrhem, množství, typ data, otevřeno, zamraženo, zbytky
- [x] Hlavní obrazovka „lednice“ s animacemi + seznam „Spotřebuj nejdřív“
- [x] Upozornění: logika vrstvených pravidel a ranního souhrnu (testováno)
- [x] Upozornění: plánování v telefonu, obrazovka nastavení (výchozí / kategorie / produkt, ranní souhrn), tlačítka Snězeno/Vyhozeno/Odložit
- [ ] Upozornění: aktualizace na pozadí, když něco přidá jiný člen domácnosti (FCM + Cloud Functions, Blaze je zapnutý)
- [x] Offline režim (Firestore cache)
- [x] Alergeny, Nutri-Score

## Fáze 2: Chytré funkce
- [ ] AI: Gemini, OpenAI, Claude – jen vlastní klíče uživatelů (v zařízení / sdílený pro domácnost přes Cloud Functions), poskytovatel volitelný pro každou funkci
- [ ] Účtenky, recepty (+ „zkopírovat zadání“), AI fallback na datum
- [ ] Statistiky, nákupní seznam, minimální zásoby
- [ ] Inventurní režim
- [ ] Widget
- [ ] Web push (FCM + Cloud Functions)

## Fáze 3: Volitelné
- [ ] Health Connect / Samsung Health
- [ ] NFC štítek pro rychlou inventuru
