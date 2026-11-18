# golnivo-data

Golnivo uygulamasının Süper Lig maç öncesi analiz verisi. Canlı skor içermez.

- `pipeline/` — saf Dart veri hattı: kaynakları indirir, zaman ağırlıklı Poisson modelini çalıştırır, `public/v1/` JSON dosyalarını üretir.
- `data/` — takım eşlemeleri, elle düzeltmeler, model parametreleri, tahmin arşivi (dondurulmuş tahminler değiştirilmez).
- `public/v1/` — yayımlanan veri (GitHub Pages).
- `docs/BACKTEST.md` — geriye dönük test sonuçları.

GitHub Actions günde iki kez (06:00 ve 21:30 UTC) veriyi yeniler ve Pages'e yayımlar.

## Kaynaklar ve lisans

- [openfootball/europe](https://github.com/openfootball/europe) — CC0 1.0
- Wikipedia katkıcıları, "2025–26 / 2026–27 Süper Lig" — [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

`public/v1/` ve `data/` altındaki derlenmiş veri CC BY-SA 4.0 ile paylaşılır.
Model çıktıları istatistiksel olasılıktır; garanti veya bahis tavsiyesi değildir.
