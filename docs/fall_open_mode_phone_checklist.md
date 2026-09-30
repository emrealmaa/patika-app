# Düşme algılama açık modu: telefon deneme listesi (Faz 7c-2)

Gerçek cihazda, `direct` derleme türüyle. **Gerçek 112 hiçbir adımda aranmaz**
(düşmede 112 zaten kendiliğinden aranmaz; teklif penceresinde de çift
dokunmayın) - 112 test numarası ile temsil edilir (`EmergencyNumber`).
**Sentetik düğmeler gerçek düşme verisi DEĞİLDİR** ve açık modda hiçbir şey
göndermemelidir; uçtan uca deneme yalnızca gerçek düşme benzeri hareketle
yapılır.

**EŞİKLER TAMAMEN TAHMİNİDİR** ve gölge verisiyle ayarlanmamıştır: telefonu
gerçekten düşürmek yerine yumuşak bir yüzeye (yatak, minder) kontrollü bırakın;
adayın oluşması garanti değildir. Bir aday oluşmazsa bu, eşiklerin ayar
gerektirdiği demektir, hata değildir; not edin.

## Hazırlık

- [ ] `flutter run --flavor direct --dart-define-from-file=dart_defines.json`
      - `dart_defines.json`: `PATIKA_SOS_TEST_NUMBER` = **kendi ikinci
        numaranız**, `PATIKA_FALL_SKIP_SHADOW_GATE` = `true` (debug'da 7 gün
        kapısını atlar; release'te hiçbir etkisi yoktur).
- [ ] Acil kişi olarak **haberi olan** birini ve ikinci numaranızı ekleyin
      (SMS/arama gelecek). SMS ve konum izni verilmiş olsun.
- [ ] Ayarlar > Düşme algılama (deneysel) bölümü görünüyor, durum satırı
      "Mod: ..." diyor mu?

## A. Açma (iki adım) - ses kanalı

- [ ] "Düşme algılamayı aç": tam uyarı okunuyor mu (25 sn geri sayım, iptal,
      acil kişilere mesaj + arama, 112 kendiliğinden aranmaz, her düşmeyi
      algılamayabilir, güvenilmemeli, "Patika acil durum servisi değildir",
      "istediğiniz an iptal diyebilirsiniz")? Debug'da "7 gün kapısı atlandı,
      bu debug'a özel" uyarının başında söyleniyor mu?
- [ ] Uyarı bitene kadar mod hâlâ gölge mi (henüz açılmadı)?
- [ ] "Evet", "tamam", tek başına "aç" AÇMIYOR; ipucu ("evet yetmez")
      duyuluyor mu? İkinci yanlış cevapta açma iptal oluyor mu?
- [ ] "Anladım, aç" (ve "kabul ediyorum aç", "onaylıyorum aç"): açılıyor mu?
      STT "anladım aç"ı doğru tanıyor mu (TalkBack açık ve kapalıyken)?
- [ ] İkinci açışta (kapatıp yeniden) **kısa hatırlatma** okunuyor, yine iki
      adım isteniyor mu?
- [ ] Yavaş konuşma hızında tam uyarı 120 sn içinde bitiyor ve onay
      verilebiliyor mu?

## B. Açma - ekran kanalı (TalkBack açık ve kapalı)

- [ ] "Açık modu aç" düğmesi: uyarı penceresi açılıyor, **varsayılan odak
      "Vazgeç"**, düğmeler 56 dp, TalkBack metni okuyor mu?
- [ ] TalkBack AÇIKKEN uyarıyı yalnızca TalkBack okuyor, TTS susuyor mu?
      TalkBack KAPALIYKEN TTS okuyor mu (çift okuma yok)?
- [ ] "Vazgeç" ve geri tuşu: açılmıyor mu? "Anladım, aç": açılıyor, düğme
      "Açık modu kapat (gölge modu sürer)" oluyor, altta "Gölge modunu tamamen
      kapatmak için ... anahtarı" notu görünüyor mu?
- [ ] Sesle başlayıp ekrandan (ya da tersi) onaylamak açmıyor mu?
- [ ] Engelliyken (acil kişiyi silin ya da gölge süresi yokken debug atlamasını
      kapatın): düğme etkin kalıyor, basınca neden yazıyla ve sesle (TalkBack
      kapalıyken) söyleniyor mu?

## C. Uçtan uca düşme benzeri hareket (açık mod)

- [ ] Kontrollü bırakma sonrası aday oluştuysa: "Düşme algılandı..." + 25 sn
      geri sayım, bipler, **15 saniye kaldı / 5 saniye kaldı** duyuruları.
- [ ] Duyuru SIRASINDA mikrofon kapalı: kendi "iptal için iptal deyin" sesiniz
      SOS'u iptal ETMİYOR mu? Duyurudan sonra sesli "iptal" çalışıyor mu?
- [ ] Sesli iptal, gözlük dokunuşu (simülasyon), ekran iptal düğmesi: üçü de
      çalışıyor mu?
- [ ] İptal sonrası **2 dk** içinde ikinci bir hareket SOS başlatmıyor; 2 dk
      sonra yine başlatıyor mu? Elle SOS ("yardım") bu sırada çalışıyor mu?
- [ ] İptal edilmezse: SMS ikinci numaranıza ve haberli kişiye gidiyor, ilk
      kişi aranıyor, **112 aranmıyor**; sonuçlar söyleniyor mu? Teklif
      penceresi ("112'yi aramak için çift dokunun") açılıyor ama sizin
      onayınız olmadan arama yok mu?
- [ ] Test Modu kayıt listesi: satırlarda "Acil durum: geri sayım başladı /
      iptal edildi / gönderildi / başlatılmadı" etiketi görünüyor mu?
- [ ] **Sentetik düğmeler açık modda bile hiçbir şey göndermiyor** (geri sayım
      yok, SMS yok)?

## D. Diyalog ve mikrofon kesme

- [ ] Bir diyalog sürerken ("acil kişi ekle", dikte) düşme adayı: diyalog
      sessizce bitiyor, geri sayım başlıyor mu?
- [ ] Mikrofon açıkken aday: mikrofon kapanıyor, geri sayımdaki sesli "iptal"
      sonra duyuluyor mu (kapanmazsa "iptal" SOS'u iptal etmez, normal komut
      olur)? "Dinleme iptal edildi" kısa bildirimi geri sayım girişini
      bozuyor mu?
- [ ] Zaten süren bir SOS (geri sayım ya da SOS'un araması) varken gelen aday
      onu kesmiyor, ikinci SOS başlatmıyor mu?
- [ ] Bluetooth kulaklık/gözlükle aynı davranış.

## E. Guard ve cihaza özgü onay

- [ ] Açıkken **son acil kişiyi silin** ("acil kişi sil ..."): mod gölgeye
      düşüyor ve "Açık mod kapatıldı, gölge modu sürüyor. ..." SESLE
      söyleniyor mu? Bir kişi kaldıysa açık mı kalıyor?
- [ ] Açıkken Ayarlar'dan SMS iznini geri alıp uygulamayı yeniden açın: mod
      gölgeye düşüyor ve nedeni söyleniyor mu?
- [ ] Sesli "düşme algılamayı kapat" ve gölge anahtarı: **tam kapatıyor**
      (mod kapalı, gölge sayacı sıfırlanıyor) mu; yeniden açmak yeniden 7 gün
      (debug'da atlama) ve iki adım istiyor mu?
- [ ] **Yedekten geri yükleme:** ayarlar yedeğiyle (`adb backup` ya da Google
      yedeği / cihaz aktarımı) geri yüklenen cihazda ayarlarda `on` görünse
      bile açık mod silahlanmıyor, gölgeye düşüp "bu telefonda yeniden
      onayınızı istiyor" sesle söyleniyor mu? Onay dosyası
      (`noBackupFilesDir/fall_open_consent`) yedekten gelmiyor mu?
- [ ] Uygulama verisini silince onay da gidiyor mu?

## F. Pil ve arka plan

- [ ] Ekran kilitli, telefon cepteyken sensör akışı sürüyor mu (kesinti sayacı;
      CLAUDE.md "Bekleyen telefon testleri" 7c-1 (b), (g)). **Uyandırmayan
      sensörle devam edildi; kesinti yüksekse wake-up/wakelock ayrı düzeltme
      olarak eklenecek.**
- [ ] Açık modda bir günde kaç aday/iptal oluştu (yanlış pozitif oranı):
      eşik ayarı için kayıt listesinden not edin.
