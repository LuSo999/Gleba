# Zdroje dat

## Informace o produktu podle EAN
Pořadí dotazů:
1. **Lokální mezipaměť** v zařízení (funguje offline).
2. **Databáze domácnosti** `households/{id}/products/{ean}`: co jsme už jednou zadali, včetně naší kategorie, umístění a obvyklé trvanlivosti.
3. **Sdílená databáze Gleba** `products/{ean}`: co zadali ostatní uživatelé (bez osobních údajů) + průměrná trvanlivost z dat na obalech. Název cizí položky nejde přepsat; interní kódy obchodů (20–29) se nesdílí.
4. **[Open Food Facts](https://world.openfoodfacts.org)**: otevřená a bezplatná databáze potravin (licence ODbL). Obsahuje název, značku, foto, kategorie, alergeny a Nutri-Score. České pokrytí je slušné u značkových výrobků, slabší u privátních značek obchodů.
5. **Ručně / AI:** pokud nic nenajdeme, uživatel vyfotí obal a vyplní název (nebo ho přečte AI).

Další zdroje jsme zvažovali a zamítli: UPCitemdb a EAN-Search jsou placené nebo zaměřené na USA. GS1 (Verified by GS1) vrací jen vlastníka kódu, ne užitečné údaje o potravině.

> Pozn.: Prefix EAN (např. 859 = ČR) určuje zemi, kde výrobce kód zaregistroval, ne původ zboží.
> Kódy začínající 20–29 jsou interní kódy obchodu (vážené zboží, pečivo). Nelze je dohledat, jen je zapamatovat v rámci domácnosti.

## Je v EAN uložena trvanlivost?
**Klasický EAN-13 ne.** Obsahuje jen identifikaci produktu.

**Ale:** nové 2D kódy (**GS1 DataMatrix**, **GS1 QR / Digital Link**) a **GS1-128** mohou nést přímo:
- AI **(17)**: datum spotřeby (use by / expiry)
- AI **(15)**: datum minimální trvanlivosti (best before)
- AI **(10)**: šarže, **(3103)**: hmotnost

GS1 tlačí iniciativu „Sunrise 2027“, kdy pokladny přejdou na 2D kódy, takže se objevují stále častěji (maso, mléčné výrobky, čerstvé zboží). **Gleba tyto kódy bude parsovat a datum vyplní automaticky.**

## Výchozí trvanlivost podle kategorie
- Neexistuje závazná norma „kategorie → trvanlivost“. Datum stanovuje **výrobce**. Obchody ho jen dodržují, vlastní trvanlivost podle kategorie nepoužívají (kromě vlastní výroby, pečiva a lahůdek).
- Výchozí hodnoty tedy bereme z:
  1. **USDA FoodKeeper**: veřejná data (public domain) s dobami skladování ~400 druhů potravin v lednici, mrazáku a spíži, **i po otevření**. Převedeme je na naše kategorie a přeložíme do CZ.
  2. **Doporučení pro skladování** (SZPI, výrobci): doplnění pro české specifické potraviny.
  3. **Statistiky z dat Gleby**: medián (datum spotřeby − den naskenování) pro daný EAN nebo kategorii. Čím víc dat, tím přesnější návrh. Ten má přednost před obecnou tabulkou.
- Tabulka je v aplikaci (assets) a lze ji upravit per domácnost.

## Fotka data spotřeby
1. **ML Kit Text Recognition** v zařízení (zdarma, offline) + parser českých i zahraničních formátů (`12.03.26`, `12/03/2026`, `2026-03-12`, `12 MAR 26`, `03/2026`, „spotřebujte do: viz víčko“…).
2. Pokud se to nepovede a uživatel má API klíč, pošle se ořez fotky AI.
3. Uživatel datum vždy potvrdí.
