# Specifikace Gleba

## 1. Cíl
Mít přehled, co doma je a kdy to projde, s co nejmenším klikáním. Sdílet ho s domácností a vyhazovat méně jídla.

## 2. Uživatelé a domácnosti
- Přihlášení: **Google** a **e-mail + heslo** (Firebase Auth).
- Uživatel může být členem **více domácností** (doma, chata…), mezi nimi přepíná.
- Pozvání: **odkaz** nebo **krátký kód** s omezenou platností. Všichni členové mají **stejná práva**.

## 3. Evidence produktů
| Vlastnost | Popis |
|---|---|
| EAN | Naskenovaný kód (EAN-13/8, UPC, GS1 DataMatrix/QR). |
| Název, značka, foto, kategorie | Z databáze produktů, nebo zadané ručně. |
| Umístění | Lednice / mrazák / spíž / vlastní. **Nepovinné.** Aplikace ho sama navrhne podle kategorie (mražené ovoce do mrazáku, cibule do spíže). |
| Množství | Počet kusů nebo jednotka (ks, g, ml). Volitelná **částečná spotřeba** (ubrat 1 ze 6 jogurtů), lze vypnout. |
| Typ data | **Spotřebujte do** (use by) / **Minimální trvanlivost** (best before). Ovlivňuje důraznost upozornění. |
| Datum | Naskenované z GS1 kódu, vyfocené (OCR), nebo zadané ručně. Pokud chybí, navrhne se podle kategorie. |
| Otevřeno | Po otevření se trvanlivost zkrátí podle kategorie (mléko 3 dny). |
| Zamraženo | Prodlouží trvanlivost podle kategorie a uloží datum zamražení. |
| Cena | Volitelně (hlavně z účtenky), používá se ve statistikách. |

Další způsoby přidání:
- **Zbytky / domácí jídlo** bez EAN: název + datum uvaření, doba spotřeby se navrhne.
- **Hromadné skenování:** sken, sken, sken… data doplníš nakonec.
- **Účtenka** (fáze 2): fotka, AI rozpozná položky, uživatel je zkontroluje.
- **Učení:** znovu naskenovaný EAN předvyplní kategorii, umístění a obvyklou trvanlivost z historie domácnosti.

Ukončení položky: **Snězeno / Vyhozeno / Částečně**. Vše se zapisuje do historie kvůli statistikám.

## 4. Upozornění
- Každý uživatel má **vlastní** nastavení. Vše jde zapnout, vypnout a upravit.
- Pravidla se vrství: **výchozí → kategorie → konkrétní produkt** (nižší úroveň přebíjí vyšší).
  - výchozí: 2 dny předem; zvlášť pro „spotřebujte do“ a „minimální trvanlivost“
  - čas doručení, tichý režim
- **Ranní souhrn** v nastavenou hodinu (zap/vyp).
- **Tlačítka v upozornění:** Snězeno / Vyhozeno / Odložit.
- **Posílá je server** (Cloud Functions každých 15 minut, FCM), jen do telefonů s Android aplikací. Čas pravidla se dodrží s přesností do 15 minut.
- Prošlé věci: připomínat **každý den** (výchozí), nebo jen jednou.
- **Nerušit** (globální okno, např. 22:00–7:00); upozornění v té době počkají na jeho konec.
- **Co dělají ostatní** (volba, výchozí vypnutá): souhrn „Jana: přidáno 6, snědeno 2“.

## 5. Obrazovky a vzhled
**Hlavní obrazovka = lednice s mrazákem pod sebou.**
- Horní dveře „Lednice“, dole šuplíky „Mrazák“, volitelně boční skříňka „Spíž“.
- Klepnutím se dveře otevřou (3D animace) a ukážou police s produkty.
- Barvy čerstvosti: zelená, oranžová (blíží se), červená (dnes/prošlé), šedá (prošlé best before).
- Přepínač na **seznam „Spotřebuj nejdřív“** seřazený podle naléhavosti.

**Zábavné animace (lze vypnout):**
- otevření dveří s chladným „výdechem“ páry, námraza na mrazáku
- naskenovaný produkt vletí do lednice na polici
- snězeno: spokojené mlasknutí a odlesk; vyhozeno: smutný koš
- prázdná lednice: světlo bliká a cvrčci 🦗

Material 3, světlý i tmavý režim, CZ/EN.

## 6. Práce bez internetu
Firestore offline cache: skenování a úpravy fungují bez signálu a synchronizují se později. Databáze produktů se ukládá do mezipaměti.

## 7. AI funkce (fáze 2)
- **Poskytovatelé:** Google Gemini, OpenAI (ChatGPT), Anthropic (Claude).
- **Vlastní API klíč, dva režimy (uživatel volí):**
  1. *Jen v zařízení*: klíč v šifrovaném úložišti telefonu, volání přímo z aplikace.
  2. *Sdílený pro domácnost*: klíč uložen šifrovaně na serveru, volání přes Cloud Function (Blaze). Klíč se nikdy nevrací do klienta.
- **Použití:**
  - čtení **účtenek** (položky, množství, ceny)
  - **datum spotřeby z fotky**, když nestačí OCR v telefonu
  - **recepty** z vybraných surovin (prioritně z těch, co brzy projdou)
- **Bez klíče:** tlačítko „Zkopírovat zadání pro AI“ připraví text se surovinami do schránky.
- **Žádná vestavěná (námi placená) AI.** Vždy se používají klíče uživatelů. Poskytovatele lze zvolit zvlášť pro každou funkci (např. účtenky Gemini, recepty Claude).
- Blaze slouží jen pro upozornění (FCM, Cloud Functions) a sdílený klíč domácnosti; v projektu je nastavený rozpočtový limit 250 Kč/měsíc.

## 8. Další funkce
| Funkce | Fáze |
|---|---|
| Nákupní seznam (sdílený), přidání po snězení jedním klepnutím, hlídání minimálních zásob | 2 |
| Widget na plochu „brzy projde“ | 2 |
| Statistiky: vyhozeno (ks, Kč, kategorie, trend), snězeno včas, kdo kolik naskenoval | 2 |
| Alergeny, Nutri-Score, foto produktu z Open Food Facts | 1 |
| **Inventurní režim** (viz níže) | 2 |
| Health Connect (a přes něj Samsung Health): zápis výživových hodnot snězeného, **velmi volitelné** | 3 |

### Inventurní režim
Řeší, že někdo vezme jogurt a nic neoznačí.
- **Rychlá inventura:** karty jako v seznamce. Doprava = pořád tam, doleva = pryč, nahoru = část. Celá lednice za 30 s.
- **Připomínka inventury** (např. v neděli večer) jako upozornění.
- **Chytré dotazy:** u věcí prošlých o X dní se aplikace sama zeptá „Je to ještě v lednici?“.
- **Odhad spotřeby:** z historie se naučí, že „mléko vydrží 4 dny“, a nabídne jeho automatické odepsání.
- *Do budoucna:* NFC štítek na lednici otevře rychlou inventuru.

## 9. Mimo rozsah (zatím)
iOS nativní aplikace (iOS uživatelé použijí PWA), chytré lednice s kamerou, nákupy online.
