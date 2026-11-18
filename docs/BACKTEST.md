# Geriye dönük test

Çalıştırma tarihi: 18.11.2026. Model: `poisson-tw-1`. Bu dosya `dart run bin/backtest.dart` ile gerçek kaynak anlık kopyalarından üretilir.

## Yöntem

Maçlar kaynak tarihi/başlangıcının takvim haftasına ayrılır; her grubun en erken dondurma anında yeniden eğitim yapılır. Başlangıcı bilinen maçta dondurma anı başlangıçtır; saatsiz maçta aynı sezon/round içindeki saatsiz maçların en erken yerel tarihinden üç gün önce 00:00 Türkiye saatidir. Saatli maçlar bu erken sınıra çekilmez. Eğitim: o tarihin sezonu ve önceki üç sezon içinde, sonucu eğitim kesiminden önce bilinebilir olan maçlar. Saat biliniyorsa başlangıç +3 saat; bilinmiyorsa Türkiye yerel gününün sonu kullanılır. Aynı haftanın sonraki sonuçları eğitime alınmaz. Ertelenip başka haftaya taşınan maç kendi tarihindeki haftaya girer. İstatistikler güncel kaynakta düzeltilmiş sonuçları içerir; geçmiş kaynak revizyonlarının ilk yayımlanma zamanları bilinmiyor.

Karar: Planın kaynak listesi 2021-22 ve 2022-23 içermediğinden bu sezonlar eklenmedi. Özellikle 2023-24 başlangıcında eğitim penceresinde yalnız 2020-21 var; bu veri boşluğu karşılaştırmanın sınırıdır. 2018-19 ve 2019-20 geçmiş ilk sezon önselini ve H2H bilgisini destekler.

L2 cezası 0.5 × λ_reg × toplam parametre farkı karesi. Çözüm deterministik L-BFGS, en fazla 600 adım, en büyük mutlak gradyan <0.0001. Yakınsamayan eğitim çalıştırmayı durdurur. Yükselen takım önseli yalnız önceki sezonu da veri setinde bulunan geçmiş ilk sezonların (en az 20 maç) lig ortalamasına göre log gol güçlerinden hesaplanır; veri yoksa sıfırdır. Gelecek sonuçlar kullanılmaz.

Skor matrisi 0–10, kesilen kuyruk toplamına bölünerek normalize edilir. Brier üç sınıftaki kare farkların toplamıdır (0–2). Log loss doğal logaritma kullanır. Tek sınıf seçen ev sahibi taban çizgisinde sıfır olasılıklar yalnız log hesabında 1e-15 ile sınırlanır. Frekans taban çizgisi aynı eğitim penceresindeki sonuç sayılarından, sınıf başına +1 yumuşatmayla üretilir. Piyasa fiyatları kullanılmadı; ücretsiz ve uygun lisanslı kaynak bulunmuyor.

## Parametre seçimi

2023-24 + 2024-25 toplam log loss en aza indirilir. 2025-26 yalnız raporlanan holdout; seçimde kullanılmaz.

| ξ (gün⁻¹) | λ_reg | Maç | Log loss |
|---:|---:|---:|---:|
| 0.001 | 1.0 | 718 | 0.9732 |
| 0.001 | 5.0 | 718 | 0.9712 |
| 0.001 | 15.0 | 718 | 0.9753 |
| 0.003 | 1.0 | 718 | 0.9721 |
| 0.003 | 5.0 | 718 | 0.971 |
| 0.003 | 15.0 | 718 | 0.9785 |
| 0.006 | 1.0 | 718 | 0.9745 |
| 0.006 | 5.0 | 718 | 0.9732 |
| 0.006 | 15.0 | 718 | 0.9832 |

Seçilen ξ=0.003, λ_reg=5.0.

## Sonuçlar

| Sezon | Yöntem | Maç | 1X2 isabet | Log loss | Brier | 3+ gol isabet | İki takım gol isabet |
|---|---|---:|---:|---:|---:|---:|---:|
| 2023-24 | Poisson | 380 | 197/380 (%51,84) | 0.9879 | 0.589 | %52,63 | %46,84 |
| 2023-24 | Her zaman ev sahibi | 380 | 173/380 (%45,53) | 18.8145 | 1.0895 | — | — |
| 2023-24 | Eğitim frekansları | 380 | 173/380 (%45,53) | 1.07 | 0.6467 | — | — |
| 2024-25 | Poisson | 338 | 182/338 (%53,85) | 0.9519 | 0.5624 | %55,62 | %53,55 |
| 2024-25 | Her zaman ev sahibi | 338 | 164/338 (%48,52) | 17.7803 | 1.0296 | — | — |
| 2024-25 | Eğitim frekansları | 338 | 164/338 (%48,52) | 1.0504 | 0.6329 | — | — |
| 2025-26 (holdout) | Poisson | 306 | 160/306 (%52,29) | 0.9984 | 0.5964 | %54,58 | %48,37 |
| 2025-26 (holdout) | Her zaman ev sahibi | 306 | 129/306 (%42,16) | 19.9783 | 1.1569 | — | — |
| 2025-26 (holdout) | Eğitim frekansları | 306 | 129/306 (%42,16) | 1.0871 | 0.6586 | — | — |

## Kalibrasyon

Her maçın üç sınıf olasılığı ayrı gözlemdir. Boş kovalar çizgiyle gösterilir.

| Sezon | Olasılık kovası | Gözlem | Ortalama tahmin | Gerçekleşme |
|---|---|---:|---:|---:|
| 2023-24 | 0.0–0.1 | 28 | 0.0727 | 0.0357 |
| 2023-24 | 0.1–0.2 | 114 | 0.1631 | 0.1491 |
| 2023-24 | 0.2–0.3 | 487 | 0.2537 | 0.2444 |
| 2023-24 | 0.3–0.4 | 194 | 0.347 | 0.3505 |
| 2023-24 | 0.4–0.5 | 161 | 0.4491 | 0.4783 |
| 2023-24 | 0.5–0.6 | 79 | 0.5438 | 0.519 |
| 2023-24 | 0.6–0.7 | 48 | 0.6399 | 0.6875 |
| 2023-24 | 0.7–0.8 | 19 | 0.7405 | 0.8421 |
| 2023-24 | 0.8–0.9 | 8 | 0.8309 | 0.75 |
| 2023-24 | 0.9–1.0 | 2 | 0.9144 | 1.0 |
| 2024-25 | 0.0–0.1 | 30 | 0.0735 | 0.0333 |
| 2024-25 | 0.1–0.2 | 133 | 0.157 | 0.1278 |
| 2024-25 | 0.2–0.3 | 408 | 0.2491 | 0.2451 |
| 2024-25 | 0.3–0.4 | 149 | 0.3468 | 0.349 |
| 2024-25 | 0.4–0.5 | 125 | 0.4477 | 0.368 |
| 2024-25 | 0.5–0.6 | 92 | 0.548 | 0.663 |
| 2024-25 | 0.6–0.7 | 37 | 0.655 | 0.7568 |
| 2024-25 | 0.7–0.8 | 25 | 0.7417 | 0.84 |
| 2024-25 | 0.8–0.9 | 15 | 0.8304 | 0.8 |
| 2024-25 | 0.9–1.0 | 0 | — | — |
| 2025-26 | 0.0–0.1 | 19 | 0.0761 | 0.0 |
| 2025-26 | 0.1–0.2 | 106 | 0.1573 | 0.1981 |
| 2025-26 | 0.2–0.3 | 378 | 0.2524 | 0.254 |
| 2025-26 | 0.3–0.4 | 160 | 0.3463 | 0.3625 |
| 2025-26 | 0.4–0.5 | 116 | 0.4437 | 0.3621 |
| 2025-26 | 0.5–0.6 | 76 | 0.5435 | 0.6053 |
| 2025-26 | 0.6–0.7 | 33 | 0.6517 | 0.697 |
| 2025-26 | 0.7–0.8 | 24 | 0.7442 | 0.5833 |
| 2025-26 | 0.8–0.9 | 6 | 0.8199 | 1.0 |
| 2025-26 | 0.9–1.0 | 0 | — | — |

## Güven etiketleri

Düşük: en büyük olasılık <0.42 veya takımlardan biri için eğitim penceresinde <6 lig maçı. Yüksek: en büyük olasılık ≥0.55 ve iki takımda da toplam zaman ağırlığı ≥12. Diğerleri orta. Eşikler holdout üzerinden ayarlanmadı; aşağıdaki grup büyüklükleri ve isabetler etiketin yorumlanmasını sağlar. Yüksek etiketi sonuç sözü değildir.

| Sezon | Etiket | Maç | 1X2 isabet |
|---|---|---:|---:|
| 2023-24 | low | 109 | %34,86 |
| 2023-24 | medium | 201 | %57,21 |
| 2023-24 | high | 70 | %62,86 |
| 2024-25 | low | 83 | %38,55 |
| 2024-25 | medium | 145 | %44,14 |
| 2024-25 | high | 110 | %78,18 |
| 2025-26 | low | 87 | %52,87 |
| 2025-26 | medium | 136 | %40,44 |
| 2025-26 | high | 83 | %71,08 |

## Veri ve sınırlar

[openfootball/europe](https://github.com/openfootball/europe) (CC0 1.0), [Wikipedia katkıcıları: 2025–26 Süper Lig](https://en.wikipedia.org/wiki/2025%E2%80%9326_S%C3%BCper_Lig) ve [2026–27 Süper Lig](https://en.wikipedia.org/wiki/2026%E2%80%9327_S%C3%BCper_Lig) (CC BY-SA 4.0). Wikipedia sonuçları takım kimliklerine dönüştürülüp openfootball fikstürüne birleştirildi. İndirilen asıllar `data/cache/`, ağsız test kopyaları `pipeline/test/fixtures/`, makinece okunur rapor `data/model.json` altında. Wikipedia kaynaklı türetilmiş sonuçlar aynı lisansla sunulur; [lisans](https://creativecommons.org/licenses/by-sa/4.0/), [sayfa geçmişi](https://en.wikipedia.org/w/index.php?title=2025%E2%80%9326_S%C3%BCper_Lig&action=history).

- 2018-19: 306 fikstür, 306 sonuç.
- 2019-20: 306 fikstür, 306 sonuç.
- 2020-21: 420 fikstür, 420 sonuç.
- 2023-24: 380 fikstür, 380 sonuç.
- 2024-25: 342 fikstür, 338 sonuç.
- 2025-26: 306 fikstür, 306 sonuç.
- 2026-27: 306 fikstür, 98 sonuç.

Eksik sonuçlar (değerlendirme dışı; gelecek fikstür hariç):

| Sezon | Tarih | Ev sahibi | Deplasman |
|---|---|---|---|
| 2024-25 | 2025-05-31 | Adana Demirspor | Gaziantep FK |
| 2024-25 | 2025-05-31 | Alanyaspor | Sivasspor |
| 2024-25 | 2025-06-01 | Bodrum FK | Beşiktaş |
| 2024-25 | 2025-06-01 | Samsunspor | Kayserispor |
| 2026-27 | 2026-10-18 | Çorum FK | Çaykur Rizespor |

Karar: Sözleşmede sonuç bekleniyor durumu bulunmadığından, başlangıcı geçmiş ve sonucu eksik maç postponed olarak işaretlenir; bu teknik etiket resmî erteleme tespiti değildir. meta.json uyarısı bu belirsizliği bildirir.

- Kaynak uyarısı: 2024-25: 4 sonuç eksik; bu maçlar eğitim ve test değerlendirmesine alınmadı.

İlk üretimde geçmiş tahminler walk-forward ile tamamlanır ve `backfilled: true` taşır. Bunlar gerçek zamanda yayımlanmış isabet olarak sayılmaz. Poisson bağımsız gol varsayımı, eksik sezonlar ve saat bilgisi olmayan maçlar başlıca sınırlardır.
