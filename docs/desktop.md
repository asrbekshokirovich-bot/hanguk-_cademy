# Kompyuter (Windows) versiyasi

Ilova telefon uchun ham, brauzer uchun ham, kompyuter uchun ham bitta koddan
yig'iladi. Windows versiyasi — alohida `.exe` dastur; brauzer kerak emas,
internet esa kerak (ma'lumotlar serverdan keladi).

---

## 1. Yig'ishning ikki yo'li

### A. GitHub yig'ib beradi (tavsiya etiladi)

Kompyuteringizga hech narsa o'rnatish shart emas.

1. GitHub'da repozitoriya → **Actions**
2. Chapda **Windows desktop build**
3. O'ngda **Run workflow** → **Run workflow**
4. 5–10 daqiqa kutasiz
5. Tugagach, o'sha ishni oching → pastda **Artifacts** →
   **hanguk-academy-windows** ni yuklab olasiz

Ichida `hanguk-academy-windows.zip`. Uni papkaga chiqarib (Extract),
`hanguk_online.exe` ni ishga tushirasiz.

⚠️ Zip ichidagi barcha fayllar kerak — `.exe` ni yolg'iz ko'chirsangiz
ishlamaydi. Yonidagi `flutter_windows.dll` va `data` papkasi ham o'sha yerda
turishi shart.

### B. O'z kompyuteringizda yig'ish

Buning uchun **Visual Studio** kerak (hozir `flutter doctor` uni topmayapti).
Bepul, lekin bir necha gigabayt:

1. https://visualstudio.microsoft.com/downloads/ → **Visual Studio Community**
2. O'rnatishda **"Desktop development with C++"** bandini belgilang
3. O'rnatilgach CMD'ni yopib-oching va tekshiring:

```
flutter doctor
```

`[√] Visual Studio` bo'lsa, yig'asiz:

```
cd /d C:\hanguk
flutter build windows --release
explorer build\windows\x64\runner\Release
```

---

## 2. Foydalanuvchilarga tarqatish

Zip faylni Telegram yoki Google Drive orqali yuborasiz. Ochgan odam
`hanguk_online.exe` ni bosadi.

Windows birinchi ochilishda ko'k ogohlantirish ko'rsatishi mumkin —
*"Windows protected your PC"*. Bu dastur imzolanmaganidan (code signing
sertifikati yo'q). **More info → Run anyway** bosiladi. Sertifikat yiliga
pullik; kichik jamoa uchun odatda shart emas.

---

## 3. Nimalari telefondagidan farq qiladi

- Oyna 1440×920 o'lchamda, markazda ochiladi; 880×620 dan kichraytirib
  bo'lmaydi — undan pastda maket buziladi
- Keng ekranda yon menyu doimo ko'rinadi (telefonda pastki menyu edi)
- Sarlavha va ikonka: "Hanguk Academy — Onlayn ta'lim platformasi", 한 belgisi

---

## 4. macOS va Linux

Hozir yig'ilmaydi: `macos/` papkasi loyihada yo'q, `linux/` bor lekin
sinalmagan. macOS versiyasi kerak bo'lsa ayting — qo'shiladi, lekin uni
yig'ish uchun Mac kompyuter yoki pullik CI kerak bo'ladi.
