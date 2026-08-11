# Microsoft Store — nashr qilish qo'llanmasi

Windows versiyasini do'kon orqali tarqatish. Zip yuborishdan farqi: odam
Store'dan bir bosishda o'rnatadi, yangilanishlar o'zi keladi, va
"Windows protected your PC" ogohlantirishi chiqmaydi.

---

## 1. Hisob ochish

https://partner.microsoft.com/dashboard → **Windows & Xbox** dasturi.

Bir martalik to'lov: **$19** (jismoniy shaxs). Kredit karta kerak.
Shaxsni tasdiqlash bir necha kun ketishi mumkin.

---

## 2. Ilova nomini band qilish

Partner Center → **Create a new app** → nom: `Hanguk Academy`

Nom band qilingach, **Product management → Product identity** sahifasida
uchta qiymat paydo bo'ladi:

| Partner Center'dagi nomi | Namuna |
|---|---|
| Package/Identity/Name | `12345Hanguk.HangukAcademy` |
| Package/Identity/Publisher | `CN=A1B2C3D4-5E6F-...` |
| Package/Properties/PublisherDisplayName | `Asrbek Shokirovich` |

📌 **Shu uchtasini menga yuboring** — `pubspec.yaml` dagi `msix_config`
ga qo'yaman. Ular hisobingizga harfma-harf mos kelmasa, do'kon paketni
rad etadi.

---

## 3. `.msix` yig'ish

Windows kompyuterda, Visual Studio o'rnatilgan bo'lishi kerak (Windows
versiyasini yig'ish uchun ham o'sha kerak edi):

```
cd /d C:\hanguk
git pull origin claude/flutter-desktop-android-ios-00ck9r
flutter build windows --release
dart run msix:create
```

Natija: `build\windows\x64\runner\Release\hanguk_online.msix`

Ochish uchun:

```
explorer build\windows\x64\runner\Release
```

---

## 4. Do'konga yuklash

Partner Center → ilovangiz → **Packages** → `.msix` faylni sudrab tashlaysiz.

Keyingi bo'limlar (Play'dagiga o'xshash):

| Bo'lim | Nima yoziladi |
|---|---|
| Pricing and availability | **Free**, mamlakat: O'zbekiston (yoki hammasi) |
| Age ratings | So'rovnoma — javoblar `docs/play-store.md` ning 6-bo'limidagidek |
| Store listing | Nom, tavsif, skrinshotlar — matnlar `docs/play-store.md` 4-bo'limida |
| Privacy policy URL | `https://hanguk-cademy.vercel.app/privacy.html` |
| Properties → Category | **Education** |

Tekshiruv odatda **1–3 kun**.

⚠️ Store tekshiruvchisi ham ilovaga kira olishi kerak. Submission
izohlariga (**Notes for certification**) Play uchun ishlatgan hisobni
yozing:

```
Bu yopiq tizim, ochiq ro'yxatdan o'tish yo'q.
Login: play.review
Parol: <parol>
```

---

## 5. Skrinshotlar

Do'kondagi skrinshotlar kamida **1366×768** bo'lishi kerak. `docs/play/`
dagilar telefon o'lchamida (1080×2340) — Store uchun yaramaydi.

Kompyuter versiyasini ochib, **Win + Shift + S** bilan yoki **PrtScn**
bosib ekran rasmini olasiz: Boshqaruv, Talabalar, Jadval, To'lovlar
ekranlaridan 4 tacha yetadi.

---

## 6. Nimaga e'tibor berish kerak

- **Versiya.** Har yangi yuklashda `pubspec.yaml` dagi `msix_version` ni
  oshirish kerak (`1.0.1.0` → `1.0.2.0`). Do'kon takrorlangan versiyani
  qabul qilmaydi — Play'dagi kabi.
- **Imzo.** Do'kon paketni o'zi imzolaydi, sizga sertifikat sotib olish
  shart emas (`store: true` sozlamasi shuning uchun turibdi).
- **Ruxsatlar.** Paket faqat `internetClient` so'raydi — ilova serverga
  ulanadi, kompyuterda boshqa hech narsaga tegmaydi.
