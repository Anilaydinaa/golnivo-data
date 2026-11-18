# Golnivo veri hattı

Saf Dart CLI; Flutter bağımlılığı yok. Komutları `pipeline/` içinden çalıştırın:

```sh
dart pub get
dart analyze
dart test
dart run bin/backtest.dart
dart run bin/build.dart --now 2026-11-18T06:00:00Z
dart run bin/validate.dart
```

`backtest.dart` gerçek kaynakları indirir, 9 parametre çiftini 2023-24 ve 2024-25 üzerinde karşılaştırır; 2025-26 holdout sonuçlarını `../docs/BACKTEST.md`, seçimi ve tüm ölçümleri `../data/model.json` içine yazar. `build.dart` günlük üretimde bu seçimi kullanır; parametreleri holdout üzerinden değiştirmez. İki CLI da yalnız daha önce indirilmiş kopyalarla çalışmak için `--offline` kabul eder. Üretimde varsayılan ağ erişimidir.

İndirme hatası son başarılı önbelleğe döner ve meta uyarısı üretir. Ayrıştırma hatası yayını durdurur; geçersiz yeni içerik önbelleğe yazılmaz. Dört çıktı önce geçici dizinde serileştirilip sözleşme denetiminden geçer; sonra yayın dizini değiştirilir. Aynı depo üzerinde iki build eşzamanlı çalıştırılmamalıdır; Actions bunu `concurrency` ile engeller.

`--now` saat dilimi içeren ISO tarih bekler. Arşiv geleceğe dönük bir kayıt olduğundan, üretim arşivinin zamanından önceye gitmek yerine ayrı bir veri dizini/anlık kopya kullanılmalıdır. Donmuş JSONL dosyasındaki mevcut kayıtlar yeniden yazılmaz. İlk başlangıçta geçmiş maçlar yalnız maç öncesi verilerle hesaplanır ve `backfilled: true` olarak ayrılır. Arşivde yalnız gerçekten yayın penceresine girmiş gelecek tahminler yayımlanmış sayılır.

`../data/overrides/matches.csv` sütunları: `season,homeId,awayId,date,kickoff,homeGoals,awayGoals,status,reason`. Diğer maç düzeltmesi CSV dosyaları da aynı başlığı kullanır. Boş alan önceki değeri korur; tarih değişip saat boş kalırsa saat temizlenir. `kickoff` açık saat dilimi içermeli; `null` saati temizler. `status=postponed` veya `scheduled` mevcut skoru temizler; `finished` skor gerektirir. Kimlikler `../data/teams.json` içinden alınır. Skorlar iki taraf için birlikte verilmelidir. Puan düzeltmeleri ayrı `point_adjustments.csv` dosyasında `season,teamId,points,reason` olarak bulunur; negatif değer puan düşürür. Düzeltmeler fikstürde olmayan maç oluşturamaz.

Testler ağ kullanmaz; ham dosyalar `test/fixtures/`, kaynak URL/lisans/SHA-256 bilgileri `test/fixtures/SOURCES.json` altında bulunur. Testlerin geçici dosyaları yalnız `test/.tmp/` içinde oluşturulup temizlenir.

Günlük workflow iki UTC zamanında çalışır, analiz ve testlerden sonra üretip yalnız `data/` ve `public/` değişikliklerini kaydeder. Workflow bu geliştirme sırasında çalıştırılmadı. GitHub Pages yayını ayrıca kurulmalıdır.
