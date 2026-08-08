# Google Play — nashr qilish qo'llanmasi

Hanguk Academy — Onlayn ta'lim ilovasini Play Market'ga chiqarish uchun
hamma narsa shu faylda. Tartib bilan boring.

---

## 0. Bir marta hal qilinadigan, keyin o'zgarmaydigan narsa

**Ilova identifikatori (package name):** `uz.hanguk.hanguk_online`

Bu Play'dagi manzilingiz bo'ladi:
`play.google.com/store/apps/details?id=uz.hanguk.hanguk_online`

⚠️ **Birinchi yuklashdan keyin buni o'zgartirib bo'lmaydi.** O'zgartirish
faqat yangi ilova ochish orqali — eski o'rnatgan foydalanuvchilar yangisini
olmaydi. Boshqacha nom xohlasangiz (masalan `uz.hangukacademy.app`), **hozir**
ayting.

---

## 1. Imzolash kaliti (keystore)

Kalit — ilovaning Play'dagi shaxsi. Yo'qotsangiz, ilovani yangilay olmaysiz.
Boshqaga tarqalsa, sizning nomingizdan ilova imzolashi mumkin.

### Kalitni yaratish

Kompyuterda Java bo'lishi kerak. Yo'q bo'lsa: https://adoptium.net (Temurin 17).

CMD'da, loyiha papkasida:

```
keytool -genkeypair -v -keystore hanguk-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

So'raladi:
- **parol** — o'ylab toping, yozib qo'ying (ikki marta so'raydi)
- **ism, tashkilot, shahar, davlat** — Asrbek / Hanguk Academy / Tashkent / UZ
- oxirida `yes` deb tasdiqlang

Natija: `hanguk-upload.jks` fayli. **Uni GitHub'ga qo'ymang** — `.gitignore`
allaqachon to'sib qo'yadi.

📌 **Nusxasini xavfsiz joyda saqlang** (Google Drive, tashqi disk). Parolini
ham. Bu ikkisisiz ilova abadiy yangilanmaydi.

### Kalitni GitHub'ga (maxfiy sifatida) qo'yish

Kalit faylni matnga o'girish kerak. CMD'da:

```
certutil -encode hanguk-upload.jks keystore-base64.txt
```

`keystore-base64.txt` ni Notepad'da oching. Birinchi va oxirgi qatorlarni
(`-----BEGIN...` va `-----END...`) **o'chiring**, qolganini nusxalang.

Keyin GitHub'da: repozitoriya → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret**. To'rtta maxfiy qo'shing:

| Nomi | Qiymati |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | yuqorida nusxalagan matn |
| `ANDROID_STORE_PASSWORD` | keystore paroli |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | keystore paroli (odatda bir xil) |

---

## 2. Ilova faylini (.aab) yig'ish

Kompyuteringizga Android Studio o'rnatish shart emas — GitHub yig'ib beradi.

1. GitHub'da repozitoriya → **Actions** bo'limi
2. Chapda **Android release bundle**
3. O'ngda **Run workflow** → **Run workflow**
4. 5–10 daqiqa kutasiz
5. Tugagach, o'sha ishni oching → pastda **Artifacts** → **hanguk-academy-aab**
   ni yuklab oling

Ichida `app-release.aab` — Play'ga yuklanadigan fayl shu.

**Har safar yangi versiya chiqarganda** `pubspec.yaml` dagi `version: 1.0.0+1`
ni oshirish kerak: `1.0.1+2`, `1.1.0+3` va hokazo. Play `+` dan keyingi sonni
takrorlashga yo'l qo'ymaydi. Buni menga ayting — o'zim oshirib qo'yaman.

---

## 3. Play Console

### Hisob ochish

https://play.google.com/console — **bir martalik $25** to'lov, kredit karta
kerak. Shaxs sifatida ochsangiz, pasport ma'lumotlari so'raladi va
tasdiqlash bir necha kun ketishi mumkin.

### Ilova yaratish

**Create app** → quyidagilarni kiriting:

| Maydon | Qiymat |
|---|---|
| App name | `Hanguk Academy` |
| Default language | `O'zbek – uz-UZ` |
| App or game | App |
| Free or paid | **Free** |

---

## 4. Do'kon sahifasi matnlari

Nusxalab qo'yaverasiz.

### Ilova nomi (30 belgigacha)
```
Hanguk Academy
```

### Qisqa tavsif (80 belgigacha)
```
Koreys tili onlayn darslari: jadval, davomat, baholar va to'lovlar bir joyda.
```

### To'liq tavsif (4000 belgigacha)
```
Hanguk Academy — koreys tili o'quv markazining rasmiy ilovasi.

Ilova markazda o'qiydigan talabalar, dars beradigan o'qituvchilar va markaz
xodimlari uchun mo'ljallangan. Hisobni markaz ma'muriyati ochib beradi —
ilovada ochiq ro'yxatdan o'tish yo'q.

TALABA UCHUN
• Haftalik dars jadvali — qachon, qaysi dars, qaysi o'qituvchi
• Jonli darsga kirish
• O'tkazib yuborilgan darslarning yozuvlari
• Shaxsiy davomat va baholar
• To'lov holati

O'QITUVCHI UCHUN
• Bugungi darslar va guruhlar
• O'z talabalari ro'yxati, davomat va o'zlashtirish
• Uyga vazifalarni tekshirish va baholash

MARKAZ MA'MURIYATI UCHUN
• Talaba va o'qituvchi hisoblarini ochish
• Guruhlar tuzish, talabani guruhga biriktirish
• Dars jadvalini yuritish
• Oylik to'lovlarni qabul qilish va qayd etish
• Umumiy ko'rsatkichlar: davomat, yuklama, moliya

Ilovada reklama yo'q. Ma'lumotlar himoyalangan serverda saqlanadi va har bir
foydalanuvchi faqat o'ziga tegishli ma'lumotni ko'radi.

Ilovadan foydalanish uchun Hanguk Academy o'quv markazida o'qiyotgan yoki
ishlayotgan bo'lishingiz va ma'muriyatdan login olishingiz kerak.
```

### Maxfiylik siyosati havolasi
```
https://hanguk-cademy.vercel.app/privacy.html
```
(o'z domeningiz bo'lgach — o'shanikini qo'yasiz)

---

## 5. Grafik materiallar

| Nima | O'lchami | Holat |
|---|---|---|
| Ilova ikonkasi | 512×512 PNG | ✅ `docs/play/icon-512.png` |
| Feature graphic | 1024×500 PNG | ✅ `docs/play/feature-graphic.png` |
| Telefon skrinshotlari | kamida 2 ta | ✅ `docs/play/screenshots/` |

Skrinshotlar ilovaning haqiqiy ekranlaridan olingan. Yangi ekran qo'shilsa
qayta yaratiladi — menga ayting.

---

## 6. Content rating (yosh reytingi)

So'rovnomani to'ldirasiz. To'g'ri javoblar:

| Savol | Javob |
|---|---|
| Kategoriya | **Education / Ta'lim** |
| Zo'ravonlik, qo'rqinchli sahnalar | Yo'q |
| Jinsiy mazmun | Yo'q |
| Haqoratli til | Yo'q |
| Giyohvandlik, alkogol, tamaki | Yo'q |
| Qimor | Yo'q |
| Foydalanuvchilar o'zaro muloqot qila oladimi | **Yo'q** (chat yo'q) |
| Joylashuv ulashiladimi | Yo'q |
| Shaxsiy ma'lumot yig'iladimi | **Ha** (ism, login) |
| Ilovada xarid bormi | Yo'q |

Natija: odatda **3+** yoki **Everyone**.

---

## 7. Data safety (ma'lumotlar xavfsizligi)

Bu bo'lim eng ko'p xato qilinadigan joy. Aniq javoblar:

**Ilova ma'lumot yig'adimi yoki ulashadimi?** → **Ha, yig'adi**
**Ma'lumot uchinchi tomonlarga ulashiladimi?** → **Yo'q**
**Uzatishda shifrlanadimi?** → **Ha**
**Foydalanuvchi ma'lumotini o'chirishni so'ray oladimi?** → **Ha**

Yig'iladigan turlar:

| Tur | Yig'iladi | Ulashiladi | Majburiy | Maqsad |
|---|---|---|---|---|
| Name (ism) | Ha | Yo'q | Ha | App functionality, Account management |
| User IDs (login) | Ha | Yo'q | Ha | App functionality, Account management |
| Phone number | Ha | Yo'q | Yo'q | App functionality |
| Other user-generated content¹ | Ha | Yo'q | Yo'q | App functionality |

¹ davomat, baholar, to'lov yozuvlari.

**Belgilamang:** Location, Contacts, Photos, Files, Financial info (bank
kartasi), Health, Messages, App activity, Device IDs, Crash logs.

> ⚠️ "Financial info" ni belgilamang — ilova pul o'tkazmaydi va karta
> ma'lumotini yig'maydi. Faqat "shu talaba shuncha to'ladi" degan yozuv bor,
> u — o'quv yozuvi.

---

## 8. Kirish uchun ma'lumot (App access)

Play tekshiruvchisi ilovaga kira olishi **shart**, aks holda rad etiladi.
Ochiq ro'yxatdan o'tish yo'qligi uchun quyidagini kiriting:

**All or some functionality is restricted** → **Ha**

Instruction:
```
Bu yopiq tizim — ro'yxatdan o'tish yo'q, hisobni markaz ma'muriyati ochadi.
Tekshirish uchun quyidagi hisobdan foydalaning:

Login: (demo hisob logini)
Parol: (demo hisob paroli)

Ilova o'zbek tilida. Kirgandan keyin pastdagi menyudan bo'limlarni ko'rish
mumkin.
```

📌 **Buning uchun alohida demo hisob oching** va parolini o'zgartirishga
majburlamaydigan qilib qoldiring. Mavjud `demo` hisobini ishlatsangiz ham
bo'ladi — lekin parolini biling va menga aytmang, o'zingiz kiriting.

---

## 9. Birinchi chiqarish

1. **Testing → Internal testing** dan boshlang — o'zingiz va bir necha kishi
   sinab ko'radi, tekshiruv tez o'tadi
2. Ishonch hosil qilgach → **Production**
3. Birinchi tekshiruv **3–7 kun** ketishi mumkin. Keyingilari tezroq.

### Tez-tez uchraydigan rad javoblari

| Sabab | Oldini olish |
|---|---|
| Tekshiruvchi kira olmadi | 8-bo'limdagi demo hisob to'g'ri ishlashini tekshiring |
| Maxfiylik siyosati ochilmadi | Havolani brauzerda ochib ko'ring |
| Data safety noto'g'ri | 7-bo'limdagi jadvalga qat'iy amal qiling |
| Ilova ochilib yopilib qoldi | Internet ruxsati — bu tuzatilgan, lekin AAB'ni telefonda sinab ko'ring |

---

## 10. Chiqarishdan oldin oxirgi tekshiruv

- [ ] `.aab` fayl GitHub Actions'dan yuklab olindi
- [ ] Fayl haqiqiy telefonda sinab ko'rildi (internet ishlayaptimi, kirish ishlayaptimi)
- [ ] Keystore va parolining nusxasi xavfsiz joyda
- [ ] Maxfiylik siyosati havolasi brauzerda ochilyapti
- [ ] Demo hisob ishlayapti va paroli o'zgartirishni talab qilmaydi
- [ ] Skrinshotlar va grafikalar yuklandi
