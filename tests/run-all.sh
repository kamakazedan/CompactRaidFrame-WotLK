#!/bin/bash
# Every check against ../CompactRaidFrame: syntax, the main suite in all nine
# locales, settings surviving a reload, upgrading from the original 1.15 (the
# first commit) and from the previous version, the original bug list, and
# incoming heals. Needs texlua (TeX Live's Lua) and Python 3.
cd "$(dirname "$0")" || exit 1
ADDON="$(cd ../CompactRaidFrame && pwd)" || exit 1
OUT="$(mktemp -d)"

texlua syncheck.lua $(find "$ADDON" -name '*.lua' -not -path '*/Libs/*') | tail -1
python3 xml2lua.py "$ADDON" "$OUT/xml.lua" >/dev/null || exit 1

for L in enUS deDE esES esMX frFR koKR ruRU zhCN zhTW; do
  CRF_LOCALE=$L texlua run.lua "$ADDON" "$OUT/xml.lua" all > "$OUT/run_$L.txt" 2>&1
  echo "$L: $(tail -1 "$OUT/run_$L.txt")"
  grep "FAIL" "$OUT/run_$L.txt" | head -5
done

texlua run.lua "$ADDON" "$OUT/xml.lua" persist-write "" "$OUT/sv_persist.lua" > "$OUT/persist_write.txt" 2>&1
texlua run.lua "$ADDON" "$OUT/xml.lua" persist-read "$OUT/sv_persist.lua" > "$OUT/persist_read.txt" 2>&1
echo "settings after a reload: $(tail -1 "$OUT/persist_read.txt")"
grep -h "FAIL" "$OUT/persist_write.txt" "$OUT/persist_read.txt" | head -5

# Upgrades: an older version saves its settings, this one loads them. From the
# original (first commit), and from the last committed version (or, with no
# uncommitted changes to the addon, the version before it).
if [ "$(git -C .. rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "upgrades: skipped in a shallow clone (git fetch --unshallow for the history)"
elif git -C .. rev-parse -q --verify HEAD >/dev/null 2>&1; then
  FIRST="$(git -C .. rev-list --max-parents=0 HEAD | tail -1)"
  if [ -n "$(git -C .. status --porcelain -- CompactRaidFrame)" ]; then
    PREV="$(git -C .. log -1 --format=%H -- CompactRaidFrame)"
  else
    PREV="$(git -C .. log -2 --format=%H -- CompactRaidFrame | tail -1)"
  fi
  for REF in $(printf '%s\n%s\n' "$FIRST" "$PREV" | awk '!seen[$0]++'); do
    OLD="$OUT/old-$REF"
    mkdir -p "$OLD"
    git -C .. archive "$REF" CompactRaidFrame | tar -x -C "$OLD" || continue
    python3 xml2lua.py "$OLD/CompactRaidFrame" "$OUT/xml_old.lua" >/dev/null || continue
    texlua run.lua "$OLD/CompactRaidFrame" "$OUT/xml_old.lua" upgrade-write "" "$OUT/sv_up.lua" > "$OUT/upgrade_write.txt" 2>&1
    texlua run.lua "$ADDON" "$OUT/xml.lua" upgrade-read "$OUT/sv_up.lua" > "$OUT/upgrade_read.txt" 2>&1
    echo "upgrade from $(sed -n 's/^## Version: *//p' "$OLD/CompactRaidFrame/CompactRaidFrame.toc" | tr -d '\r'): $(tail -1 "$OUT/upgrade_read.txt")"
    grep -h "FAIL" "$OUT/upgrade_read.txt" | head -5
  done
fi

texlua origbugs.lua "$ADDON" "$OUT/xml.lua" > "$OUT/origbugs.txt" 2>&1
echo "the original's bug list: $(grep -c ' fixed$' "$OUT/origbugs.txt") fixed, $(grep -c 'BUG PRESENT$' "$OUT/origbugs.txt") still present $(tail -1 "$OUT/origbugs.txt" | sed 's/^ *//')"
grep 'BUG PRESENT$' "$OUT/origbugs.txt" | head -5
echo "incoming heals: $(texlua healtest.lua "$ADDON" "$OUT/xml.lua" 2>&1 | tail -1)"
echo "(logs in $OUT)"
