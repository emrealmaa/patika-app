# SOS telefon deneme listesi (Faz 7a)

Gerçek cihazda, `direct` derleme türüyle. **Gerçek 112 hiçbir adımda
aranmaz** - 112 test numarası ile temsil edilir. Kod tarafı bunu zorunlu
kılıyor (`EmergencyNumber`, release dışında yalnızca enjekte edilen
numara); yine de bu listede hiçbir adımda gerçek 112'yi aramayın.

## Hazırlık (bir kere)

- [ ] `flutter run --flavor direct --dart-define-from-file=dart_defines.json`
      - `dart_defines.json`'da `PATIKA_SOS_TEST_NUMBER`: **kendi ikinci
        numaranız** (başka bir telefonunuz/SIM'iniz). "112" YAZMAYIN, kod
        onu yok sayar.
- [ ] Acil kişi olarak **haberi olan** birini ekleyin ("acil kişi ekle
      ..."): bu kişiye bunun bir test olduğunu, SMS/arama gelebileceğini
      önceden söyleyin.
- [ ] SMS izni kurulum sırasında istendi mi, verdiniz mi kontrol edin
      (Ayarlar > Uygulamalar > Patika > İzinler'den de doğrulanabilir).
- [ ] Konum izni verilmiş olsun (normal kullanım akışından).
- [ ] Ayarlar > Acil durum'da "112'yi ara" **kapalı** kalsın (bu bölümün
      çoğu adımı için).

## A. Elle SOS (gözlük/uzun basış simülasyonu, Test Modu'ndan)

- [ ] Uzun basış: geri sayım başlıyor mu, sesli "Acil durum çağrısı
      gönderilecek..." duyuluyor mu, bip'ler duyuluyor mu (son 3 sn
      sıklaşıyor mu)?
- [ ] Hiçbir şey yapmadan 7 sn bekleyin: SMS ikinci numaranıza VE haberli
      kişiye gidiyor mu (ikisi de)? Ardından tek bir arama başlıyor mu
      (ilk acil kişi - haberli kişi)?
- [ ] "Gönderildi" cümlesi yalnızca gerçekten giden SMS için mi söyleniyor
      ("iletildi/ulaştı" DENMEMELİ)?
- [ ] **Başarısız sayılır:** SMS gitmediği halde "gönderildi" denirse,
      ya da gerçek 112 arandıysa (asla olmamalı).

## B. İptal

- [ ] Yeni bir geri sayımda 2-3. saniyede tek dokunuşla iptal: "Acil durum
      çağrısı iptal edildi" duyuluyor mu, SMS/arama gitmiyor mu?
- [ ] Yeni bir geri sayımda sesle "iptal" (ya da "yanlış alarm", "vazgeç",
      "gerek yok") deyin: iptal oluyor mu?
- [ ] Geri sayımda "dur" deyin: **iptal OLMAMALI**, geri sayım sürmeli.
- [ ] **Başarısız sayılır:** "dur" iptal ederse, ya da sesli "iptal"
      geri sayımı durdurmazsa.

## C. Sesli SOS

- [ ] "Yardım" (ya da "imdat", "acil durum") deyin: geri sayım başlıyor
      mu?
- [ ] Geri sayımda "yardım"ı tekrarlayın (ilk 2 sn içinde DEĞİL, birkaç
      saniye sonra): hemen gönderiyor mu (beklemeden)?
- [ ] **Başarısız sayılır:** tetikleyici "yardım" cümlesinin kendisi
      (aynı anda/hemen ardından) geri sayımı atlayıp anında gönderirse.

## D. 112 ayarı

- [ ] Ayarlar > Acil durum'da "112'yi ara"yı açın: sesli uyarı
      duyuluyor mu (asılsız arama cezası notu)?
- [ ] Yeni bir SOS başlatın: SMS'ler yine hepsine gidiyor mu, ama arama
      **yalnızca test numarasına** mı gidiyor (acil kişiye DEĞİL)?
- [ ] Ayarı kapatıp tekrar deneyin: arama acil kişiye dönüyor mu?
- [ ] **Başarısız sayılır:** ayar açıkken gerçek 112 aranırsa, ya da
      ayar kapalıyken test numarası aranırsa.

## E. Acil kişi yok / SMS izni yok

- [ ] Tüm acil kişileri silin, SOS başlatın: "Acil kişi yok. 112'yi
      aramak için çift dokunun" duyuluyor mu, geri sayım hiç başlamıyor
      mu (izin penceresi açılmıyor mu)?
- [ ] Çift dokunun (ya da ekranda karşılığını kullanın): yalnızca test
      numarası aranıyor mu?
- [ ] Bir acil kişi ekleyip SMS iznini Ayarlar'dan elle geri alın, SOS
      başlatın: "SMS izni yok, acil durum mesajı gönderilemez"
      duyuluyor mu, geri sayım başlamıyor mu?

## F. Konum

- [ ] Konum servisini kapatın (GPS), SOS başlatın: "konum izni yok/
      konumsuz gönderiliyor" gibi bir şey duyuluyor mu, SMS yine de
      gidiyor mu (yalnızca konumsuz)?
- [ ] Konum servisini açıp tekrar deneyin: SMS'te Google Haritalar
      bağlantısı var mı, doğruluk metre olarak makul mü?

## G. Ekran kilitli / telefon cepte

- [ ] Ekranı kilitleyin, telefonu cebe koyun, gözlük simülasyonundan
      (ya da Hızlı Ayarlar karosundan) SOS tetikleyin: geri sayım sesle
      duyulabiliyor mu, konum alınıyor mu (arka plan servisi konum
      türüyle çalışıyor mu)?
- [ ] Bu sırada sesle "iptal" deyip iptal edebiliyor musunuz?

## H. Arama sırasında konuşmama

- [ ] Bir SOS'u sonuna kadar götürün (arama başlasın). Arama sürerken
      uygulama HİÇ konuşmuyor mu (SMS sonuçları arama BAŞLAMADAN
      söylenmiş olmalı)?
- [ ] Aramayı siz kapatın: birkaç saniye içinde "özet" konuşması geliyor
      mu (yalnızca bir sorun varsa - hepsi yolundaysa hiç konuşmayabilir,
      bu NORMAL)?
- [ ] Arama sürerken glasses'tan çift baş sallama deneyin (ayar açıksa):
      yeni bir dinleme AÇILMAMALI (bkz. kod notu, arama kanalıyla
      çakışmasın diye).
- [ ] **Başarısız sayılır:** uygulama arama sürerken (karşı taraf
      cevap verdikten sonra bile) herhangi bir şey seslendirirse.

## I. Genel gözlem (her senaryoda not alın)

- [ ] Kişi aranınca ses **hoparlörden mi** çıkıyor (eller serbest
      gerekiyor)?
- [ ] Çift SIM'de hangi SIM'den gidiyor?
- [ ] Uçak modunda / şebeke yokken: "Gönderilemedi, 112'yi aramak için
      çift dokunun" doğru mu söyleniyor?
- [ ] Galaxy S24 FE / Android 16'da pil optimizasyonu SOS'u kesiyor mu?

Bulgularınızı `CLAUDE.md`'deki "Bekleyen telefon testleri" listesine
işleyin (hangi madde doğrulandı/tutmadı).
