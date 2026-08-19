#!/usr/bin/env bash
# Пересобирает PORTING-BUNDLE-26.2.md: части I–VIII (guides/) остаются как есть,
# части IX–X (промпты и шаблоны) приклеиваются из prompts/ и templates/.
#
# Части I–VIII правятся в guides/ и переносятся в бандл вручную: там текст слегка
# отредактирован под сплошное чтение (заголовки «Часть N. …»). Этот скрипт трогает
# ТОЛЬКО хвост начиная с маркера ниже, поэтому запускать его безопасно.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

MARKER='<!-- BUNDLE-APPENDIX-START -->'
BUNDLE=PORTING-BUNDLE-26.2.md
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

# Отрезаем старый хвост, если он уже был приклеен
if grep -qF "$MARKER" "$BUNDLE"; then
  sed "/$(printf '%s' "$MARKER" | sed 's/[][\.*^$/]/\\&/g')/,\$d" "$BUNDLE" > "$TMP"
else
  cat "$BUNDLE" > "$TMP"
fi

{
  echo "$MARKER"
  echo
  echo '---'
  echo
  echo '# Часть IX. Промпты для агентов'
  echo
  echo 'Отдельными файлами — в `prompts/`. Порядок: оркестратор нанимает A, затем параллельно'
  echo 'B/C/D, затем интегратора, затем свипера по списку ошибок.'
  for f in prompts/00-ORCHESTRATOR.md prompts/01-AGENT-A-core.md prompts/02-AGENT-B-logic.md \
           prompts/03-AGENT-C-client.md prompts/04-AGENT-D-datagen.md \
           prompts/05-AGENT-INTEGRATOR.md prompts/06-SWEEPER.md prompts/07-WEB-RECHECK.md; do
    echo; echo '---'; echo
    sed '1s/^# /## /' "$f"
  done
  echo; echo '---'; echo
  echo '# Часть X. Шаблоны документов порта'
  echo
  echo 'Отдельными файлами — в `templates/`.'
  for f in templates/PORT-STATUS-TEMPLATE.md templates/PORT-GAPS-TEMPLATE.md \
           templates/FINDINGS-TEMPLATE.md templates/AGENT-REPORT-TEMPLATE.md; do
    echo; echo '---'; echo
    sed '1s/^# /## /' "$f"
  done
} >> "$TMP"

mv "$TMP" "$BUNDLE"; trap - EXIT
echo "$BUNDLE: $(wc -l < "$BUNDLE") строк"
