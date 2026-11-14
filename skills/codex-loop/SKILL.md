---
name: codex-loop
description: Kullanıcı Codex'e bir şey sormamı, Codex ile tartışmamı, kodu Codex'e inceletmemi ya da planı Codex ile birlikte yapmamı istediğinde kullan — örn. "codex'e sor", "codex ne diyor", "codex ile tartışın", "codex'e inceletin", "codex loop", "planlamayı codex ile yapın", "codex ile karar verin".
---

# Codex Loop

**Özet:** Codex (OpenAI) farklı eğitilmiş ayrı bir ajan; kör noktaları benimkinden farklı. Ona danışırım, bulduğunu değerlendiririm, son karar ve uygulama bende. İtiraz etmekten çekinme, kapsamı büyütme, Codex ne dediyse kullanıcıya dürüstçe raporla.

## Araç

`${CLAUDE_SKILL_DIR}` bu skill'in klasörüdür (script'ler ve şablonlar orada). Yer tutucu doldurulmamışsa `${CLAUDE_PLUGIN_ROOT}/skills/codex-loop` kullan.

```bash
"${CLAUDE_SKILL_DIR}/codex-ask.sh" [seçenekler] <<'EOF'
<mesaj>
EOF
```

| Seçenek | Ne işe yarar |
|---|---|
| `-e` | Kaydetme (tek seferlik soru). `-r` ile birlikte kullanılamaz. |
| `-r <id>` | Aynı Codex oturumuna devam (sonraki turlar). |
| `-C <dizin>` | Codex'in bakacağı proje. Varsayılan: mevcut dizin. |
| `-m <model>` | Model. Kullanıcı bir model söylerse kullan; söylemezse verme (Codex config'indeki varsayılan kullanılır). Hesaptaki modeller `~/.codex/models_cache.json`'da. |
| `-E <seviye>` | `minimal\|low\|medium\|high\|xhigh`. "Hızlı sor" denirse `-E low`. Söylenmezse verme (Codex config'indeki varsayılan kullanılır). |
| `-s <şema>` | Cevabı JSON şemasına göre iste. İnceleme modunda `${CLAUDE_SKILL_DIR}/templates/review.schema.json`. |
| `-t <sn>` | Zaman aşımı, varsayılan 540. |

Codex **her zaman salt okunur** çalışır (kullanıcı kararı); yazma izni verecek bir seçenek yoktur. Kodu ben yazarım.

- Mesajı her zaman heredoc ile stdin'den ver.
- Bash çağrısında `timeout: 600000` ver. 540 sn'den uzun sürebilecek büyük incelemelerde `-t` artır ve `run_in_background` kullan.
- Çıktının ilk iki satırı `CODEX_THREAD_ID: <id>` ve `CODEX_MODEL: <model> (<seviye>)`; sonra Codex'in cevabı.
- Codex salt okunur çalışır; uygulama/eklenti/tarayıcı/bilgisayar kontrolü/çoklu ajan özellikleri ve `node_repl` MCP sunucusu kapalıdır.

### Oturum seçimi: yeni iş = yeni oturum

- `-r` yalnız aynı işin turları arasında (tek bir inceleme ya da planlama sürerken) kullanılır.
- Yeni bir istek, önceki bir işle ilgili olsa bile yeni oturumla başlar. Önceki işin devamıysa, verilmiş kararların kısa özetini ilk mesaja yaz; eski oturuma dönme. Eski oturuma dönmek tüm geçmişi yeniden gönderir (önbellek de dakikalar içinde düşer, yani pahalıdır) ve alakasız ayrıntı taşır.
- İstisna: kullanıcı açıkça "o Codex konuşmasına devam et" derse id'yi `codex-threads.sh list` ile bul ve `-r` ile dene; olmazsa kullanıcıya söyle ve özetle yeni oturum aç.
- Kullanıcı kendi Codex oturumunun id'sini verip devam etmemi isterse script onu takibe almaz (stderr'de uyarı görünür) ve o oturum arşivlenmez/silinmez. Bu doğru davranıştır; `codex-threads.sh archive` ile de arşivlemeye çalışma.

### Hatalar

stderr'de `CODEX_ERROR: <TÜR>` görünür. Kullanıcıya ne olduğunu düz söyle; sessizce tekrar deneme.

| Kod | Tür | Ne yap |
|---|---|---|
| 124 | TIMEOUT | Kapsamı daralt ya da `-t` artırıp arka planda tekrar dene; kullanıcıya söyle. |
| 75 | RATE_LIMIT | Codex kotası dolmuş. Durdur, kullanıcıya söyle. |
| 77 | AUTH | Kullanıcıdan terminalde `! codex login` çalıştırmasını iste. |
| 65 | SCHEMA | Cevap şemaya uymadı; bir kez tekrar sor, yine olmazsa düz metinle devam et. |

## Codex'e bağlam verme

Codex bizim konuşmamızı görmez. Şablonları kullan (`${CLAUDE_SKILL_DIR}/templates/`): `ask.md`, `review.md`, `plan.md`. İçlerinde ne verilmesi gerektiği yazıyor: amaç, mutlak proje yolu ve ilgili dosyalar (kendisi okur, içerik yapıştırma), kısıtlar, verilmiş kararlar, ondan tam olarak ne istendiği.

## Modlar

### 1. Sor ("codex'e sor", "codex ne diyor")
- `templates/ask.md`, tek mesaj, `-e`.
- Kullanıcıya önce Codex'in cevabının özeti, sonra ayrı başlıkla kendi görüşüm: katıldıklarım, katılmadıklarım, nedenleri.

### 2. İncele / Tartış ("codex'e inceletin", "codex ile tartışın", "codex loop")
Kodun sahibi benim, Codex inceler. Doğru olanı düzelt, yanlış olana gerekçeyle itiraz et, anlaştığımızda ya da bütçe bitince dur.

- **Hedef:** amacı karşılayan en küçük değişiklik. İnceleme kodu doğru yapar, büyütmez.
- **Kapsam:** 1. turda base/head sabitlenir (`templates/review.md`); sonraki turlar aynı kapsamda kalır.
- **Şema:** her turda `-s "${CLAUDE_SKILL_DIR}/templates/review.schema.json"`.
- **Bütçe:** en fazla 3 tur. 1. tur: tüm değişiklik. 2–3. tur: sadece değişen kod ve açık bulgular. Yalnız güvenlik, yetki, kimlik doğrulama, veri kaybı riski varsa 5 tura çıkabilir.
- **Erken dur:** bir tur yalnız `nit` döndürürse döngü biter.
- **Nit:** davranışa etkisi olmayan stil/zevk. Yanlış talimat, yanıltıcı yorum ya da yanlış dokümantasyon nit değildir.
- **Tek inceleyici:** aynı anda tek Codex oturumu; Codex alt ajan başlatmaz.

**Bulgu defteri:** Bulguları turlar boyunca id'leriyle (F1, F2, …) takip et. Her bulgu için kararım: **kabul** (düzelttim, ne yaptım) / **ret** (gerekçe) / **belirsiz** (kullanıcıya sor). Sonraki turda defteri Codex'e geri gönder; kapanan konular yeniden açılmaz. Severity'yi ben değerlendiririm; Codex'in verdiği severity'ye körü körüne uyma ama raporda olduğu gibi göster.

### 3. Birlikte planla ("planlamayı codex ile yapın", "codex ile karar verin")
- Önce kodu inceleyip kendi taslağımı çıkarırım, sonra `templates/plan.md` ile Codex'e veririm.
- En fazla 3 tur. "ONAY" ya da kalan "ANLAŞMAZLIK" ile biter.
- Anlaşamadığımız nokta kalırsa iki görüşü de kullanıcıya sunarım, kararı o verir.
- Kullanıcı yalnız plan istediyse planı sunup onay beklerim; uygulamayı da istediyse uygularım.

## Dürüst raporlama (zorunlu)

Codex'in itirazlarını yumuşatma, gizleme ya da "küçük şeyler" diye geçiştirme. Her inceleme/tartışma/planlama sonunda:

```
Codex (<model>, <seviye>) ile N tur — karar: onayladı / açık bulgular kaldı / anlaşamadık
```

ardından:
- **Kabul ettiklerim:** id, bulgu, ne yaptım
- **Reddettiklerim:** id, bulgu, gerekçem ve Codex'in son tavrı (geri çekti / ısrar etti)
- **Açık kalanlar:** varsa, kararı kullanıcıya bırak

"onayladı" yalnız Codex'in son turdaki verdict'i `approved` ise yazılır. Bütçe bittiği için durduysam "açık bulgular kaldı" yazılır.

## PR imzası

Bu döngüden sonra bir PR açar ya da güncellersem, açıklamanın en sonuna (attribution satırlarından önce) ekle:

```
---
Reviewed with `codex-loop` (N rounds with <model>, <seviye>)
Codex verdict: approved / findings remaining
```

## Temizlik

Kayıtlı oturumlar otomatik takip edilir: Claude oturumu kapanınca arşivlenir, arşivden 30 gün sonra silinir. Yalnız bu script'in açtığı oturumlara dokunulur. İş bittiğinde yine de hemen arşivle ki kullanıcının Codex listesi o sırada kalabalık görünmesin:

```bash
"${CLAUDE_SKILL_DIR}/codex-threads.sh" archive <THREAD_ID>
```

Kullanıcı "Codex o gün ne demişti" diye sorarsa: arşivlenmiş dökümler `~/.codex/archived_sessions/*<id>.jsonl`; `response_item` satırlarındaki `user`/`assistant` mesajlarını okuyup özetle. Takip listesi: `codex-threads.sh list`.
