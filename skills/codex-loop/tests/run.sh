#!/usr/bin/env bash
# codex-ask.sh ve codex-threads.sh testleri. Sahte codex kullanır; gerçek Codex çağrılmaz.
#   bash skills/codex-loop/tests/run.sh   (repo kökünden)

set -u
here="$(cd "$(dirname "$0")" && pwd)"
ask="$here/../codex-ask.sh"
threads="$here/../codex-threads.sh"
pass=0 failed=0
base_tmp="${TMPDIR:-/tmp}"

check() {
  local name="$1"; shift
  if "$@"; then pass=$((pass + 1)); echo "  ✓ $name"; else failed=$((failed + 1)); echo "  ✗ $name"; fi
}

setup() {
  T="$(mktemp -d "$base_tmp/codex-loop-test.XXXXXX")"
  export CODEX_BIN="$here/fake-codex" CODEX_LOOP_DATA="$T/data" CODEX_HOME="$T/codex-home" \
    FAKE_LOG="$T/calls.log" CLAUDE_CODE_SESSION_ID=S1 CODEX_LOOP_SYNC=1 TMPDIR="$T/tmp"
  unset FAKE_MODE FAKE_TID FAKE_ARCHIVE_FAIL
  mkdir -p "$CODEX_HOME" "$TMPDIR"
  printf 'model = "m-default"\nmodel_reasoning_effort = "high"\n[profile]\nmodel = "baska"\n' >"$CODEX_HOME/config.toml"
}
teardown() { rm -rf "$T"; }

ask() { out="$("$ask" "$@" 2>"$T/stderr")"; rc=$?; err="$(cat "$T/stderr")"; }
has() { grep -qF -- "$2" <<<"$1"; }
calls() { cat "$FAKE_LOG" 2>/dev/null; }
not() { ! "$@"; }

# "id:originator:archived" kayıtlarıyla sahte Codex veritabanı
mkdb() {
  python3 -I - "$CODEX_HOME/state_5.sqlite" "$@" <<'EOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table if not exists threads(id text primary key, originator text, archived int)")
for spec in sys.argv[2:]:
    i, o, a = spec.split(":")
    con.execute("insert or replace into threads values (?, ?, ?)", (i, o, int(a)))
con.commit()
EOF
}

echo "codex-ask.sh"

setup
ask <<<"soru"
check "başarılı cevap, çıkış 0"                 [ "$rc" = 0 ]
check "thread id ve cevap basılıyor"            has "$out" $'CODEX_THREAD_ID: T-new'
check "cevap metni"                             has "$out" "cevap"
check "varsayılan model config'den okunuyor"    has "$out" "CODEX_MODEL: m-default (high)"
check "id Claude oturumunun listesine yazıldı"  grep -qx T-new "$CODEX_LOOP_DATA/open/S1.ids"
check "salt okunur sandbox"                     has "$(calls)" 'sandbox_mode="read-only"'
check "approval_policy never"                   has "$(calls)" 'approval_policy="never"'
check "riskli özellikler kapalı"                has "$(calls)" "--disable apps --disable plugins --disable computer_use --disable browser_use --disable in_app_browser --disable multi_agent"
check "node_repl MCP kapalı"                     has "$(calls)" "mcp_servers.node_repl.enabled=false"
check "geçici dizin temizlendi"                 [ -z "$(ls -A "$TMPDIR")" ]
teardown

setup
ask -r YABANCI <<<"kullanıcının kendi oturumu"
check "resume: takip edilmeyen oturum yazılmadı"   [ ! -e "$CODEX_LOOP_DATA/open/S1.ids" ]
check "resume: takip edilmeyen için uyarı"         has "$err" "takibe alınmadı"
check "resume: takip edilmeyen yine de çalışıyor"  [ "$rc" = 0 ]
ask -w <<<"soru"
check "-w artık yok: kullanım hatası"              [ "$rc" = 2 ]
teardown

setup
mkdir -p "$CODEX_LOOP_DATA"
printf 'T-old\t%s\n' "$(date +%s)" >"$CODEX_LOOP_DATA/archived.tsv"
ask -r T-old -m m2 -E low <<<"devam"
check "resume: aynı id"                         has "$out" "CODEX_THREAD_ID: T-old"
check "resume: model ve seviye başlıkta"        has "$out" "CODEX_MODEL: m2 (low)"
check "resume: güvenlik ayarları da geçiyor"    has "$(calls)" "exec resume --json --skip-git-repo-check -c sandbox_mode=\"read-only\" -c approval_policy=\"never\" --disable apps"
check "resume: -m ve effort geçiyor"            has "$(calls)" '-m m2 -c model_reasoning_effort="low"'
check "resume: id listeye bir kez yazıldı"      [ "$(grep -cx T-old "$CODEX_LOOP_DATA/open/S1.ids")" = 1 ]
ask -r T-old <<<"bir tur daha"
check "aynı id tekrar yazılmıyor"               [ "$(grep -cx T-old "$CODEX_LOOP_DATA/open/S1.ids")" = 1 ]
teardown

setup
ask -e <<<"soru"
check "ephemeral: kaydedilmedi yazıyor"         has "$out" "ephemeral, kaydedilmedi"
check "ephemeral: listeye yazılmadı"            [ ! -e "$CODEX_LOOP_DATA/open/S1.ids" ]
check "ephemeral: --ephemeral geçiyor"          has "$(calls)" "--ephemeral"
ask -e -r X <<<"soru"
check "-e ile -r birlikte: kullanım hatası"     [ "$rc" = 2 ]
ask -E cok <<<"soru"
check "geçersiz -E: kullanım hatası"            [ "$rc" = 2 ]
ask </dev/null
check "boş mesaj: kullanım hatası"              [ "$rc" = 2 ]
teardown

setup
mkdir -p "$T/proje/alt"
out="$(cd "$T/proje" && "$ask" -C alt <<<"soru" 2>/dev/null)"
check "göreli -C mutlak yola çevriliyor"        has "$(calls)" "-C $T/proje/alt -"
check "Codex doğru dizinde çalışıyor"           [ "$(calls | cut -f1)" = "$T/proje/alt" ]
ask -C "$T/yok" <<<"soru"
check "olmayan dizin: kullanım hatası"          [ "$rc" = 2 ]
teardown

setup
FAKE_MODE=fail_with_answer ask <<<"soru"
check "hata kodu yutulmuyor"                    [ "$rc" = 1 ]
check "yarım cevap yine gösteriliyor"           has "$out" "yarım cevap"
check "CODEX_ERROR yazılıyor"                   has "$err" "CODEX_ERROR: CODEX_FAILED"
check "hatada ayrıntılar saklanıyor"            [ -n "$(ls -A "$TMPDIR")" ]
teardown

setup
FAKE_MODE=no_complete ask <<<"soru"
check "turn.completed yoksa hata"               [ "$rc" != 0 ]
teardown

setup
start=$(date +%s)
FAKE_MODE=timeout ask -t 1 <<<"soru"
check "zaman aşımı: çıkış 124"                  [ "$rc" = 124 ]
check "zaman aşımı: TIMEOUT mesajı"             has "$err" "CODEX_ERROR: TIMEOUT"
check "zaman aşımı: id yine de kaydedildi"      grep -qx T-new "$CODEX_LOOP_DATA/open/S1.ids"
check "zaman aşımı: beklemeden dönüyor"         [ $(( $(date +%s) - start )) -lt 10 ]
teardown

setup
FAKE_MODE=ratelimit ask <<<"soru"
check "rate limit: çıkış 75"                    [ "$rc" = 75 ]
FAKE_MODE=auth ask <<<"soru"
check "auth: çıkış 77"                          [ "$rc" = 77 ]
teardown

setup
echo '{}' >"$T/s.json"
FAKE_MODE=schema_ok ask -s "$T/s.json" <<<"soru"
check "şemaya uyan cevap: çıkış 0"              [ "$rc" = 0 ]
check "--output-schema geçiyor"                 has "$(calls)" "--output-schema $T/s.json"
FAKE_MODE=schema_bad ask -s "$T/s.json" <<<"soru"
check "şemaya uymayan cevap: çıkış 65"          [ "$rc" = 65 ]
teardown

echo "codex-threads.sh"

setup
mkdir -p "$CODEX_LOOP_DATA/open"
printf 'A1\nA2\nA3\nA4\n' >"$CODEX_LOOP_DATA/open/S1.ids"
mkdb A1:codex_exec:0 A2:codex_exec:1 A3:codex_exec:0 A4:codex_vscode:0
FAKE_ARCHIVE_FAIL="A3" "$threads" session-end <<<'{"session_id":"S1"}'
check "session-end: başarılı arşiv deftere girdi"    grep -q "^A1	" "$CODEX_LOOP_DATA/archived.tsv"
check "session-end: zaten arşivli olan başarılı"     grep -q "^A2	" "$CODEX_LOOP_DATA/archived.tsv"
check "session-end: başarısız olan bekliyor"         [ "$(cat "$CODEX_LOOP_DATA/open/S1.ending")" = "A3" ]
check "session-end: .ids dosyası kaldırıldı"         [ ! -e "$CODEX_LOOP_DATA/open/S1.ids" ]
check "session-end: kapandı işareti kondu"           [ -e "$CODEX_LOOP_DATA/open/S1.ended" ]
check "session-end: codex_exec olmayan arşivlenmedi" not has "$(calls)" "archive A4"
check "session-end: codex_exec olmayan deftere girmedi" not grep -q "^A4	" "$CODEX_LOOP_DATA/archived.tsv"
FAKE_TID=GEC ask <<<"oturum kapandıktan sonra gelen"
check "kapanmış oturumda yeni id kuyruğa gidiyor"    grep -qx GEC "$CODEX_LOOP_DATA/open/S1.ending"
check "kapanmış oturumda .ids yeniden oluşmuyor"     [ ! -e "$CODEX_LOOP_DATA/open/S1.ids" ]
"$threads" session-end <<<'{"session_id":"BASKA"}'
check "başka oturumun listesine dokunulmuyor"        [ -e "$CODEX_LOOP_DATA/open/S1.ending" ]
mkdb GEC:codex_exec:0
"$threads" session-start <<<'{"session_id":"S1"}'
check "session-start: bekleyen tekrar denendi"       [ ! -e "$CODEX_LOOP_DATA/open/S1.ending" ]
check "session-start: deftere girdi"                 grep -q "^A3	" "$CODEX_LOOP_DATA/archived.tsv"
check "session-start: geç gelen de arşivlendi"       grep -q "^GEC	" "$CODEX_LOOP_DATA/archived.tsv"
check "session-start (resume): işaret kaldırıldı"    [ ! -e "$CODEX_LOOP_DATA/open/S1.ended" ]
teardown

setup
mkdir -p "$CODEX_LOOP_DATA/open"
printf 'M1\nM2\nV1\n' >"$CODEX_LOOP_DATA/open/S1.ids"
mkdb M1:codex_exec:0 M2:codex_exec:0 V1:codex_vscode:0 KULLANICI:codex_vscode:0
"$threads" archive M1 >/dev/null
check "elle arşiv: deftere girdi"                    grep -q "^M1	" "$CODEX_LOOP_DATA/archived.tsv"
check "elle arşiv: açık listeden çıktı"              not grep -qx M1 "$CODEX_LOOP_DATA/open/S1.ids"
FAKE_ARCHIVE_FAIL=M2 "$threads" archive M2 >/dev/null 2>&1
check "elle arşiv başarısız: hata kodu"              [ $? = 1 ]
check "elle arşiv başarısız: listede kaldı"          grep -qx M2 "$CODEX_LOOP_DATA/open/S1.ids"
"$threads" archive KULLANICI >/dev/null 2>&1
check "takip edilmeyen id reddedildi"                [ $? = 1 ]
check "takip edilmeyen id'ye dokunulmadı"            not has "$(calls)" "archive KULLANICI"
"$threads" archive V1 >/dev/null
check "codex_exec olmayan id arşivlenmedi"           not has "$(calls)" "archive V1"
check "codex_exec olmayan id listeden çıktı"         not grep -qx V1 "$CODEX_LOOP_DATA/open/S1.ids"
exec 7>"$CODEX_LOOP_DATA/.lock"; flock 7
timeout 5 env CODEX_LOOP_LOCK_WAIT=1 "$threads" archive M2 >/dev/null 2>&1
lockrc=$?
exec 7>&-
check "kilit alınamazsa hata veriyor"                [ "$lockrc" != 0 ]
check "kilit alınamazsa listeye dokunulmuyor"        grep -qx M2 "$CODEX_LOOP_DATA/open/S1.ids"
teardown

setup
mkdir -p "$CODEX_LOOP_DATA"
old=$(( $(date +%s) - 31 * 86400 )); new=$(( $(date +%s) - 86400 ))
printf 'ESKI\t%s\nVSCODE\t%s\nYOK\t%s\nGERIALINDI\t%s\nYENI\t%s\n' "$old" "$old" "$old" "$old" "$new" >"$CODEX_LOOP_DATA/archived.tsv"
mkdb ESKI:codex_exec:1 VSCODE:codex_vscode:1 GERIALINDI:codex_exec:0 YENI:codex_exec:1
"$threads" session-start </dev/null
check "30 günü geçen kendi oturumumuz silindi"       has "$(calls)" "delete --force ESKI"
check "başka kaynaklı oturum silinmedi"              not has "$(calls)" "delete --force VSCODE"
check "arşivden geri alınan silinmedi"               not has "$(calls)" "delete --force GERIALINDI"
check "30 günü geçmeyen silinmedi"                   not has "$(calls)" "delete --force YENI"
check "defterde yalnız YENI kaldı"                   [ "$(cut -f1 "$CODEX_LOOP_DATA/archived.tsv")" = "YENI" ]
teardown

setup
mkdir -p "$CODEX_LOOP_DATA"
printf 'ESKI\t%s\n' $(( $(date +%s) - 31 * 86400 )) >"$CODEX_LOOP_DATA/archived.tsv"
"$threads" session-start </dev/null
check "veritabanı yoksa hiçbir şey silinmiyor"       not has "$(calls)" "delete"
check "veritabanı yoksa kayıt korunuyor"             grep -q "^ESKI	" "$CODEX_LOOP_DATA/archived.tsv"
teardown

setup
mkdir -p "$CODEX_LOOP_DATA/open"
mkdb B1:codex_exec:0 T-new:codex_exec:0
printf 'B1\n' >"$CODEX_LOOP_DATA/open/S1.ids"
( exec 7>"$CODEX_LOOP_DATA/.lock"; flock 7; sleep 2 ) &
sleep 0.3
ask <<<"kilit meşgulken yeni oturum"
check "register kilidi bekleyip yazdı"               grep -qx T-new "$CODEX_LOOP_DATA/open/S1.ids"
( exec 7>"$CODEX_LOOP_DATA/.lock"; flock 7; sleep 2 ) &
sleep 0.3
"$threads" session-end <<<'{"session_id":"S1"}'
check "session-end kilidi bekleyip arşivledi"        grep -q "^B1	" "$CODEX_LOOP_DATA/archived.tsv"
check "session-end: kilit beklemesinde id kaybolmadı" grep -q "^T-new	" "$CODEX_LOOP_DATA/archived.tsv"
wait
teardown

echo
echo "$pass geçti, $failed başarısız"
[ "$failed" = 0 ]
