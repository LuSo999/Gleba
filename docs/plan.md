# Plán vývoje

## Fáze 0: Základ
- [x] Flutter projekt (Android + web), struktura podle funkcí, Riverpod, go_router
- [ ] Firebase projekt (Auth, Firestore, Hosting), `flutterfire configure`
- [x] Lokalizace CZ/EN (ARB), Material 3 téma světlé/tmavé
- [x] CI v GitHub Actions: analýza, testy, build APK + web
- [x] Automatické nasazení webu na Firebase Hosting (https://gleba-e9a60.web.app)
- [x] Rozložení pro velkou obrazovku: lednice + „Spotřebuj nejdřív“ + nákupní seznam vedle sebe, ostatní obrazovky vystředěné
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
- [x] Upozornění ze serveru (Cloud Functions každých 15 min + FCM): okamžitě i pro položky ostatních členů, opakování prošlých, tichý režim, souhrn aktivity ostatních, odložení na zítra
- [x] Historie domácnosti + tlačítko Zpět
- [x] Offline režim (Firestore cache)
- [x] Alergeny, Nutri-Score

## Fáze 2: Chytré funkce
- [x] AI: Gemini, OpenAI, Claude – jen vlastní klíče uživatelů (v zařízení / sdílený pro domácnost přes Cloud Functions), poskytovatel volitelný pro každou funkci
- [x] Účtenky, recepty (+ „zkopírovat zadání“), AI fallback na datum, neznámý produkt z fotky
- [x] Nákupní seznam (sdílený), přidání z detailu produktu, hlídání minimálních zásob s automatickým doplněním
- [x] Statistiky: snězeno včas / vyhozeno (ks, Kč), vývoj po týdnech/měsících, nejčastěji vyhazované kategorie a produkty, kdo co dělá, tipy
- [x] Inventurní režim: karty (je tam / snězeno / část / vyhozeno), filtr podle místa a „po datu“, zpět, týdenní připomínka, upozornění na dlouho prošlé věci na hlavní obrazovce
- [x] Widget na plochu: 5 věcí, které projdou nejdřív (sám se přepočítává o půlnoci), tlačítko + pro skenování
- [ ] ~~Web push~~ (nechceme – upozornění jen do telefonu)

## Fáze 3: Volitelné
- [ ] Health Connect / Samsung Health
- [ ] NFC štítek pro rychlou inventuru
