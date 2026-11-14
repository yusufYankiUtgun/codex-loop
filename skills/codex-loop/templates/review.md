# İnceleme mesajı şablonu

`-s "<skill klasörü>/templates/review.schema.json"` ile gönder (tam yol SKILL.md'de). <...> kısımlarını doldur.

## 1. tur

```
Ben Claude (Claude Code). Kodun sahibi benim; sen inceleyicisin. Salt okunur çalışıyorsun:
dosyalara dokunma, alt ajan ya da başka inceleyici başlatma.

## Amaç
<kullanıcının istediği şey, 1-3 cümle>

## İnceleme kapsamı (sabit)
Proje: <mutlak yol>
Base: <commit/branch>   Head: <commit/branch ya da "çalışma ağacı">
Diff'i görmek için: <örn. git diff <base>...HEAD -- <yollar>>  (ya da aşağıdaki diff)
<gerekirse diff ya da değişen dosya listesi>

## Kısıtlar ve verilmiş kararlar
<tartışmaya açık olmayan şeyler; yoksa "yok">

## Senden istediğim
- Değişikliğin amacı doğru ve güvenli şekilde karşılayıp karşılamadığını incele.
- Amacın dışına çıkan yeni özellik, refactor ya da kapsam büyütme önerme.
- Her bulgu için somut senaryo ver: hangi girdi/durumda ne yanlış olur.
- severity: davranışa etkisi olmayan stil/zevk = nit. Yanlış bir talimat, yanıltıcı yorum ya da
  yanlış dokümantasyon nit DEĞİLDİR (davranışsal etkisi vardır).
- Bulgu id'lerini F1, F2, ... diye ver.
- verdict: blocker/major/minor bulgu yoksa approved, varsa findings_remaining.
```

## 2. ve 3. tur (aynı oturuma `-r <id>` ile)

```
Bulgu durumu (benim kararlarım):
- F1 <kabul: şöyle düzelttim | ret: gerekçe | belirsiz: kullanıcıya soruyorum>
- F2 ...

Yeni diff: <sadece bu turda değişen kısım ya da komut>

Bu turda SADECE değişen koda ve açık bulgulara bak; kapanmış konuları yeniden açma.
Reddettiğim bulguda gerekçeme ikna olduysan status=withdrawn, olmadıysan still_open yap ve
neden olmadığını tek cümleyle claim'e yaz. Önceki id'leri koru; yeni bulgu ancak değişen kodda olabilir.
```
