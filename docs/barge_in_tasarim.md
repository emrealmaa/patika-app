# Sesle araya girme (barge-in) - tasarım notu (Madde 9)

Durum: **KOD YAZILMADI** (2026-10-14). Bu not, deneysel "konuşurken sesle
kesme" özelliğinin neden şimdi yazılmadığını, hangi koşullarla güvenli
yazılabileceğini ve kullanıcıdan beklenen kararları kaydeder.

## Bugünkü davranış (değişmedi, testle kilitli)

- TTS konuşurken mikrofon **kapalıdır**. Konuşmayı kesmenin tek yolu bir
  tetikleyicidir (gözlük dokunuşu, Konuş alanı, Hızlı Ayarlar karosu):
  `VoiceController.startListening` önce `AnnouncementQueue.stopAll()` ile TTS'i
  susturur, sonra dinler.
- SOS geri sayımında ayrı, sessiz bir dinleme oturumu açılır
  (`listenForSos`); yalnızca iptal / hemen gönder tanınır.
- `test/barge_in_lock_test.dart` bu iki kuralı kilitler.

## İstenen

Bluetooth kulaklık takılıyken, TTS konuşurken kısa bir komut kümesiyle
("dur", "tekrar et", "yardım") tetikleyicisiz kesme. Ayar bayrağı arkasında,
varsayılan kapalı. SOS davranışını asla etkilememeli.

## Neden şimdi güvenli değil

1. **Tanıyıcı uygun değil.** `speech_to_text` Android `SpeechRecognizer`
   kullanır: sürekli dinleme için tasarlanmamıştır (oturumlar 15-30 sn,
   `pauseFor` sonrası kapanır, yeniden açmak gerekir). Samsung One UI'da her
   oturum başında/sonunda sistem bip sesi çalabilir. Bu, TTS'in üstünde sürekli
   bip ve kesik dinleme demektir.
2. **Bluetooth SCO etkisi.** Kulaklık mikrofonundan dinlemek SCO (HFP) kanalını
   açar: TTS çıkışı da dar banda (8/16 kHz, "telefon sesi") düşer, A2DP müziği
   keser. Ayrıca `sos_call_monitor.dart`'taki açık soru: SCO'nun
   `AudioManager.getMode()`'u `MODE_IN_COMMUNICATION`'a geçirmesi SOS'un
   "arama sürüyor mu" algısını etkileyebilir. Sürekli dinleme bunu sürekli
   hale getirir. **Cihazda doğrulanmadan SOS'a dokunan bir risk.**
3. **Yankı ve yanlış komut.** TTS kendi cümlesinde "dur" geçerse (ör.
   "otobüs durağı" - tam kelime eşleşmesi korur ama STT "dur ağı" duyabilir)
   ya da kulaklık yankı bastırması zayıfsa uygulama kendi sesini komut
   sanabilir. "yardım" yanlış pozitifi SOS geri sayımı başlatır (geri sayım ve
   iptal var, ama gereksiz alarm Z21 riski).
4. **Pil.** Saatlerce sürekli mikrofon + bulut tanıma (Türkçe çevrimdışı
   model cihazda yoksa) pil ve veri tüketir.

## Güvenli olması için koşullar (yazılmadan önce)

- **Yerel anahtar kelime tanıyıcı** (bulut STT değil, oturumsuz): ör. Vosk
  (Apache-2.0, Türkçe küçük model ~40 MB) ya da Android'in kendi "hotword"
  API'si (yalnızca sistem asistanına açık, kullanılamaz). Porcupine'in
  ücretsiz lisansı ticari kullanıma kapalı: **uygun değil**. Vosk için yeni
  paket gerekir; **kullanıcı kararı (2026-10-14): Vosk eklenmeyecek**.
- Telefon testleri: (a) SCO açıkken TTS kalitesi ve `getMode()` değeri,
  (b) kulaklık yankısıyla kendi sesini tanıma oranı, (c) Samsung bip sesi,
  (d) bir saatlik pil tüketimi.

## Önerilen tasarım (koşullar sağlanınca)

- `Settings.bargeIn` (varsayılan **kapalı**), yalnızca Bluetooth kulaklık bağlı
  ve TTS **konuşurken** etkin; arama sürerken, SOS'un herhangi bir aşamasında
  ve dikte sırasında **hiç** açılmaz.
- Komut kümesi yalnızca TÜM cümle eşleşmesiyle: "dur", "tekrar et", "yardım"
  (`classifyControl`'un dikte kuralı gibi). Başka hiçbir niyet tanınmaz.
- Yankı bekçisi: o an konuşulan TTS metninde geçen kelime, konuşma bittikten
  ~500 ms sonrasına kadar komut sayılmaz.
- "yardım" doğrudan SOS'u değil, mevcut `triggerSos` yolunu çağırır (geri
  sayım + iptal varsayılanı GÖNDER aynen); SOS geri sayımı başlayınca
  barge-in dinleyicisi kapanır, SOS'un kendi `listenForSos` oturumu devralır.
- Testler: bayrak kapalıyken bugünkü davranış aynen (kilit testi); bayrak
  açıkken sahte tanıyıcıyla "dur" TTS'i keser; TTS metnindeki "dur" komut
  sayılmaz; SOS sırasında dinleyici kapalı.

## Kullanıcı kararları (2026-10-14)

1. **Vosk eklenmeyecek.** Barge-in, paket gerektirmeyen güvenli bir yerel
   tanıyıcı bulunana kadar ertelendi.
2. Cihaz testleri (yukarıdaki a-d) yapılmadan kod yazılmaması önerilir.
