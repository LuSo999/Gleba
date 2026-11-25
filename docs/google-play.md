# Gleba na Google Play

Podklady pro Play Console. Texty jsou připravené ke zkopírování, grafika je v `docs/play/`.

## 0. Předpoklady

- Ověřená identita vývojářského účtu v Play Console.
- **Testovací účet pro kontrolu Googlu.** Aplikace vyžaduje přihlášení, proto v Gleba založ účet e-mailem a heslem (například `gleba.review@…`), dej do něj pár potravin a jeho údaje vyplň v *Obsah aplikace → Přístup k aplikaci*.
- GitHub secrets pro podepsaný build: `GLEBA_UPLOAD_KEYSTORE_BASE64`, `GLEBA_UPLOAD_STORE_PASSWORD`, `GLEBA_UPLOAD_KEY_PASSWORD` (upload klíč, alias `upload`).

## 1. Vytvoření aplikace

| Pole | Hodnota |
|---|---|
| Název | Gleba |
| Výchozí jazyk | čeština (cs-CZ), překlad en-US |
| Aplikace / hra | Aplikace |
| Zdarma / placená | Zdarma |
| Balíček (ID aplikace) | `com.gleba.food.app` |

## 2. První build (AAB)

1. GitHub → Actions → **Release (Google Play)** → *Run workflow*. Vznikne artefakt `gleba-release-aab` se souborem `app-release.aab`. Případně pushni tag `v1.0.0`.
2. Play Console → *Testování → Interní testování* → nové vydání → nahraj `app-release.aab` a přijmi Play App Signing.
3. **Důležité pro přihlášení přes Google:** Play Console → *Integrita aplikace → Podepisování aplikací* → zkopíruj **SHA-1 a SHA-256 klíče pro podepisování aplikací** (ne upload klíče) a přidej je ve Firebase (Nastavení projektu → Android aplikace `com.gleba.food.app` → Přidat otisk). Bez nich přihlášení přes Google v aplikaci z Play selže.
   - Otisky upload klíče (pro úplnost):
     - SHA-1 `29:50:76:99:3A:14:E1:68:B6:82:73:F2:AF:C3:7D:B4:A8:F2:B1:D6`
     - SHA-256 `52:B7:B7:39:0F:2C:35:D4:A1:C9:36:64:F1:32:2E:46:6E:E1:33:07:53:81:10:34:B4:D1:98:6A:3D:9B:8A:B5`
4. Pozvi testery (e-maily) a pošli jim odkaz z interního testování.

Automatické nahrávání: s GitHub secretem `PLAY_SERVICE_ACCOUNT` (JSON servisního účtu s přístupem k aplikaci v Play Console) workflow nahraje AAB rovnou do interního testování jako koncept.

## 3. Záznam v obchodě

### Čeština
**Krátký popis (max 80 znaků)**
> Hlídá, co máte v lednici a kdy to projde. Sdílené s celou domácností.

**Úplný popis**
> Gleba hlídá jídlo v lednici, mrazáku a spíži, abyste nic nevyhazovali.
>
> • Naskenujte čárový kód: název, kategorii i nutriční hodnoty najde sama (Open Food Facts a databáze Gleby).
> • Datum spotřeby vyfoťte, aplikace ho přečte. Nebo ho zadejte ručně a Gleba podle kategorie navrhne, jak dlouho jídlo vydrží.
> • Lednice, mrazák a spíž přehledně na policích, barvy podle čerstvosti.
> • Upozornění dva dny před koncem, ranní souhrn a vlastní pravidla pro kategorie i produkty.
> • Sdílená domácnost: pozvěte partnera nebo spolubydlící odkazem či kódem, všichni vidí totéž i offline.
> • Kdo snědl? Jídlo rozdělíte mezi členy domácnosti a každému se jeho díl zapíše do Health Connect (Samsung Health).
> • Historie s tlačítkem Zpět, inventura přejížděním karet, nákupní seznam, hlídání zásob a jídelníček.
> • Statistiky: kolik jste snědli včas, co nejčastěji vyhazujete a kolik to stojí.
> • Volitelně AI s vlastním klíčem (Gemini, ChatGPT, Claude): přečte účtenku, poradí recept ze zbytků, naplánuje jídla.
>
> Bez reklam a bez sledování. Funguje i na webu.

### English
**Short description**
> Knows what's in your fridge and when it expires. Shared with your household.

**Full description**
> Gleba keeps track of the food in your fridge, freezer and pantry so nothing goes to waste.
>
> • Scan a barcode: name, category and nutrition are filled in (Open Food Facts and Gleba's own database).
> • Snap the expiry date and the app reads it, or type it and Gleba suggests how long the food keeps.
> • Fridge, freezer and pantry on shelves, coloured by freshness.
> • Reminders two days ahead, a morning digest and your own rules per category or product.
> • Shared household: invite your partner or flatmates by link or code; everyone sees the same, even offline.
> • Who ate it? Split food between household members, each share goes to their Health Connect (Samsung Health).
> • History with undo, swipe-through inventory, shopping list, stock keeping and meal planning.
> • Statistics: how much you ate in time, what you throw away most and what it costs.
> • Optional AI with your own key (Gemini, ChatGPT, Claude): reads receipts, suggests recipes from leftovers, plans meals.
>
> No ads, no tracking. Also works on the web.

### Grafika (`docs/play/`)
- Ikona 512×512: `icon-512.png`
- Hlavní obrázek 1024×500: `feature-graphic-1024x500.png`
- Snímky telefonu 1080×2160: `screenshot-1.png` až `screenshot-5.png` (domov, vnitřek lednice, Kdo snědl?, Spotřebuj nejdřív, statistiky)

### Kategorie a kontakty
- Kategorie: **Jídlo a pití** (Food & Drink), štítky: kuchyně, nákupy, zdraví
- E-mail: `lubomirsoustruznik@email.cz`
- Web: `https://gleba-e9a60.web.app`
- Zásady ochrany soukromí: `https://gleba-e9a60.web.app/privacy.html`

## 4. Obsah aplikace (App content)

| Sekce | Odpověď |
|---|---|
| Zásady ochrany soukromí | `https://gleba-e9a60.web.app/privacy.html` |
| Přístup k aplikaci | Vše nebo část je omezená, přihlášení e-mailem: testovací účet z bodu 0 |
| Reklamy | Ne |
| Hodnocení obsahu (IARC) | Kategorie *Utility, Productivity…*; násilí, sex, hazard, drogy: ne; sdílení polohy: ne; uživatelé spolu komunikují: ne (data sdílí jen pozvaná domácnost); nákupy digitálního zboží: ne. Výsledek PEGI 3 / Everyone |
| Cílová skupina | 18+ (nejjednodušší, bez programu Rodiny); případně 13+ |
| Zpravodajská aplikace | Ne |
| Vládní / finanční / zdravotnická | Ne (Health Connect je jen zápis výživy, viz níže) |
| Smazání účtu | V aplikaci: Nastavení → Smazat účet. Webový odkaz: `https://gleba-e9a60.web.app/delete-account.html` |

### Bezpečnost dat (Data safety)
- Shromažďuje nebo sdílí data: **Ano**. Šifrování při přenosu: **Ano** (HTTPS). Lze požádat o smazání: **Ano**.

| Typ dat | Shromažďováno | Sdíleno | Účel | Povinné |
|---|---|---|---|---|
| Osobní údaje → Jméno | ano | ne | Funkce aplikace, správa účtu | ano |
| Osobní údaje → E-mailová adresa | ano | ne | Správa účtu | ano |
| Osobní údaje → ID uživatele | ano | ne | Funkce aplikace, správa účtu | ano |
| Zdraví a fitness → Zdravotní údaje (výživa) | ano | ne | Funkce aplikace | ne (jen se zapnutým Health) |
| Fotky | ne* | ne* | – | – |
| Aktivita v aplikaci → Jiné akce (potraviny, historie) | ano | ne | Funkce aplikace | ano |
| ID zařízení nebo jiná ID (FCM token) | ano | ne | Funkce aplikace (notifikace) | ne |

\* Fotky se zpracují v telefonu. S AI se posílají poskytovateli, kterého si uživatel sám nastaví vlastním klíčem, jako přenos na pokyn uživatele (u Googlu se to nepočítá jako sdílení). Kdyby ses chtěl jistit, uveď *Fotky → Sdíleno → Funkce aplikace, volitelné*.

Poskytovatelé služeb (Firebase) se nepočítají jako „sdílení“.

### Health Connect
Play Console → *Obsah aplikace → Zdravotní aplikace / Health Connect*:
- Oprávnění: **WRITE_NUTRITION** (jen zápis).
- Zdůvodnění: *„Uživatel, který si funkci zapne, si může do Health Connect zapsat nutriční hodnoty jídla, které podle aplikace snědl (své části jídla rozděleného v domácnosti). Aplikace z Health Connect nic nečte.“*
- Funkce v aplikaci: Nastavení → Zapisovat snězené do Health. Zásady ochrany soukromí ji popisují. Aplikace má i obrazovku s vysvětlením oprávnění (Health Connect rationale).

### Obsah vytvořený AI
Recepty a jídelníček generuje AI s klíčem uživatele. U odpovědi je tlačítko **Nahlásit nevhodnou odpověď** (otevře e-mail). To odpovídá zásadám Google Play pro obsah generovaný AI.

## 5. Deklarace (při vytváření aplikace)
- **Programové zásady pro vývojáře:** Gleba je splňuje. Má zásady ochrany soukromí, smazání účtu, žádné reklamy, popisky odpovídají funkcím a nahlašování AI odpovědí.
- **Play App Signing:** přijmout (doporučeno, nutné pro AAB). Pak přidat SHA klíče pro podepisování do Firebase (bod 2.3).
- **Exportní zákony USA:** Gleba používá jen standardní šifrování (HTTPS/TLS přes Android a Firebase), žádnou vlastní kryptografii, takže spadá pod výjimku. Zaškrtnout.

## 6. Před produkcí
Google u nových osobních vývojářských účtů vyžadoval před vydáním do produkce **uzavřený test s alespoň 12 testery po dobu 14 dní**. Přesný aktuální požadavek ukáže Play Console na hlavním panelu. Postup: Interní testování → Uzavřené testování (alfa) → Produkce.

## 7. Poznámky k vydání (Co je nového)
Texty jsou v `distribution/whatsnew/whatsnew-cs-CZ` a `whatsnew-en-US` (max. 500 znaků na jazyk). Workflow Release je při každém nahrání pošle do Play. Před releasem je aktualizuj.
