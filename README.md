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
| `/login` | Kirish — login + parol | to'liq |
| `/change-password` | Birinchi kirishda majburiy parol almashtirish | to'liq |
| `/admin/users` | Talabalar — hisoblarni yaratish, parol tiklash, rol | to'liq (admin) |

### Hisoblar va kirish

Ochiq ro'yxatdan o'tish **yo'q**. Har bir talaba va o'qituvchi hisobini
administrator yaratadi va login bilan parolni qo'lga beradi.

- **Kirish** login bilan (`aziza.k`), email bilan emas. Ko'p talabada
  ishlatiladigan email yo'q. Ichkarida login `aziza.k@users.hanguk-academy.uz`
  ko'rinishiga aylantiriladi — bu domenga hech qachon xat yuborilmaydi.
  Aylantirish ilovaning o'zida hisoblanadi, bazadan **so'ralmaydi**: "bunday
  login bormi?" deb javob beradigan ochiq so'rov butun ro'yxatni birma-bir
  yig'ib olishga imkon berardi.
- **Parol tizim tomonidan yaratiladi** va bir marta ko'rsatiladi. Admin uni
  nusxalab talabaga beradi.
- **Birinchi kirishda parol almashtiriladi.** Admin ko'rgan parol hisobning
  haqiqiy paroli bo'lib qolmaydi — router boshqa hamma ekranni yopib turadi.
- Rollar: `student` / `teacher` / `admin`. Jadvaldagi tahrirlash va avto-yozuv
  o'qituvchi va adminda; hisoblar paneli faqat adminda.

Hisob yaratish, o'chirish va parol tiklash `supabase/functions/admin-users`
Edge Function orqali bajariladi. Sabab: bu amallar `service_role` kalitini
talab qiladi, u esa hech qachon ilova ichida bo'lmasligi kerak — binarni
ochgan odam bazaning egasiga aylanardi. Funksiya har bir so'rovda chaqiruvchi
haqiqatan admin ekanini tekshiradi.

Joylashtirish:

```bash
supabase functions deploy admin-users
```

yoki Supabase paneli → Edge Functions → yangi funksiya yaratib, faylni
qo'yish. Sozlanadigan maxfiy qiymat yo'q — `SUPABASE_URL` va
`SUPABASE_SERVICE_ROLE_KEY` platformaning o'zi tomonidan beriladi.

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
- **Hisobni vaqtincha bloklash** — hozircha faqat o'chirish bor.
- **Parolni o'zi tiklash** — talaba parolni unutsa, adminga murojaat qiladi.
  Emailsiz hisobga avtomatik tiklash yuborib bo'lmaydi.

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
