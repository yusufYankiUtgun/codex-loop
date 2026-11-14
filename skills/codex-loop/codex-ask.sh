#!/usr/bin/env bash
# Codex'e stdin'den gelen mesajı gönderir, son cevabını stdout'a basar.
#
# Kullanım:
#   codex-ask.sh [-r THREAD_ID] [-C DIR] [-m MODEL] [-E EFFORT] [-s SCHEMA] [-t SN] [-e] <<'EOF'
#   ...mesaj...
#   EOF
#
#   -r THREAD_ID  Önceki Codex oturumuna devam et (tartışmanın sonraki turları)
#   -C DIR        Codex'in çalışma dizini (varsayılan: mevcut dizin)
#   -m MODEL      Codex modeli (varsayılan: ~/.codex/config.toml'daki)
#   -E EFFORT     Düşünme seviyesi: minimal|low|medium|high|xhigh (varsayılan: config)
#   -s SCHEMA     Cevabı bu JSON Schema'ya göre iste (inceleme modu); geçersiz cevap hata sayılır
#   -t SN         Zaman aşımı, saniye (varsayılan: 540 ya da $CODEX_LOOP_TIMEOUT)
#   -e            Ephemeral: oturumu diske kaydetme (tek seferlik soru; -r ile birlikte kullanılamaz)
#
# Codex her zaman salt okunur çalışır; yazma izni verecek bir seçenek bilerek yoktur.
# -r ile yalnız codex-loop'un takip ettiği oturumlar takibe alınır; başka bir oturuma
# (kullanıcının kendi oturumu) devam edilirse o oturum listeye yazılmaz, arşivlenmez.
#
# Çıktı başlığı:
#   CODEX_THREAD_ID: <id>      sonraki turlarda -r ile ver
#   CODEX_MODEL: <model> (<effort>)
# Kayıtlı oturumlar codex-threads.sh tarafından arşivlenir ve 30 gün sonra silinir.
#
# Çıkış kodları: 0 tamam, 2 kullanım hatası, 124 zaman aşımı, 75 kota/rate limit,
# 77 giriş/yetki, 65 şemaya uymayan cevap, diğerleri Codex'in kendi kodu.
# Hata durumunda stderr'e "CODEX_ERROR: <TÜR> — <açıklama>" yazılır.

set -uo pipefail

CODEX_BIN="${CODEX_BIN:-codex}"
DATA_DIR="${CODEX_LOOP_DATA:-$HOME/.claude/codex-data}"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"

thread=""
dir="$PWD"
model=""
effort=""
schema=""
tmo="${CODEX_LOOP_TIMEOUT:-540}"
ephemeral=0

usage() { echo "Hata: $1" >&2; exit 2; }

while getopts "r:C:m:E:s:t:e" opt; do
  case "$opt" in
    r) thread="$OPTARG" ;;
    C) dir="$OPTARG" ;;
    m) model="$OPTARG" ;;
    E) effort="$OPTARG" ;;
    s) schema="$OPTARG" ;;
    t) tmo="$OPTARG" ;;
    e) ephemeral=1 ;;
    *) usage "geçersiz seçenek" ;;
  esac
done

[ "$ephemeral" = 1 ] && [ -n "$thread" ] && usage "-e ve -r birlikte kullanılamaz"
case "$effort" in ""|minimal|low|medium|high|xhigh) ;; *) usage "geçersiz -E değeri: $effort" ;; esac
[[ "$tmo" =~ ^[0-9]+$ ]] || usage "geçersiz -t değeri: $tmo"
dir="$(realpath -e -- "$dir" 2>/dev/null)" || usage "dizin yok: $dir"
if [ -n "$schema" ]; then
  schema="$(realpath -e -- "$schema" 2>/dev/null)" || usage "şema dosyası yok"
fi

prompt="$(cat)"
[ -n "$prompt" ] || usage "stdin'den mesaj gelmedi"

work="$(mktemp -d "${TMPDIR:-/tmp}/codex-ask.XXXXXX")" || usage "geçici dizin oluşturulamadı"
keep_work=0
trap '[ "$keep_work" = 1 ] || rm -rf "$work"' EXIT

# Oturum id'sini, hangi Claude oturumunda açıldıysa onun listesine yazar (codex-threads.sh ile
# aynı kilit altında). Resume'da yalnız zaten takip edilen id'ler yazılır. Claude oturumu
# kapanmışsa (.ended) id doğrudan arşiv kuyruğuna (.ending) gider.
register() {
  [ "$ephemeral" = 1 ] && return
  local sid="${CLAUDE_CODE_SESSION_ID:-manual}" open="$DATA_DIR/open"
  sid="${sid//[^A-Za-z0-9._-]/_}"
  mkdir -p "$open" || return
  # Kilidi boşalana kadar bekle: kilidi tutan codex-threads.sh işlemlerinin her Codex çağrısı
  # 60 sn ile sınırlı. Kilit hiç alınamıyorsa (dosya açılamadı) takip dosyalarına dokunma.
  if ! { exec 8>"$DATA_DIR/.lock" && flock 8; }; then
    # Sahiplik doğrulanamadığı için resume'da arşiv komutu önerme (kullanıcının oturumu olabilir).
    if [ -n "$thread" ]; then
      echo "Uyarı: takip kilidi alınamadı; $1 için takip kaydı yapılamadı." >&2
    else
      echo "Uyarı: takip kilidi alınamadı; codex-loop'un yeni açtığı $1 listeye yazılamadı, elle arşivlemek için: codex archive $1" >&2
    fi
    return
  fi
  if [ -n "$thread" ] && ! grep -qsxF -- "$1" "$open"/*.ids "$open"/*.ending \
      && ! grep -qs -- "^$1	" "$DATA_DIR/archived.tsv"; then
    echo "Uyarı: $1 codex-loop'un açtığı bir oturum değil; takibe alınmadı, arşivlenmeyecek." >&2
  else
    local f="$open/$sid.ids"
    [ -e "$open/$sid.ended" ] && f="$open/$sid.ending"
    grep -qsxF -- "$1" "$open"/*.ids "$open"/*.ending || printf '%s\n' "$1" >>"$f"
  fi
  exec 8>&-
}

# Danışma çağrısında Codex'in sandbox dışında yazabilecek araçlarını kapat.
args=(--json --skip-git-repo-check
  -c 'sandbox_mode="read-only"' -c 'approval_policy="never"'
  --disable apps --disable plugins --disable computer_use
  --disable browser_use --disable in_app_browser --disable multi_agent
  -c 'mcp_servers.node_repl.enabled=false'
  -o "$work/last.txt")
[ -n "$model" ] && args+=(-m "$model")
[ -n "$effort" ] && args+=(-c "model_reasoning_effort=\"$effort\"")
[ -n "$schema" ] && args+=(--output-schema "$schema")
[ "$ephemeral" = 1 ] && args+=(--ephemeral)

if [ -n "$thread" ]; then
  cmd=("$CODEX_BIN" exec resume "${args[@]}" "$thread" -)
else
  cmd=("$CODEX_BIN" exec "${args[@]}" -C "$dir" -)
fi

cd "$dir" || usage "dizine girilemedi: $dir"

# id'yi thread.started gelir gelmez kaydet; akışın kalanını sonuna kadar oku (SIGPIPE olmasın).
printf '%s' "$prompt" | timeout --kill-after=10 "$tmo" "${cmd[@]}" 2>"$work/err.txt" | {
  found=0
  while IFS= read -r line; do
    printf '%s\n' "$line" >>"$work/events.jsonl"
    if [ "$found" = 0 ] && [[ "$line" == *'"thread.started"'* ]]; then
      id="$(jq -r '.thread_id // empty' <<<"$line" 2>/dev/null)"
      if [ -n "$id" ]; then
        register "$id"
        printf '%s' "$id" >"$work/tid"
        found=1
      fi
    fi
  done
}
status=${PIPESTATUS[1]}

tid="$(cat "$work/tid" 2>/dev/null)"
[ -n "$tid" ] || tid="$thread"

config_value() {
  sed -n "1,/^\[/{s/^$1 *= *\"\([^\"]*\)\".*/\1/p}" "$CODEX_HOME_DIR/config.toml" 2>/dev/null | head -1
}
shown_model="${model:-$(config_value model)}"
shown_effort="${effort:-$(config_value model_reasoning_effort)}"

if [ "$ephemeral" = 1 ]; then
  echo "CODEX_THREAD_ID: (ephemeral, kaydedilmedi)"
else
  echo "CODEX_THREAD_ID: ${tid:-(bilinmiyor)}"
fi
echo "CODEX_MODEL: ${shown_model:-varsayılan} (${shown_effort:-varsayılan})"
echo

[ -s "$work/last.txt" ] && { cat "$work/last.txt"; echo; }

fail() {
  keep_work=1
  echo "CODEX_ERROR: $2 — $3" >&2
  echo "Ayrıntılar: $work" >&2
  tail -n 15 "$work/err.txt" >&2 2>/dev/null
  exit "$1"
}

if [ "$status" = 124 ] || [ "$status" = 137 ]; then
  fail 124 TIMEOUT "Codex ${tmo} sn içinde bitmedi"
fi

if [ "$status" != 0 ] || ! grep -q '"turn.completed"' "$work/events.jsonl" 2>/dev/null || [ ! -s "$work/last.txt" ]; then
  diag="$(cat "$work/err.txt" 2>/dev/null; grep -E '"(error|turn.failed)"' "$work/events.jsonl" 2>/dev/null)"
  if grep -qiE 'rate.?limit|usage limit|too many requests|\b429\b|quota' <<<"$diag"; then
    fail 75 RATE_LIMIT "Codex kotası ya da hız sınırı doldu"
  elif grep -qiE 'unauthori[sz]ed|\b401\b|\b403\b|not logged in|log ?in again|authentication' <<<"$diag"; then
    fail 77 AUTH "Codex girişi geçersiz; terminalde 'codex login' gerekebilir"
  fi
  [ "$status" = 0 ] && status=1
  fail "$status" CODEX_FAILED "Codex cevabı tamamlanmadı (çıkış kodu $status)"
fi

if [ -n "$schema" ] && ! jq -e 'type == "object" and (.verdict | type == "string")' "$work/last.txt" >/dev/null 2>&1; then
  fail 65 SCHEMA "Cevap beklenen JSON şemasına uymuyor"
fi

exit 0
