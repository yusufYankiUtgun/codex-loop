# Planlama mesajı şablonu

Kayıtlı oturum (`-e` yok); sonraki turlar `-r <id>` ile. <...> kısımlarını doldur.

## 1. tur

```
Ben Claude (Claude Code). Kullanıcı bu planı seninle birlikte netleştirmemi istedi. Kararı ve
uygulamayı ben yapacağım. Salt okunur çalışıyorsun: dosyalara dokunma, alt ajan başlatma.

## Amaç
<kullanıcının istediği şey>

## Bağlam
Proje: <mutlak yol>   İlgili dosyalar: <yollar — kendin okuyabilirsin>
Kısıtlar / verilmiş kararlar: <...>

## Taslak planım
1. <...>
2. <...>

## Senden istediğim (kısa ve maddeli)
a) Plandaki somut hatalar ya da riskler (dosya:satır ile, varsa).
b) Her adım için: gerekli / gereksiz / değiştir — tek cümle gerekçe.
c) Kaçırdığım, gerçekten değer katacak en fazla 3 şey. Kapsamı büyütme.
Anlaşıyorsak son satıra "ONAY" yaz.
```

## Sonraki turlar

```
Değerlendirmem:
KABUL: <maddeler>
İTİRAZ: <madde — gerekçe — önerdiğim alternatif>
<açık soru varsa>

Kısa cevap ver. Anlaşıyorsak son satıra "ONAY" yaz; anlaşamadığımız nokta varsa açıkça "ANLAŞMAZLIK: ..." yaz.
```
