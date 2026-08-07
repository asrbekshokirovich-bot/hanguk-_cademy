# Hanguk Academy — Onlayn ta'lim

Flutter ilovasi: **Windows desktop + Android + iOS + web** (bitta kod bazasi).
Dizayn manbasi — `Hanguk Academy Online` handoff bandli: to'q "liquid-glass"
desktop ko'rinishi, suzuvchi buyruq doki va yagona **Vibrant Lime** urg'u.

Bu ilova mavjud talaba ilovasidan (`hanguk-uz/hanguk_app`) **alohida** turadi —
u universitetga hujjat topshirish uchun, bu esa onlayn darslar uchun.

## Ekranlar

| Yo'l | Ekran | Holati |
|---|---|---|
| `/` | Asosiy — jonli banner, 4 ta statistika, bugungi jadval, so'nggi yozuvlar | to'liq |
| `/live` | Jonli dars — sahna, ishtirokchilar, suhbat, boshqaruv paneli | UI to'liq, media ulanmagan |
| `/recordings` | Yozuvlar — filtr chiplari + karta panjarasi | to'liq |
| `/recordings/:id` | Dars tafsiloti — pleyer, materiallar, test, uy vazifasi | pleyer o'rin egallovchi |
| `/schedule` | Jadval — haftalik jadval, avto-yozuv tugmasi (xodimlar uchun) | to'liq |

### Yuqori o'ng burchakdagi boshqaruvlar

- **🔍 Qidiruv** — darslar va yozuvlar bo'ylab, nomi, kategoriyasi yoki
  o'qituvchi ismi bo'yicha. Natijaga bosilsa o'sha sahifaga o'tadi.
- **🔔 Bildirishnomalar** — `ol_notifications` jadvalidan. O'qilmaganlar
  qizil nuqta bilan sanaladi, "O'qildi" bittada hammasini belgilaydi.
- **Avatar** — profil menyusi: ism, rol, daraja, ma'lumot manbai (Supabase
  yoki demo) va chiqish tugmasi.

Telefonda qidiruv va qo'ng'iroq yuqoridagi sarlavhada turadi.

### Hozircha ulanmagan

Bular ataylab qoldirilgan, keyingi bosqich:

- **Video/audio.** Jonli xonada kamera, mikrofon yoki masofaviy oqim yo'q.
  Ekranda buni aytuvchi ogohlantirish bor — ishlamaydigan tugmalar
  ko'rsatilmaydi. LiveKit uchun `ol_lessons.live_room` ustuni tayyor.
- **Yozuv pleyeri.** `/recordings/:id` da skrubber va vaqtlar haqiqiy
  progressdan chiziladi, lekin video dekodlanmaydi.
- **Ishtirokchilar va suhbat** jonli xonada `DemoData` dan olinadi.
- **Test / uy vazifasi modullari** — kartalar bor, oynalar yo'q.
- **Chiqish** — kirish (login) ekrani hali yo'q, shuning uchun profil
  menyusidagi "Chiqish" hozircha xabar ko'rsatadi.

## Ishga tushirish

```bash
flutter pub get
flutter run -d windows
```

Bayroqsiz ishlaydi — `lib/core/env.dart` loyihaning o'z Supabase manzilini va
publishable kalitini ichida saqlaydi. Bu kalit binarda yuborilishi uchun
mo'ljallangan: uning o'zida hech qanday huquq yo'q, har bir so'rov baribir
migratsiyadagi RLS qoidalaridan o'tadi. **`service_role` va `sb_secret_…`
kalitlarini hech qachon bu yerga yozmang.**

Boshqa loyihaga yo'naltirish:

```bash
flutter run -d windows \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Bo'sh URL berish demo rejimni yoqadi — `demo_data.dart` dagi fiksturalar
ishlatiladi, tarmoqqa umuman chiqmaydi:

```bash
flutter run -d windows --dart-define=SUPABASE_URL=
```

Profil menyusidagi "Ma'lumot manbai" qatori qaysi rejimda ekaningizni
ko'rsatadi.

Boshqa platformalar: `-d android`, `-d ios`, `-d chrome`, `-d linux`.

## Ma'lumotlar bazasi

`supabase/migrations/20260807120000_online_lessons.sql` — barcha jadvallar
`ol_` prefiksi bilan, shuning uchun mavjud Supabase loyihasi bilan bir joyda
yashay oladi.

Qo'llash: Supabase'da **SQL Editor** ni ochib, `.sql` faylning butun
mazmunini qo'ying va **Run** bosing. Yoki CLI bilan `supabase db push`.

Rollar `ol_profiles.role` dan keladi (`student` / `teacher` / `admin`) va
har bir RLS siyosati shunga tayanadi. Talaba faqat o'z progressini va o'z
davomatini yoza oladi; darslar, yozuvlar va jadvalni faqat xodimlar
o'zgartiradi.

## Layout

Dizayn 1440×920 desktop uchun chizilgan, lekin bir xil kod telefonga ham
chiqadi. `lib/design_system/layout.dart` uchta darajani belgilaydi:

- `compact` (<760px) — suzuvchi dok o'rniga pastki navigatsiya; bitta ustun.
- `medium` (<1180px) — dok bor, panjaralar ikki ustunga tushadi.
- `expanded` — dizayndagi ko'rinish.

## Testlar

```bash
flutter test                              # vidjet testlari
flutter test test/golden                  # ekranlarni golden bilan solishtirish
flutter test --update-goldens test/golden # goldenlarni yangilash
```

Golden testlar beshta ekranni 1440×920 da dasturiy rasterizatsiya bilan
chizadi — desktop layoutini displeysiz CI da tekshirishning yagona yo'li.
Goldenlarda ikonkalar bo'sh kvadrat bo'lib chiqadi: test muhiti Material
Icons shriftini yuklamaydi. Bu ilovaga taalluqli emas, faqat rasmda shunday.
