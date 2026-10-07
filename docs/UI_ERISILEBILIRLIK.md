# Arayüz ve erişilebilirlik kararları

Arayüz yenilemesinin (2026-10-07, `8e8cdfe`..`8feb25e`) kararları ve
gerekçeleri. Birincil kullanıcı görme engelli; ölçüt "göz alıcı" değil,
**ekrana bakmadan ve TalkBack ile kullanılabilir** olmak. Genel kurallar
(her widget'ta Semantics, en az 56 dp, bilgi asla yalnızca renkle)
`CLAUDE.md`'de; burada arayüze özgü olanlar var.

## 1. Tema ve renkler

- **Açık tema, tek kaynak:** tüm renk ve ölçüler `PatikaTokens`'ta
  (`lib/theme/app_theme.dart`). Ekranlar ve widget'lar renk/ölçü sabiti
  yazmaz. *Neden:* kontrast tek yerde ölçülebilsin, bir renk değişince
  her ekran birlikte değişsin.
- **Metin kontrastı 7:1 (WCAG AAA):** üst üste gelen her gerçek metin/zemin
  çifti `PatikaTokens.textPairs`'te listeli ve
  `test/theme_contrast_test.dart` her çiftin en az 7:1 olduğunu ölçer.
  Anlam taşıyan grafik öğeler (durum noktası, anahtar izi) en az 3:1
  (WCAG 1.4.11, `graphicPairs`). *Neden:* kullanıcıların bir kısmı az
  görür; AA (4,5:1) az gören biri için yetmeyebilir. Taslaktaki bazı
  renkler bu yüzden koyulaştırıldı (ton aynı, açıklık düşük; liste
  `app_theme.dart` doc'unda).
- **Durum yalnızca renkle verilmez:** renkli nokta ve ikonlar yardımcı
  işarettir, durum her zaman yazıyla da söylenir (ör. durum hapı).
- **SOS ekranı bilerek koyu:** uygulamanın geri kalanından ayrışsın,
  az gören biri de "acil durum ekranındayım" diye hemen anlasın.

## 2. Yazı tipi

- **Plus Jakarta Sans**, statik TTF'ler olarak uygulamaya gömülü
  (`assets/fonts/`, Regular/Medium/SemiBold/Bold/ExtraBold). *Neden:*
  çalışma anında ağdan font indirmek yok (çevrimdışı çalışır, ilk açılışta
  yazı tipi değişip yerleşim kaymaz).
- **Lisans:** SIL OFL 1.1, `assets/fonts/OFL.txt`. `lib/theme/font_license.dart`
  bunu Flutter'ın lisans listesine ekler (OFL, fontla birlikte lisans
  metninin dağıtılmasını ister).

## 3. Ekranlar ve gezinme

- **Ekranlar:** Konuş, Bağlantı, Ayarlar (alt çubuktan) ve SOS tam ekranı
  (geri sayım/gönderim sürerken her şeyin üstünde). Test Modu gizli,
  Ayarlar'daki sürüm satırına 7 dokunuşla açılır.
- **Üst uygulama çubuğu yok; her ekranın kendi başlığı var**
  (`Semantics(header: true)`). *Neden:* TalkBack'te ilk odak doğrudan
  ekranın adı olsun, araya fazladan bir öğe girmesin.
- **TalkBack açıkken Konuş ekranı tek büyük düğme**
  (`MediaQuery.accessibleNavigationOf`, `lib/screens/listen_screen.dart`):
  başlık ve ardından ekranın geri kalanının tamamı dinleme düğmesi.
  *Neden:* uygulamanın asıl işi sesli komut; ekranın neresine çift
  dokunulursa dokunulsun dinleme başlasın, düğmeyi aramak gerekmesin.
  Pil ve durum kartları sesli "durum" komutuyla zaten erişilebilir.
- **Bölüm başlıkları büyük harfe çevrilmez.** *Neden:* Dart'ın
  `toUpperCase()`'i yerel ayardan bağımsızdır ve Türkçe "i"yi "İ" yerine
  "I" yapar ("Bildirimler" → "BILDIRIMLER"): yanlış yazım, ayrıca ekran
  okuyucuya da bu yanlış metin gider.

## 4. SOS tam ekranı

Kaynak: `lib/widgets/sos_countdown_banner.dart`, test: `test/sos_screen_test.dart`.

- **`BlockSemantics`:** ekran açıkken arkadaki sekmeler ve alt çubuk
  TalkBack'ten düşer; kullanıcı görünmeyen öğelere gidemez. Bunu kanıtlayan
  test var ("açılınca arkadaki sekmeler ve alt çubuk TalkBack'ten düşer").
- **Odak zorla taşınmaz:** odak "İptal et" düğmesine programla
  götürülmez. *Neden:* TalkBack odaklanınca düğmeyi okur ve TTS'in geri
  sayım duyurusunun üstüne konuşur; acil durumda iki sesin çakışması
  duyuruyu anlaşılmaz yapar. İptal zaten sesle ve gözlük dokunuşuyla da
  yapılabiliyor.
- **Duyuru TTS'ten, canlı bölge yok:** geri sayım duyurusu
  `FeedbackSosAnnouncer` ile TTS'e gider; `liveRegion` kullanılmaz ki aynı
  cümle iki kez okunmasın.
- **Bilgi yalnızca renkle/halkayla verilmez:** kalan süre cümleyle yazılır;
  halka ve büyük sayı süs. Düğme en az 64 dp ve etiketi düğmenin içinde
  (dışarıdan `excludeSemantics` ile sarmak TalkBack'te dokunma eylemini
  kaybettiriyordu, bkz. README "Cihazda bulunan hatalar").

## 5. Animasyonlar

Kaynak: `lib/widgets/nabiz_halkalari.dart`, test: `test/animations_test.dart`.

- **Yalnızca süs:** dinleme nabzı (Konuş), tarama dalgası (Bağlantı) ve SOS
  geri sayım halkası `ExcludeSemantics` içinde; anlamsal etiketleri ve odak
  sırasını değiştirmez.
- **Yalnızca ilgili durum sürerken:** halkalar yalnızca dinlerken/tararken
  ağaca konur, durum bitince çıkar. Görünmeyen yerde (ör. SOS ekranının
  arkası) ticker susturulur. *Neden:* boşta sürekli dönen animasyon pil
  harcar ve "bir şey oluyor" diye yanlış bilgi verir.
- **"Animasyonları kaldır" açıkken durur**
  (`MediaQuery.disableAnimationsOf`): denetleyici hiç çalışmaz, halkalar
  durağan çizilir. *Neden:* hareket hassasiyeti olan kullanıcılar ve
  sistem ayarına saygı.

## 6. Bilinen sorunlar

- **`play` türünde "SOS nasıl çalışır?" kartı `direct` davranışını
  anlatıyor.** Ayarlar'daki kart (`Tr.sosHowSummary`, `Tr.sosHowDetails`,
  `lib/screens/settings_screen.dart`) "iptal etmezseniz acil kişilerinize
  gönderilir" diyor; bu yalnızca `direct`'te doğru. `play`'de SOS
  desteklenmez ve "Bu sürümde acil durum mesajı gönderilemiyor" der (Faz 7
  kararları madde 1). Eğitimdeki SOS cümlesiyle aynı sorun: **TODO.md
  madde 17**. İlk sürüm `direct` ile dağıtıldığı için şimdilik
  düzeltilmedi; `play` dağıtımı gündeme gelirse kart ve eğitim metni
  derleme türüne göre ayrılmalı.

## 7. Cihazda doğrulanacaklar

Otomatik testlerle kilitli olanlar dışında, şunlar gerçek telefonda (Galaxy
S24 FE, TalkBack açık) henüz denenmedi: uçtan uca TalkBack turu, SOS
ekranında odağın davranışı, "Animasyonları kaldır" ayarı, açılır kartların
genişleme durumunun okunması.
