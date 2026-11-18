# Veri ve atıf

- `cache/openfootball-*.txt`: [openfootball/europe](https://github.com/openfootball/europe), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- `cache/wikipedia-*.json`: Wikipedia katkıcıları, [2025–26 Süper Lig](https://en.wikipedia.org/wiki/2025%E2%80%9326_S%C3%BCper_Lig) ve [2026–27 Süper Lig](https://en.wikipedia.org/wiki/2026%E2%80%9327_S%C3%BCper_Lig), [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Katkı geçmişleri sayfalardaki geçmiş bağlantısında bulunur.
- Ham kopyaların indirme tarihi, URL ve SHA-256 değerleri `pipeline/test/fixtures/SOURCES.json` içindedir. Önbellek sonraki başarılı indirmelerde güncellenir; test kopyaları sabittir.
- `teams.json`: 32 takımın ortak kimlikleri; sponsorlu kaynak adları takma ad olarak eşlenir. Bilinmeyen takım adları hata üretir.
- `model.json`: 9 çiftlik ızgara sonuçları, seçilen parametreler, sezon ölçümleri ve kalibrasyon. Kaynak veri üzerinde yürütülen gerçek backtest çıktısıdır.
- `archive/latest-2026-27.json`: yayınlanan gelecek maçların son tahminleri. `archive/frozen-2026-27.jsonl`: başlangıcı geçmiş maçların değişmeyen tahminleri.
- `overrides/`: elle düzeltme girişleri; ilk kurulumda yalnız başlık bulunur, sonuç uydurulmaz.

Wikipedia skorları takım kimliklerine dönüştürülüp openfootball tarih/fikstürüyle birleştirildi; öncelik sırası elle düzeltme, Wikipedia, openfootball. Wikipedia kaynaklı dönüştürülmüş sonuçlar ve bunları içeren `public/v1/` veri derlemesi CC BY-SA 4.0 ile paylaşılır. Kaynak atıfları yayınlanan `meta.json` içinde de bulunur. Model çıktıları maç öncesi geçmiş verilerden hesaplanır.

Karar: Sözleşmede sonucu beklenen geçmiş maç için ayrı durum yok. Böyle bir maç `postponed` etiketi ve meta uyarısıyla gösterilebilir; bu etiket resmî erteleme bilgisi sayılmaz. Sonuçları eksik eski sezon maçları eğitim ve ölçümden çıkarılır; ayrıntılar `docs/BACKTEST.md` içinde açıklanır.

## Başlangıç saati düzeltmeleri

`overrides/kickoffs.csv` başlığı: `season,homeId,awayId,kickoffLocal,status`.
`kickoffLocal` tam olarak `YYYY-MM-DD HH:MM` biçiminde Türkiye yerel saatidir (UTC+3).
Takımlar `teams.json` kimlikleriyle yazılır. Yerel tarih aynı zamanda kaynak maç tarihini düzeltir;
başlangıç UTC'ye dönüştürülür ve bu maç yalnız kendi başlangıcında dondurulur.
Aşağıdaki satır yalnız biçim örneğidir; doğrulanmadan veri dosyasına eklenmez:

```csv
season,homeId,awayId,kickoffLocal,status
2026-27,trabzonspor,eyupspor,2026-11-20 20:00,scheduled
```

`status` boş bırakılırsa mevcut skor/durum korunur. `scheduled` ve `postponed` önceki skoru
siler; `finished` kullanımı mevcut skor veya `homeGoals,awayGoals` sütunlarında skor gerektirir.
`matches.csv` ayrıca `date,kickoff,homeGoals,awayGoals,status,reason` sütunlarını destekler;
`kickoff` zaman dilimli ISO-8601 veya saati kaldırmak için `null` olabilir.
`kickoffLocal` ile `kickoff` aynı satırda birlikte verilmez. CSV dosyaları ad sırasıyla uygulanır;
aynı maç için çelişkili birden çok düzeltme girmeyin.

Saatsiz maçlar aynı sezon/round içindeki saatsiz maçların en erken yerel tarihinden üç gün önce
00:00 Türkiye saatinde dondurulur. Bilinen skor daima hemen dondurulur. Önceki yayının zamanı
bu sınırdan önce değilse tahmin walk-forward ve `backfilled: true` olur; canlı isabete eklenmez.
Karar: Sonucun eğitimde kullanılabilirlik zamanı bu güvenlik payından ayrıdır; saatsiz maçta
kaynak yerel gün sonu, saatli maçta başlangıç +3 saat korunur. Kaynak günü henüz dolmadan
skor biliniyorsa meta içinde `kaynak tarihi gerçek tarihten geç olabilir: <id>` uyarısı yer alır.
