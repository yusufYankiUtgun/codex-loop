# codex-loop

codex-loop, Claude ile OpenAI'nin Codex'ini aynı masaya oturtuyor. Bir plan yaparken, bir karar verirken ya da kod yazarken Claude işi tek başına bitirmiyor; Codex'le tartışıyor. İkisi birbirinin önerisini eleştiriyor, zayıf noktaları gösteriyor ve en sonunda ikisinin de arkasında durabileceği bir sonuca varıyorlar.

Bu neden işe yarıyor? Claude ile Codex farklı şirketlerin, farklı şekilde eğitilmiş modelleri. Güçlü oldukları ve kaçırdıkları yerler de farklı. Biri bir riski gözden kaçırdığında öbürü onu yakalıyor; biri gereksiz karmaşık bir yol önerdiğinde öbürü daha basitini gösteriyor. Birbirlerinin eksiğini kapatarak vardıkları sonuç, çoğu zaman tek bir modelin kendi başına bulacağından çok daha sağlam oluyor.

## Nasıl kullanılıyor?

Yeni bir komut öğrenmen gerekmiyor. Claude'a normal konuşur gibi söylemen yeterli:

- **"codex'e sor"**: Claude soruyu Codex'e iletiyor. Sana önce Codex'in ne dediğini, sonra kendi fikrini anlatıyor; nerede katıldığını, nerede katılmadığını ve nedenini söylüyor.
- **"codex'e inceletin"** ya da **"codex ile tartışın"**: Kodu Claude yazıyor, Codex inceliyor. Claude her bulguya tek tek bakıyor. Codex haklıysa düzeltiyor, haksızsa nedenini söyleyip itiraz ediyor, emin olamadığı noktayı sana soruyor. Bu gidip gelme en fazla 3 tur sürüyor, böylece iş uzayıp gitmiyor.
- **"planlamayı codex ile yapın"**: Claude bir plan taslağı çıkarıp Codex'le tartışıyor. Anlaşamadıkları bir nokta kalırsa iki tarafın görüşünü de sana getiriyor; kararı sen veriyorsun.

Codex hiçbir dosyayı değiştiremiyor, sadece okuyup fikir veriyor. Kodu her zaman Claude yazıyor, son söz de sende.

## Tartışma nasıl ilerliyor?

İnceleme ve planlama turlar hâlinde ilerliyor. Her turda biri konuşuyor, öbürü cevap veriyor:

1. **1. tur:** Codex işin tamamına bakıyor. İncelemede değişikliğin tamamını, planlamada Claude'un taslağını görüyor. Bulduğu her sorunu bir numarayla (F1, F2, …) ve "şu durumda şu bozulur" diye somut bir örnekle yazıyor.
2. **Claude'un cevabı:** Claude her maddeye tek tek karar veriyor: kabul edip düzeltiyor, gerekçesini söyleyip reddediyor ya da emin değilse sana soruyor.
3. **2. ve 3. tur:** Codex sadece değişen kısma ve hâlâ açık olan maddelere bakıyor. Claude'un itirazına ikna olduysa maddeyi geri çekiyor, olmadıysa neden olmadığını söyleyerek ısrar ediyor. Kapanmış bir konu yeniden açılmıyor.

Tartışma en fazla **3 tur** sürüyor. Bundan önce de bitebilir: Codex onay verirse ya da geriye sadece zevk meselesi küçük notlar kalırsa döngü kendiliğinden duruyor. Güvenlik, yetkilendirme ya da veri kaybı gibi ciddi bir risk varsa 5 tura kadar uzayabiliyor. Bu sınır, iki modelin sonsuza kadar birbirini düzeltmeye çalışıp işi büyütmesini engelliyor.

## Sonunda ne görüyorsun?

Claude, Codex'in itirazlarını sulandırmadan, "ufak tefek şeyler" diye geçiştirmeden aktarıyor. Bir inceleme bittiğinde şöyle bir özet geliyor:

```
Codex (<model>, high) ile 2 tur — karar: onayladı

Kabul ettiklerim:
  F1  Liste boş gelince fonksiyon çöküyordu → kontrol ekledim
Reddettiklerim:
  F2  "Bu döngüyü map ile yaz" → davranışı değiştirmiyor, gerek yok (Codex geri çekti)
Açık kalanlar: yok
```

Codex bir şeyde ısrar ediyorsa ya da anlaşamadıkları bir konu varsa bu özette açıkça görünüyor.

## Gereksinimler

- [Claude Code](https://claude.com/claude-code)
- [Codex CLI](https://github.com/openai/codex), giriş yapılmış olarak (`codex login`)
- `jq`, `python3`, `flock`, `setsid`, GNU `timeout` / `realpath` / `date`

codex-loop **Linux'ta** ve **Windows'ta WSL içinde** çalışır. Script'ler bash ile yazıldı ve Linux araçlarını (`flock`, `setsid`, GNU coreutils) kullandığı için doğrudan Windows'ta (Git Bash / PowerShell) çalışmaz.

| Sistem | Durum |
|---|---|
| Linux | Çalışır |
| Windows + WSL | Çalışır |
| Windows (doğrudan, WSL olmadan) | Çalışmaz |
| macOS | Test edilmedi |

**Windows'ta kullanacaksan:** Claude Code'u ve Codex CLI'ı WSL'in içine kur ve oradan çalıştır. VS Code kullanıyorsan önce VS Code'u WSL'e bağla (WSL eklentisi, "Connect to WSL"), Claude Code eklentisi o zaman WSL içinde çalışır. `jq` gibi eksik araçlar için WSL'de: `sudo apt install jq`.

## Kurulum

Claude Code içinde:

```
/plugin marketplace add yusufYankiUtgun/codex-loop
/plugin install codex-loop@codex-loop
```

ya da terminalden:

```bash
claude plugin marketplace add yusufYankiUtgun/codex-loop
claude plugin install codex-loop@codex-loop
```

Kurduktan sonra Claude Code'u yeniden başlat. Skill'i doğrudan çağırmak istersen: `/codex-loop:codex-loop`.

Kurmadan önce denemek istersen repo'yu klonlayıp tek oturumluk yükleyebilirsin:

```bash
git clone https://github.com/yusufYankiUtgun/codex-loop
claude --plugin-dir ./codex-loop
```

## Güvenlik

Codex her çağrıda şu ayarlarla çalışır; bunları açacak bir seçenek bilerek yoktur:

- `sandbox_mode="read-only"`, `approval_policy="never"`: dosya yazamaz, izin istemez
- Uygulamalar, eklentiler, tarayıcı, bilgisayar kontrolü ve çoklu ajan özellikleri kapalı
- `node_repl` MCP sunucusu kapalı

Codex projedeki dosyaları okuyabilir. Claude ona dosya içeriği yapıştırmaz, yalnızca yolu verir.

## Codex oturumlarının temizliği

Codex her konuşmayı kaydediyor. Claude ona sık danıştığında bu kayıtlar senin Codex geçmişini doldurur. Bu yüzden codex-loop, kendi açtığı konuşmaları iş bitince arşive kaldırıyor ve bir ay sonra siliyor.

Plugin iki hook ekler (`hooks/hooks.json`):

- **SessionEnd:** Claude oturumu kapanınca, o oturumda codex-loop'un açtığı Codex oturumları arşivlenir.
- **SessionStart:** Önceden arşivlenemeyenler tekrar denenir; arşivde 30 günü geçenler silinir.

Yalnızca bu plugin'in açtığı oturumlara dokunulur. Silmeden önce Codex'in kendi kaydında oturumun `codex exec` ile açıldığı doğrulanır. Terminalde, masaüstü uygulamasında ya da VS Code'da açtığın kendi Codex oturumların hiçbir zaman listeye girmez. Hook'lar işi arka plana bırakır, yani Claude Code'u bekletmez.

Takip kayıtları `~/.claude/codex-data/` altında tutulur. Elle kontrol için:

```bash
skills/codex-loop/codex-threads.sh list               # açık ve arşivli oturumlar
skills/codex-loop/codex-threads.sh archive <THREAD_ID>
```

## Ayarlar (ortam değişkenleri)

| Değişken | Varsayılan | Ne işe yarar |
|---|---|---|
| `CODEX_BIN` | `codex` | Codex komutu |
| `CODEX_HOME` | `~/.codex` | Codex'in config ve kayıt dizini |
| `CODEX_LOOP_DATA` | `~/.claude/codex-data` | Takip kayıtları |
| `CODEX_LOOP_TIMEOUT` | `540` | Bir Codex çağrısının zaman aşımı (sn) |
| `CODEX_LOOP_RETENTION_DAYS` | `30` | Arşivdeki oturumların kaç gün sonra silineceği |
| `CODEX_LOOP_LOCK_WAIT` | `300` | Kilit için en fazla bekleme (sn) |

Model ve düşünme seviyesi verilmezse Codex'in kendi config'i (`~/.codex/config.toml`) kullanılır. Claude'a "şu modelle sor" ya da "hızlı sor" dersen ona göre `-m` / `-E` verir.

## `codex-ask.sh`

Claude'un kullandığı script; istersen elle de çalıştırabilirsin:

```bash
skills/codex-loop/codex-ask.sh [-e] [-r THREAD_ID] [-C DİZİN] [-m MODEL] [-E SEVİYE] [-s ŞEMA] [-t SN] <<'EOF'
mesaj
EOF
```

| Seçenek | Açıklama |
|---|---|
| `-e` | Oturumu kaydetme (tek seferlik soru) |
| `-r <id>` | Aynı Codex oturumuna devam et |
| `-C <dizin>` | Codex'in bakacağı proje (varsayılan: mevcut dizin) |
| `-m <model>` | Codex modeli |
| `-E <seviye>` | `minimal`, `low`, `medium`, `high`, `xhigh` |
| `-s <şema>` | Cevabı JSON şemasına göre iste (inceleme: `templates/review.schema.json`) |
| `-t <sn>` | Zaman aşımı |

Çıktının ilk iki satırı `CODEX_THREAD_ID: …` ve `CODEX_MODEL: …`, ardından Codex'in cevabı gelir. Hata durumunda stderr'e `CODEX_ERROR: <TÜR>` yazılır:

| Çıkış kodu | Tür | Anlamı |
|---|---|---|
| 2 | — | Kullanım hatası |
| 124 | `TIMEOUT` | Codex süresinde bitmedi |
| 75 | `RATE_LIMIT` | Codex kotası / hız sınırı doldu |
| 77 | `AUTH` | Giriş geçersiz, `codex login` gerekli |
| 65 | `SCHEMA` | Cevap JSON şemasına uymadı |

## Testler

Sahte bir `codex` ile çalışır; gerçek Codex çağrılmaz, kota harcanmaz:

```bash
bash skills/codex-loop/tests/run.sh
```

## Repo yapısı

```
.claude-plugin/
  plugin.json          plugin bilgileri
  marketplace.json     repo'yu kurulabilir bir marketplace yapar
hooks/hooks.json       oturum temizliği hook'ları
skills/codex-loop/
  SKILL.md             Claude'a verilen talimatlar
  codex-ask.sh         Codex'e mesaj gönderen script
  codex-threads.sh     oturum takibi, arşivleme, silme
  templates/           soru, inceleme, planlama mesaj şablonları ve inceleme şeması
  tests/               testler ve sahte codex
```

## Lisans

[MIT](LICENSE)
