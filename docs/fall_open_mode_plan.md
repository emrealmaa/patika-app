# Düşme algılama - açık mod (Faz 7c-2) keşif ve planı

**Durum: altı karar verildi (2026-09-30, §8'de "KARAR"), kalanlar açık; kod
yok.** Kodlama 7c-1 telefon testinin sonucunu bekliyor, özellikle §0/1
(uyandırmayan sensör): sonuç 7c-2'nin tamamını etkiliyor. Seçenekler
artı/eksileriyle yazıldı; karar kullanıcıya ait. Sabit olanlar (tekrar
tartışılmaz): `CLAUDE.md` "Faz 7c kararları" (madde 3: iki adımlı açma, acil
kişi yoksa açılmaz, tam metin yalnızca ilk kez; madde 5: süre şartı; madde 6:
25 sn + 2 dk bastırma + 10 sn tekrar). 7c-1 kodu: `docs/fall_detection_plan.md`.

## 0. Bu planın bağlı olduğu ön koşullar (kodlamadan ÖNCE)

1. **7c-1 telefon testi** ("Bekleyen telefon testleri", ilk madde). Açık mod,
   telefon cepte ve ekran kapalıyken sensör verisi GELİYORSA anlamlı. Keşifte
   şunu gördük: `MotionProbe.kt` `getDefaultSensor(TYPE_ACCELEROMETER)` ile
   **uyandırmayan (non-wake-up)** ivmeölçeri kullanıyor. Uyandırmayan sensörler
   CPU uyurken olay üretmez/toplar; ekran kapalı, cepte telefonda kesinti ya da
   toplu gecikme beklenir (**varsayım, cihazda doğrulanmadı**). Seçenekler:
   wake-up varyantı (`getDefaultSensor(TYPE_ACCELEROMETER, true)`), kısmi
   wakelock, ya da ikisi. Hepsi pil maliyeti. Bu, 7c-1 testinin ana sorusu;
   cevabı 7c-2'nin yapılabilirliğini belirler.
2. **Gölge verisi, en az bir hafta günlük kullanım** (karar 5). Kesin yanlış
   pozitif eşiği ("X günde 1'den az") bu veriyle belirlenecek.
3. Android 9+ arka planda sürekli sensörleri yalnızca ön plan servisi varken
   verir; uygulamamızın servisi var (`BackgroundService`) ama sensör akışının
   servis ömrüyle birlikte sürdüğü cihazda doğrulanmadı.

## 1. Açık moda geçiş: iki adımlı onay

**Sabit:** Adım 1 uyarıyı okutur ve modu AÇMAZ; adım 2 ayrı bir turda yalnızca
"anladım, aç" kabul eder (genel "evet", sessizlik, başka cevap açmaz). Açık mod
metni **ilk seferde tam**, sonra **kısa hatırlatma** ("Düşme algılama deneysel,
hâlâ güvenilmemeli") - varsayım: kısa hatırlatmada da iki adım geçerli
(karar 3 "ikisi de geçerli" diyor), yalnızca uyarı metni kısalır.

### 1a. Kapılar (adım 1'den önce, sırayla; hangisi tutmazsa nedeni söylenir)

| Kapı | Gerekçe |
|---|---|
| `direct` derleme | `play`'de SOS "desteklenmiyor"; açık mod anlamsız olurdu |
| En az 1 acil kişi | karar 3 |
| SMS izni verilmiş | SOS anında izin istenmez (Faz 7 madde 7); yoksa geri sayım boşuna çalışırdı |
| Gölge modu en az 7 gündür açık | karar 5; "gölge ne zamandan beri" için **yeni kalıcı alan** gerekir (`fallShadowSince`) - kayıt listesi yetmez, çünkü yalnızca darbeye ulaşanları tutar |
| (İsteğe bağlı) sensör kesintisi oranı eşiği | telefon testinden sonra karar |

### 1b. Adım 1 -> adım 2 nasıl yürür: üç seçenek

**A) Yalnızca sesli diyalog** (`DialogFlow`, `EmergencyContactAddFlow` deseni)
- Artı: birincil kullanıcı için doğal; mevcut altyapı ve testler; cevapsızlıkta
  2 denemeden sonra iptal = güvenli yön; ekran gerekmez.
- Eksi: "aç" tek heceli, STT'de "ac/hac/aş" riski -> açmak zorlaşır (güvenli
  hata, ama can sıkıcı); ekranlı kullanıcıya keşfedilebilirlik düşük.

**B) Yalnızca ekran** (Ayarlar'da düğme -> uyarı penceresi, "Anladım, aç" ve
"Vazgeç" düğmeleri, varsayılan odak "Vazgeç")
- Artı: yanlış tanıma imkânsız; metin hem TalkBack'le hem TTS'le okunur.
- Eksi: sesle açılamaz; görme engelli kullanıcı için pencere akışı daha
  yorucu; ilk kullanımda dernekle deneme gerekir.

**C) İkisi, tek çekirdek - KARAR (2026-09-30)** - `FallEnableSession`: adım durumu, zaman
aşımı (öneri 60 sn), kapılar, "tam metin duyuldu mu" bayrağı tek yerde; ses
diyaloğu ve ekran penceresi yalnızca arayüz. Adım 2 **yalnızca adım 1'in
yapıldığı kanaldan** kabul edilir. **Kapatma her kanalda tek adım** (kapatmak
güvenli yön).
- Artı: STT sorunu ekranla aşılır; ikisi aynı kuralları paylaşır, testler tek.
- Eksi: iki arayüz = daha fazla yüzey ve test.

### 1c. "Anladım, aç" eşleştirme (A ve C için)
- Yalnızca tüm cümle, nezaket sözcükleriyle ("lütfen anladım, aç" gibi) -
  `classifySosVoice` ile aynı katı kalıp. Öneri: "anladım aç", "anladım,
  açabilirsin", "anladım açılsın". **Bilerek dar.**
- `parseYesNo` KULLANILMAZ ("evet/tamam" açmasın).
- Bu kalıp Dikte ve diğer diyalog cevaplarında hiç denetlenmez.

### 1d. "İlk kez tam metin" bayrağı: neye bağlı?
- **Öneri:** bayrak yalnızca "anladım, aç" verildiğinde kalıcı olarak yazılır.
  Tam metni duyup vazgeçen kullanıcı sonraki denemede yine tam metni duyar.
- Alternatif: metin okunur okunmaz yazılır. Artı: daha az tekrar. Eksi: metni
  yarıda kesen/duymayan kullanıcı bir daha tam metni hiç duymaz.
- Bayrak ayarlardan ayrı saklanır (`LoudMessagesNotice` gibi), "ayarları sıfırla"
  uyarıyı silmesin.

### 1e. Açıkken bir kapı bozulursa (acil kişi silindi, SMS izni geri alındı)
1. Mod açık kalır; düşme anında ön kontrol engeller ve **konuşur** ("Acil kişi
   yok, 112'yi aramak için çift dokunun", Faz 7 madde 7). Eksi: yanlış pozitifte
   rahatsız edici ve 112 teklifi sunar.
2. **Kalan son acil kişi silinince / izin geri alınınca otomatik gölgeye düşer
   ve bunu sesle söyler - KARAR (2026-09-30).** Eksi: ek bağlantı (kişi silme akışı ve
   uygulama açılış yoklaması mod durumuna dokunur). İzin iptali yalnızca
   açılışta yoklanabilir.
3. Sessizce devre dışı bırakmak - **önerilmez** (sessiz kopma yok ilkesi).

## 2. SosController bağlantısı

### 2a. Tetik yolu: üç seçenek
- **A)** `FallMonitor` kurucusuna `onCandidate` geri çağrısı. Artı: küçük.
  Eksi: monitörün "SOS'a hiç dokunmaz" garantisi geri çağrıyla yumuşar, kapı ve
  bastırma mantığı AppState'e dağılır.
- **B)** `AppState` `FallShadowLog`'u dinler. Eksi: kayıt yazımı ile tetik
  birbirine bağlanır; yazma hatası tetiği etkileyebilir. **Önerilmez.**
- **C) `FallSosBridge` - KARAR (2026-09-30):** ayrı küçük sınıf; girdisi aday akışı, çıktısı
  `trigger(SosSource.fall)`; mod, kapılar ve bastırma bu sınıfta; monitör ve
  `lib/fall/` SOS'suz kalır (bugünkü kaynak taraması testi bozulmaz, yalnızca
  köprünün dosyası `lib/sos/` altında olur). Artı: tek yerde, tam testli.

**Kilit testleri güncellenir:** "SosSource.fall yalnızca lib/sos/ içinde"
testi köprü `lib/sos/`'ta olduğu için geçerli kalır; yeni testler: yalnızca
açık modda, yalnızca `candidate`'da, yalnızca bastırma dışındayken tetikler;
gölge/kapalıda asla. **Sentetik kaynak köprüye hiç bağlanmaz** (§4).

### 2b. 25 sn geri sayım
Bugün var: `SosConfig.fallCountdown = 25 sn`, girişte "Düşme algılandı..."
cümlesi (`Tr.sosFallCountdownStart`), her saniye bip, iptal kanalları (sesli
"iptal", gözlük dokunuşu, ekran), 112 kendiliğinden aranmaz. **Eksik:** giriş
cümlesi dışında konuşma yok; tekrar duyuru yok.

### 2c. 10 sn'de bir tekrar duyuru: anlamı ve seçenekler
"10 sn'de bir" 25 sn için geçen süre 10 ve 20'de, yani kalan **15 ve 5**
sn'de duyuru demek (ilk cümle 25'te).
- **A) Kısa cümle, kalan süreyle - KARAR (2026-09-30):** "15 saniye kaldı,
  iptal için iptal deyin" (kalan 15 ve 5 sn'de). Artı: kullanıcı durumu yeniden duyar. Eksi: yoğun kullanımda 2 kez
  konuşma.
- **B) Yalnızca kalan süre:** "15 saniye". Artı: çok kısa. Eksi: iptal yolunu
  hatırlatmaz.
- **C) Son 10 saniyede geri sayım sesli okunur.** Artı: gerilim/netlik. Eksi:
  kalabalık, bip ile çakışır.

**Teknik risk (hepsi için):** TTS konuşurken mikrofon kendi sesimizi duymasın
diye "iptal" dinleme kapatılıyor (`_introDone` mantığı). Her tekrar ~2-3 sn
sesli iptali devre dışı bırakır. Önlem: cümle kısa, konuşma biterken dinleme
hemen açılır; ekran ve gözlük dokunuşu iptali her zaman açık. `tick`
arayüzüne kaynak bilgisi (ya da "elle/düşme" ayrımı) gerekir: bugün `tick`
yalnızca kalan süreyi alıyor.

### 2d. 2 dk bastırma: anlam noktaları
1. **Ne zaman başlar?** İptal anından (ÖNERİ; kullanıcı "yanlış alarm" dediği
   an) ya da adayın oluştuğu andan. İptal anı daha doğru: geri sayım 25 sn
   sürdüğü için aday anından 2 dk fiilen 95 sn olurdu.
2. **Neyi bastırır?** Yalnızca düşme kaynaklı yeni tetiği. Gölge kaydı devam
   eder; elle SOS (sesli, gözlük) ve sesli "yardım" **hiç etkilenmez**.
3. **Gönderilen SOS sonrası?** Ayrı kural zaten var (60 sn, iptal/başarısızı
   saymaz). İkisi birbirine karışmaz.
4. **Kalıcı mı?** Bellekte (uygulama yeniden başlarsa sıfırlanır). Artı: basit;
   eksi: uygulama çökerse bastırma kaybolur. Öneri: bellekte.
5. **Bastırılan aday kaydı:** kayda etiket (bkz. §3).

### 2e. Meşgulken gelen aday
- Zaten geri sayım/gönderim sürüyorsa: `trigger` `alreadyRunning` döner
  (mevcut davranış), ikinci aday yalnızca kayda yazılır.
- Diyalog (mesaj dikte) ya da gelen arama sürerken: SOS diyaloğu keser
  (güvenlik-önce, Faz 7a). **Öneri: düşme için de aynı** (gerçek düşme o
  sırada olabilir). Alternatif: diyalog sürerken bastırmak -> yanlış negatif
  riski; önerilmez.
- Telefon ekranı açıkken (elde tutuluyor olabilir) tetiklememek yanlış
  pozitifi azaltır ama elde telefonla düşen biri için yanlış negatif. **Karar
  gölge verisine bırakılsın**, şimdi eklenmesin.

### 2f. Ön kontrol başarısızlığı (düşmede)
Bugünkü kural ("ön kontrolde takılan SOS her kaynakta 112 teklifi açar")
düşmede yanlış pozitifte gürültülü. 1e/2 (otomatik gölgeye düşme) bunu nadir
yapar. Ayrıca düşme için "teklif yok, yalnızca nedeni söyle" seçeneği var.
**Karar sizde;** öneri: Faz 7 madde 5 aynen kalsın (her kaynakta teklif), çünkü
açık modu kapı bozulunca da kullanıcı yardımsız kalmamalı.

## 3. Gölge kaydı şeması (açık moda geçişle birlikte)

- **Bir iptal = gerçek dünyada en güçlü yanlış pozitif etiketi.** Açık modda
  kullanıcının "iptal" demesi, eşik ayarı için altın değerinde. **KARAR
  (2026-09-30): kayda `act` alanı eklenir:** `none` (gölge/kapalı), `sos_started`,
  `cancelled`, `sent`, `suppressed`. Konum ve ham veri yine yok.
- Bu, `fall_shadow_log_test.dart`'taki **alan beyaz listesini bilinçli olarak
  değiştirir** (test güncellenir, gerekçesi yazılır). Eski satırlar
  `act` yokken `none` okunur.
- Alternatif: şema değişmez, iptaller yalnızca `SosController.history`'de
  (bellekte, kalıcı değil). Eksi: yanlış pozitif verisi kaybolur.

## 4. Test Modu'ndaki sentetik düğmeler açık modda ne yapar?

**Sentetik kaynak köprüye BAĞLANMAZ (ÖNERİ, kilitli testle).** Aksi halde bir
Test Modu düğmesi gerçek acil kişilere gerçek SMS atardı.
- Açık modun uçtan uca denemesi: debug derlemesinde, acil kişi olarak **ikinci
  numarayla** (mevcut SOS deneme listesi yaklaşımı, asla gerçek 112 değil),
  telefonu gerçekten düşürerek ya da elle sallayarak. `docs/sos_phone_test_checklist.md`
  benzeri bir liste 7c-2'de yazılır.
- Alternatif: "deneme geri sayımı" (mesaj göndermeyen kuru çalıştırma) için
  `SosDelivery`'ye kuru-çalıştırma kipi. Artı: telefonsuz denenebilir. Eksi:
  SOS yoluna test amaçlı bir dal eklemek, SOS'un en sade kalması gerektiği
  yerde risk. **Önerilmez.**

## 5. Ayarlar ekranında görünürlük

Bugün: Ayarlar "Acil durum" bölümünde yalnızca 112 anahtarı; gölge modu yalnızca
Test Modu'nda.

- **A) "Acil durum" bölümüne 3 konumlu seçici (Kapalı / Gölge / Açık).**
  Artı: tek yer, az yüzey. Eksi: "Açık" seçimi bir anahtar gibi görünür,
  iki adımlı açmayla uyumsuz hissettirir; seçiciyi görüp "Açık"a dokunan
  kullanıcı beklenmedik bir pencereyle karşılaşır.
- **B) Ayrı "Düşme algılama (deneysel)" bölümü - KARAR (2026-09-30):**
  - Durum satırı (okunur metin): "Mod: kapalı / gölge, 3 gündür, 2 kayıt /
    açık".
  - "Gölge modu" **anahtarı** (kapatmak/açmak tek adım; açarken gölge
    uyarısı sesle).
  - "Açık modu aç" **düğmesi** (anahtar değil, eylem): §1'in iki adımını
    başlatır. Açıkken yerine "Açık modu kapat".
  - Artı: anahtar kazara tek dokunuşla açılmaz; durum ve neden metinleri yer
    bulur; eğitim metniyle uyumlu. Eksi: daha fazla yüzey.
- **C) Yalnızca sesle + Test Modu; Ayarlar'da salt okunur durum satırı.**
  Artı: en az yüzey, kazara açma en az. Eksi: ekranlı kullanıcı için
  keşfedilebilirlik düşük, sesle açmanın STT'ye bağımlılığı.

### Engellenmiş durumda (acil kişi yok vb.)
- **A) Düğme devre dışı + gerekçe metni altında.** Eksi: TalkBack "devre dışı"
  der ama nedeni ayrı bir satırda; kullanıcı düğmeyi "atlar".
- **B) Düğme etkin kalır, basınca nedeni sesle + yazıyla söyler, gerekiyorsa
  yönlendirir ("Önce acil kişi ekleyin: 'acil kişi ekle' deyin") (ÖNERİ).**
  Artı: her kanalda (ekran, ses) aynı metin; keşfedilebilir. Eksi: düğmeye
  basınca "olmadı" cevabı.
- Gerekçe metinleri tek yerde (`Tr`), hem düğme hem sesli komut kullanır:
  acil kişi yok / bu sürümde SOS yok / SMS izni yok / gölge süresi dolmadı
  (kalan gün sayısıyla).

## 6. Sesli komutlar (yeni niyet)
"Düşme algılamayı aç/kapat", "gölge modunu aç/kapat", "düşme algılama durumu".
- **Açma her zaman §1'in iki adımı**; tek cümlede açılmaz.
- "Kapat" tek adım; kapalıyken "kapat" zararsız bilgi ("zaten kapalı").
- Sınıflandırıcı: katı kalıp (tüm cümle), puanlamadan önce; "acil durum" SOS,
  "durum" DURUM, "dur" DUR çakışmaları testle kilitlenir (7b dersi).

## 7. Durum komutu, eğitim metni, belgeler
- "Durum" cümlesi: açık modda "Düşme algılama açık, deneysel" (gölge cümlesi
  gibi tek cümle, yalnızca kapalı değilse).
- Sesli eğitime düşme algılama **eklenmez** (deneysel); yalnızca komutlar
  listesinde. `TODO.md` madde 17 (eğitim metni `play` için yanlış) geçerli.
- Kaynak: "Patika acil durum servisi değildir" cümlesi açık mod uyarı metnine de
  girer mi? **Karar sizde;** öneri: evet, tam metnin sonuna tek cümle.

## 8. Karar listesi

**Verilen kararlar (2026-09-30, tekrar tartışılmaz):**

| # | Konu | Karar |
|---|---|---|
| 1 | Adım 1 -> 2 kanalı | **C:** sesli + ekran, tek çekirdek (`FallEnableSession`); adım 2 yalnızca adım 1'in kanalından; kapatma her kanalda tek adım |
| 4 | Açıkken kapı bozulursa | Otomatik gölgeye düşer ve **sesle söyler** |
| 5 | Tetik yolu | **C:** ayrı `FallSosBridge` (`lib/sos/` altında); `lib/fall/` SOS'suz kalır |
| 6 | Tekrar duyuru | Kısa cümle, kalan süreyle: "15 saniye kaldı, iptal için iptal deyin" (kalan 15 ve 5 sn'de) |
| 10 | Kayıt şeması | `act` alanı eklenir (`none`, `sos_started`, `cancelled`, `sent`, `suppressed`); alan beyaz listesi testi bilinçli güncellenir |
| 12 | Ayarlar | **B:** ayrı "Düşme algılama (deneysel)" bölümü, gölge anahtarı + "Açık modu aç" **düğmesi** |

**Açık kalanlar (önerim parantezde):**

2. "Anladım, aç" kalıpları: dar liste (§1c).
3. Tam metin bayrağı ne zaman yazılır (yalnızca "anladım, aç" verilince).
7. Bastırma (iptal anından, yalnızca düşme kaynaklı, bellekte).
8. Meşgulken (diyalog/arama sürerken de tetikle; SOS diyaloğu keser).
9. Ön kontrol başarısızlığında 112 teklifi (Faz 7 madde 5 aynen).
11. Sentetik kaynak köprüye bağlanmaz; uçtan uca deneme ikinci numarayla
    (öneri; kilitli testle).
12b. Engellenmiş durumda "Açık modu aç" düğmesi (etkin kalır, nedeni söyler).
13. Açık mod uyarısına "Patika acil durum servisi değildir" cümlesi (evet).
14. Wake-up sensör / wakelock (7c-1 telefon testinden sonra; **7c-2'nin ön
    koşulu**).

## 9. Önerilen sıra (karar sonrası, her adım tek tek gösterilir)

1. `fallShadowSince` + kapı mantığı (`FallOpenModeGate`, saf, testli).
2. `FallEnableSession` (iki adım, zaman aşımı, kanal kilidi, bayrak) + testler.
3. Sesli diyalog + sınıflandırıcı kalıbı + testler.
4. Ayarlar bölümü + onay penceresi + erişilebilirlik testleri.
5. `FallSosBridge` (tetik, bastırma, meşgulken) + **SOS kilit testlerinin
   bilinçli güncellenmesi**.
6. Tekrar duyuru (`SosAnnouncer.tick` kaynak bilgisi) + testler.
7. Kayıt şeması `act` + test güncellemesi.
8. Belgeler, deneme listesi (`docs/fall_open_mode_phone_checklist.md`).
