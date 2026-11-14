#!/usr/bin/env bash
# codex-loop'un açtığı Codex oturumlarını arşivler ve arşivden RETENTION gün sonra siler.
# Yalnız codex-ask.sh'nin listeye yazdığı ve Codex kaydında originator=codex_exec olan
# oturumlara dokunur; kullanıcının kendi Codex oturumları (terminal, masaüstü uygulaması,
# VS Code) hiçbir zaman listeye girmez.
#
# Kullanım:
#   codex-threads.sh archive <THREAD_ID>   iş bitince elle arşivle (yalnız takip edilen id)
#   codex-threads.sh list                  açık ve arşivli kayıtları göster
#   codex-threads.sh session-end           Claude Code SessionEnd hook'u (stdin: hook JSON)
#   codex-threads.sh session-start         Claude Code SessionStart hook'u (stdin: hook JSON)
#
# Veri: ~/.claude/codex-data/open/<claude-oturum>.ids    açık oturumlar
#       ~/.claude/codex-data/open/<claude-oturum>.ending kapanmış Claude oturumunun arşivlenecekleri
#       ~/.claude/codex-data/open/<claude-oturum>.ended  Claude oturumu kapandı işareti
#       ~/.claude/codex-data/archived.tsv                "<id>\t<arşiv zamanı (epoch)>"
# Tüm değişiklikler ~/.claude/codex-data/.lock altında yapılır (codex-ask.sh de aynı kilidi kullanır).

set -uo pipefail

CODEX_BIN="${CODEX_BIN:-codex}"
DATA_DIR="${CODEX_LOOP_DATA:-$HOME/.claude/codex-data}"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
RETENTION_DAYS="${CODEX_LOOP_RETENTION_DAYS:-30}"
OPEN="$DATA_DIR/open"
ARCHIVED="$DATA_DIR/archived.tsv"

mkdir -p "$OPEN"

# lock          → en fazla CODEX_LOOP_LOCK_WAIT (300) sn bekler
# lock forever  → kilit boşalana kadar bekler (kilidi tutan her Codex çağrısı 60 sn ile sınırlı)
lock() {
  exec 9>"$DATA_DIR/.lock" || return 1
  if [ "${1:-}" = forever ]; then flock 9; else flock -w "${CODEX_LOOP_LOCK_WAIT:-300}" 9; fi
}

session_id_from_stdin() {
  local sid
  sid="$(jq -r '.session_id // empty' 2>/dev/null)"
  printf '%s' "${sid//[^A-Za-z0-9._-]/_}"
}

# Codex'in kendi kaydından "<originator> <archived>" basar.
# Çıkış: 0 bulundu, 3 böyle bir oturum yok, 1 veritabanı okunamadı.
thread_info() {
  python3 -I - "$CODEX_HOME_DIR" "$1" <<'EOF'
import glob, os, re, sqlite3, sys
home, tid = sys.argv[1], sys.argv[2]
dbs = sorted(glob.glob(os.path.join(home, "state_*.sqlite")),
             key=lambda p: int(re.search(r"state_(\d+)\.sqlite$", p).group(1)))
if not dbs:
    sys.exit(1)
try:
    con = sqlite3.connect(f"file:{dbs[-1]}?mode=ro", uri=True)
    row = con.execute("select originator, archived from threads where id = ?", (tid,)).fetchone()
except sqlite3.Error:
    sys.exit(1)
if row is None:
    sys.exit(3)
print(row[0] or "-", row[1])
EOF
}

tracked_open() {
  grep -qsxF -- "$1" "$OPEN"/*.ids "$OPEN"/*.ending
}

untrack_open() {
  local f
  for f in "$OPEN"/*.ids "$OPEN"/*.ending; do
    [ -f "$f" ] && grep -qxF -- "$1" "$f" || continue
    grep -vxF -- "$1" "$f" >"$f.tmp"; mv "$f.tmp" "$f"
    [ -s "$f" ] || rm -f "$f"
  done
}

# 0 arşivlendi (ya da zaten arşivliydi), 2 oturum artık yok ya da bizim değil (listeden çık),
# 1 başarısız ya da doğrulanamadı (listede kalsın, sonra tekrar denensin).
archive_one() {
  local info rc
  info="$(thread_info "$1")"; rc=$?
  [ "$rc" = 3 ] && return 2
  [ "$rc" = 0 ] || return 1
  [ "${info% *}" = codex_exec ] || return 2
  [ "${info##* }" = 1 ] && return 0
  timeout --kill-after=10 60 "$CODEX_BIN" archive "$1" </dev/null >/dev/null 2>&1 && return 0
  info="$(thread_info "$1")" && [ "${info##* }" = 1 ] && return 0
  return 1
}

mark_archived() {
  touch "$ARCHIVED"
  { grep -v -- "^$1	" "$ARCHIVED"; printf '%s\t%s\n' "$1" "$(date +%s)"; } >"$ARCHIVED.tmp" && mv "$ARCHIVED.tmp" "$ARCHIVED"
}

# Bir .ending dosyasındaki id'leri arşivler; başarısızlar dosyada kalır. Kilit altında çağrılır.
drain() {
  local file="$1" id left=()
  [ -f "$file" ] || return 0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    archive_one "$id"
    case $? in
      0) mark_archived "$id" ;;
      2) ;;
      *) left+=("$id") ;;
    esac
  done <"$file"
  if [ "${#left[@]}" = 0 ]; then
    rm -f "$file"
  else
    printf '%s\n' "${left[@]}" >"$file.tmp" && mv "$file.tmp" "$file"
  fi
}

# Arşivde RETENTION günü geçenleri siler. Silmeden önce Codex kaydında oturumun
# codex exec ile açıldığı ve hâlâ arşivde olduğu doğrulanır. Kilit altında çağrılır.
purge() {
  [ -f "$ARCHIVED" ] || return 0
  local cutoff id ts info rc keep=()
  cutoff=$(( $(date +%s) - RETENTION_DAYS * 86400 ))
  while IFS=$'\t' read -r id ts; do
    [ -n "$id" ] || continue
    if [ "${ts:-0}" -gt "$cutoff" ]; then keep+=("$id	$ts"); continue; fi
    info="$(thread_info "$id")"; rc=$?
    case "$rc" in
      3) ;;                                   # Codex'te zaten yok: listeden çıkar
      0)
        if [ "$info" = "codex_exec 1" ]; then
          timeout --kill-after=10 60 "$CODEX_BIN" delete --force "$id" </dev/null >/dev/null 2>&1 || keep+=("$id	$ts")
        fi ;;                                 # başka kaynaklı ya da arşivden çıkarılmış: silme, listeden çıkar
      *) keep+=("$id	$ts") ;;                 # veritabanı okunamadı: dokunma, sonra tekrar dene
    esac
  done <"$ARCHIVED"
  if [ "${#keep[@]}" = 0 ]; then : >"$ARCHIVED"; else printf '%s\n' "${keep[@]}" >"$ARCHIVED.tmp" && mv "$ARCHIVED.tmp" "$ARCHIVED"; fi
}

# Hook'lar Claude Code'u bekletmesin diye işi arka plana bırakır.
detach() {
  if [ "${CODEX_LOOP_SYNC:-0}" = 1 ]; then "$0" "$@"; else setsid "$0" "$@" </dev/null >/dev/null 2>&1 & fi
}

case "${1:-}" in
  archive)
    id="${2:?THREAD_ID gerekli}"
    lock || { echo "Kilit alınamadı, hiçbir şey değiştirilmedi" >&2; exit 1; }
    if ! tracked_open "$id"; then
      if grep -q -- "^$id	" "$ARCHIVED" 2>/dev/null; then echo "Zaten arşivde: $id"; exit 0; fi
      echo "Takip edilmeyen oturum, dokunulmadı: $id" >&2; exit 1
    fi
    archive_one "$id"; rc=$?
    case "$rc" in
      0) mark_archived "$id"; untrack_open "$id"; echo "Arşivlendi: $id" ;;
      2) untrack_open "$id"; echo "Codex'te yok ya da codex-loop'a ait değil, listeden çıkarıldı: $id" ;;
      *) echo "Arşivlenemedi (listede kaldı, sonra tekrar denenecek): $id" >&2; exit 1 ;;
    esac ;;
  list)
    echo "Açık:"; cat "$OPEN"/*.ids "$OPEN"/*.ending 2>/dev/null | sed 's/^/  /'
    echo "Arşivde (silinme tarihi):"
    [ -f "$ARCHIVED" ] && while IFS=$'\t' read -r id ts; do
      echo "  $id  $(date -d "@$(( ts + RETENTION_DAYS * 86400 ))" +%F)"
    done <"$ARCHIVED" ;;
  session-end)
    sid="$(session_id_from_stdin)"
    [ -n "$sid" ] || exit 0
    detach _end "$sid" ;;
  session-start)
    sid="$(session_id_from_stdin)"
    detach _maintain "$sid" ;;
  _end)
    lock forever || exit 1
    touch "$OPEN/$2.ended"
    if [ -f "$OPEN/$2.ids" ]; then cat "$OPEN/$2.ids" >>"$OPEN/$2.ending" && rm -f "$OPEN/$2.ids"; fi
    drain "$OPEN/$2.ending" ;;
  _maintain)
    lock || exit 0
    [ -n "${2:-}" ] && rm -f "$OPEN/$2.ended"   # bu Claude oturumu açık (yeni ya da --resume)
    for f in "$OPEN"/*.ending; do [ -f "$f" ] && drain "$f"; done
    find "$OPEN" -name '*.ended' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
    purge ;;
  *)
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit 2 ;;
esac
