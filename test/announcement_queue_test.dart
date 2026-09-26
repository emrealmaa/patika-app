import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/announcement_queue.dart';

import 'fakes.dart';

void main() {
  late FakeSpeechOutput tts;
  late AnnouncementQueue queue;
  late DateTime now;

  setUp(() {
    tts = FakeSpeechOutput();
    now = DateTime(2026, 9, 26, 12);
    queue = AnnouncementQueue(tts, now: () => now);
  });

  // Kuyruk mikro görevlerle ilerliyor; her adımdan sonra boşaltılıyor.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> finish() async {
    tts.finishCurrent();
    await settle();
  }

  test('sırayla konuşur', () async {
    queue.add('bir');
    queue.add('iki');
    await settle();
    expect(tts.spoken, ['bir']);
    await finish();
    expect(tts.spoken, ['bir', 'iki']);
  });

  test('yüksek öncelik o an konuşulanı keser, kesilen tekrar okunmaz', () async {
    queue.add('bilgi', priority: AnnouncementPriority.low);
    await settle();
    queue.add('engel', priority: AnnouncementPriority.critical);
    await settle();
    expect(tts.stops, 1);
    expect(tts.spoken, ['bilgi', 'engel']);
    await finish();
    expect(tts.spoken, ['bilgi', 'engel']);
    expect(queue.current, isNull);
  });

  test('eşit ya da düşük öncelik konuşulanı kesmez', () async {
    queue.add('sonuç 1');
    await settle();
    queue.add('bilgi', priority: AnnouncementPriority.low);
    queue.add('sonuç 2');
    await settle();
    expect(tts.stops, 0);
    expect(tts.spoken, ['sonuç 1']);
  });

  test('bekleyenler önceliğe göre, eşitler geliş sırasına göre okunur', () async {
    queue.add('ilk', priority: AnnouncementPriority.critical);
    await settle();
    queue.add('bilgi', priority: AnnouncementPriority.low);
    queue.add('sonuç 1');
    queue.add('sonuç 2');
    queue.add('bağlantı', priority: AnnouncementPriority.high);
    for (var i = 0; i < 5; i++) {
      await finish();
    }
    expect(tts.spoken, ['ilk', 'bağlantı', 'sonuç 1', 'sonuç 2', 'bilgi']);
  });

  test('aynı duyuru konuşulurken ya da sıradayken birleştirilir', () async {
    queue.add('Gözlük bağlandı');
    queue.add('Gözlük bağlandı');
    queue.add('başka');
    queue.add('başka');
    await finish();
    await finish();
    expect(tts.spoken, ['Gözlük bağlandı', 'başka']);
  });

  test('aynı duyuru kısa sürede tekrar gelirse okunmaz, süre geçince okunur', () async {
    queue.add('Pil düşük');
    await finish();
    now = now.add(const Duration(seconds: 2));
    queue.add('Pil düşük');
    await settle();
    expect(tts.spoken, ['Pil düşük']);

    now = now.add(const Duration(seconds: 2));
    queue.add('Pil düşük');
    await settle();
    expect(tts.spoken, ['Pil düşük', 'Pil düşük']);
  });

  test('uzun bekleyen düşük öncelikli duyuru atılır', () async {
    queue.add('uzun sonuç');
    await settle();
    queue.add('bayat bilgi', priority: AnnouncementPriority.low);
    now = now.add(const Duration(seconds: 11));
    await finish();
    expect(tts.spoken, ['uzun sonuç']);
  });

  test('tekrar et: son duyuru birleştirme kuralına takılmadan tekrar okunur', () async {
    queue.add('Saat 14:05');
    await finish();
    queue.repeatLast();
    await settle();
    expect(tts.spoken, ['Saat 14:05', 'Saat 14:05']);
  });

  test('stopAll konuşmayı keser ve sırayı boşaltır', () async {
    queue.add('bir');
    queue.add('iki');
    await settle();
    queue.stopAll();
    await settle();
    expect(tts.stops, 1);
    expect(tts.spoken, ['bir']);
    expect(queue.current, isNull);
  });

  test('boş metin yok sayılır', () async {
    queue.add('   ');
    await settle();
    expect(tts.spoken, isEmpty);
  });
}
