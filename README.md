# Gleba 🧊

Aplikace pro evidenci potravin v lednici, mrazáku a spíži: naskenuješ EAN, vyfotíš nebo zadáš datum spotřeby a Gleba ti včas připomene, co je potřeba sníst. Domácnost sdílíš s ostatními.

- **Platformy:** Android (primárně) + web (PWA, použitelné i na iOS)
- **Technologie:** Flutter, Firebase (Auth, Firestore, Hosting, FCM, Cloud Functions), ML Kit
- **Jazyky:** čeština, angličtina

## Dokumentace
- [Specifikace](docs/specifikace.md): co aplikace umí a proč
- [Datový model](docs/datovy-model.md): struktura Firestore a bezpečnostní pravidla
- [Zdroje dat](docs/zdroje-dat.md): odkud bereme informace o produktech a trvanlivosti
- [Plán vývoje](docs/plan.md): fáze a pořadí prací

## Vývoj

```bash
flutter pub get
flutter run -d chrome     # web
flutter run               # připojený Android telefon
flutter test              # testy
```

Dokud není nastavený Firebase, aplikace běží v **ukázkovém režimu**: přihlásí se kýmkoli, data drží jen v paměti a předvyplní ukázkovou lednici.

### Struktura
```
lib/
  domain/   čistá logika bez závislostí – modely, čtení GS1 kódů a dat z OCR,
            tabulka trvanlivostí, pravidla upozornění (vše pokryto testy)
  data/     Firestore, Open Food Facts, ukázkový (in-memory) backend
  ui/       obrazovky, lednice s animacemi, téma
  l10n/     překlady CZ/EN (.arb)
firestore.rules   bezpečnostní pravidla
```

### Napojení na Firebase
1. Ve [Firebase konzoli](https://console.firebase.google.com) založte projekt.
2. **Authentication** → zapněte poskytovatele *Google* a *E-mail/heslo*.
3. **Firestore Database** → vytvořte databázi (region `eur3` nebo `europe-west3`).
4. Lokálně:
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   flutterfire configure --project=<ID-projektu> --platforms=android,web
   ```
   Tím se přepíše `lib/firebase_options.dart` a aplikace se sama přepne z ukázkového režimu na Firebase.
5. Do `.firebaserc` doplňte ID projektu a nasaďte pravidla a web:
   ```bash
   firebase deploy --only firestore
   flutter build web && firebase deploy --only hosting
   ```
6. Pro přihlášení Googlem na Androidu přidejte do Firebase SHA-1 otisk podpisového klíče
   (`cd android && ./gradlew signingReport`).
7. V `lib/config.dart` upravte `kWebAppUrl` na adresu z Firebase Hosting (kvůli odkazům v pozvánkách).

### Podpis Android aplikace
- `android/app/debug.keystore` je **sdílený ladicí klíč** (heslo `android`). Je v repozitáři záměrně, aby každé sestavení (lokálně i na GitHubu) mělo stejný otisk a fungovalo přihlášení Googlem. Otisky registrované ve Firebase:
  - SHA-1 `27:0B:E0:D7:4E:F1:E0:02:4D:BC:CB:06:0E:8A:41:65:88:DD:8E:34`
  - SHA-256 `28:A3:82:AB:C2:37:0C:CF:14:E2:EF:3D:54:56:AF:74:ED:B1:25:4F:C6:D3:CE:63:52:04:A4:55:6B:C9:48:FF`
- Pro vydání na Google Play vytvoříme samostatný **produkční klíč**, který do repozitáře nikdy nepatří (GitHub Secrets).

### Upozornění (server)
Upozornění posílá server (`functions/`, Cloud Functions v regionu `europe-west3`): každých 15 minut projde položky, použije pravidla každého uživatele a pošle push do jeho telefonů (FCM). Telefon nic neplánuje, jen zobrazí zprávu s tlačítky Snězeno / Vyhozeno / Zítra.

```bash
cd functions && npm ci && npm test   # testy plánovače (časová pásma, tichý režim, odložení…)
```

### Nasazení serveru
Nasazuje GitHub Action **Deploy to Firebase** při každé změně v `main` (nebo ručně v záložce Actions): web na Firebase Hosting (https://gleba-e9a60.web.app), Cloud Functions a pravidla Firestore. Potřebuje jednorázově tajný klíč:
1. [Google Cloud konzole → IAM → Service accounts](https://console.cloud.google.com/iam-admin/serviceaccounts?project=gleba-e9a60) → **Create service account** (např. `github-deploy`).
2. Role: **Editor** (Upravovatel). Pro osobní projekt nejjednodušší varianta; nasazení funkcí potřebuje přístup k Cloud Functions, Cloud Build, Artifact Registry, Cloud Scheduler a Firestore.
3. U účtu → **Keys** → **Add key** → **JSON** → stáhne se soubor.
4. GitHub → repozitář → **Settings → Secrets and variables → Actions → New repository secret**: název `FIREBASE_SERVICE_ACCOUNT`, hodnota = celý obsah JSON souboru. Soubor pak smažte.
