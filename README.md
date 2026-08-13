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

### Uchta panel

Navigatsiya hisobning roliga qarab tanlanadi. Rol almashtirgich **yo'q** —
prototipdagi chip dizaynerga uchta rolni ko'rsatish uchun; mahsulotda u yo
yolg'on bo'lardi (talaba admin bo'la olmaydi), yo teshik (agar ishlaganda).

| Rol | Ekranlar |
|---|---|
| **Talaba** | `/` Asosiy · `/live` Jonli · `/recordings` Yozuvlar · `/schedule` Jadval |
| **O'qituvchi** | `/teacher` Asosiy · `/live` Darsim · `/teacher/students` Talabalarim · `/teacher/grading` Baholash · `/recordings` Yozuvlar |
| **Admin** | `/admin` Boshqaruv · `/admin/students` Talabalar · `/admin/teachers` O'qituvchilar · `/schedule` Jadval · `/admin/finance` Moliya |

Yopiq marshrutlar routerda ham tekshiriladi — dokdan yashirish himoya emas.

### Darsning holati

`scheduled` → `live` → `ended`. Ikkala o'tishni ham xodim ilova ichidan
bajaradi:

- **Darsni boshlash** — o'qituvchi panelidagi "Bugungi darslarim" ro'yxatida,
  rejalashtirilgan dars yonida. Yozuv qaytgach jonli xonaga o'tkazadi, oldin
  emas — aks holda xona hali yangilanmagan qatorni o'qib "jonli dars yo'q"
  deb turardi.
- **Darsni tugatish** — jonli xonaning boshqaruv panelida. Tasdiq so'raydi:
  yonidagi "Chiqish" butunlay boshqa ish qiladi, va tugatishning orqaga
  qaytarish tugmasi yo'q.

Ikkalasi ham **o'qituvchining o'ziga bog'langan**:

- `/live` — "hozir efirda nima bor", talabaning va dokning eshigi.
  `/live/:id` bitta darsni nomlaydi; o'qituvchi o'z xonasiga shu yo'l bilan
  kiradi. Ikki dars bir vaqtda ketayotganda `/live` faqat taxmin qila oladi,
  va taxmini boshqa o'qituvchining xonasi bo'lib chiqardi.
- Tugatish tugmasi darsni **o'zi olib borayotgan** o'qituvchida
  (`ol_lessons.teacher_id` = mening `ol_teachers.id` im) va adminda
  ko'rinadi. Admin uchun ochiq qoldirilgan: o'qituvchi noutbukini yopib
  ketgan xona kimdir tomonidan tozalanishi kerak.
- "Bugungi darslarim" ham faqat o'z darslarini ko'rsatadi — ilgari butun
  maktabning kunini chizardi. Adminda o'z darsi yo'q, shuning uchun u to'liq
  kunni ko'radi.

Kim yoza olishini baribir `ol_lessons_write` siyosati hal qiladi; tugmani
yashirish tekshiruv emas.

Holat ko'rinmas joylarga ham ta'sir qiladi — dokdagi jonli nuqta, talabaning
asosiy sahifasidagi banner, va 30 kunlik o'rtacha davomat: u faqat `ended`
darslarni sanaydi, shuning uchun tugatilmagan dars hisobga umuman kirmaydi.

### Pul

Summalar **butun so'mda, `bigint`** saqlanadi. Kasrli tiyin amalda yo'q, va
5 000 000 UZS ni `double` da saqlash bugun to'g'ri ko'rinadi-yu, birinchi
bo'lishda xato beradi.

Moliya bo'limi — **daftar, to'lov tizimi emas**. Pul naqd yoki bank orqali
keladi, kimdir uni shu yerda qayd etadi; ilova mablag' harakatlantirmaydi.
"Tasdiqlash" holat bilan birga sanani ham yozadi — sanasiz tasdiq bank
ko'chirmasi bilan solishtirilmaydi.

Kechikkan holati **hisoblab chiqariladi**, saqlanmaydi: faqat fon vazifasi
ishlaganda to'g'ri bo'ladigan ustun — bu vazifa ishlamagan paytda noto'g'ri
bo'ladigan ustun.

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

Hisob yaratish, o'chirish va parol tiklash **bazadagi `SECURITY DEFINER`
funksiyalar** orqali bajariladi (`20260807170000_admin_user_rpc.sql`). Bu
amallar oshirilgan huquq talab qiladi, u esa hech qachon ilova ichida
bo'lmasligi kerak — binarni ochgan odam bazaning egasiga aylanardi. Har bir
funksiyaning birinchi satri chaqiruvchi haqiqatan admin ekanini tekshiradi.

Kelishuv ochiq aytiladi: bu `auth.users` ga to'g'ridan-to'g'ri yozadi, buni
Supabase tavsiya qilmaydi — o'sha sxema GoTrue niki va versiyalar orasida
o'zgarishi mumkin. Xatolik ko'rinadigan bo'ladi (yangi majburiy ustun paydo
bo'lsa funksiya xato beradi, buzuq hisob yaratmaydi), lekin GoTrue yangilangach
qayta sinash kerak.

`supabase/functions/admin-users` — xuddi shu uch ishni bajaradigan Edge
Function, repoda qoldirilgan. U odatdagi yo'l va afzalroq; agar joylashtira
olsangiz, `AdminRepository` ni unga qaytarib, bu funksiyalarni o'chirsa
bo'ladi.

```bash
supabase functions deploy admin-users
```

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
