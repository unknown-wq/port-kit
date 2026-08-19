#!/usr/bin/env bash
# Быстрая проверка типов без Gradle — для агентов, которым Gradle запрещён (контракт C4).
#
#   ../porting-26.2/typecheck.sh                 # все ошибки, уникальные, с текстом
#   ../porting-26.2/typecheck.sh network,event   # только свои пакеты
#   ../porting-26.2/typecheck.sh -c              # только счётчик
#
# Запускать из /home/user/Structurize/26.2.
#
# Оговорки:
#  - Берётся jar из loom-cache проекта, в котором AccessWidener УЖЕ применён (и наш
#    structurize.accesswidener, и транзитивные из fabric-api). Поэтому «has private access»
#    здесь настоящая ошибка, а не шум — в отличие от прогона по сырому deobf-jar.
#    Если такого jar ещё нет (Gradle ни разу не собирал проект), скрипт откатывается на сырой
#    и предупреждает: тогда ложные срабатывания возможны, сверяйся с structurize.accesswidener.
#  - Файлы, запаркованные под BlockUI (C9), исключены тем же набором масок, что и в build.gradle.
#  - Миксинов в моде нет (0 файлов), поэтому исключения по '*/mixin/*' не нужны.
#  - Это только проверка типов. Финальную правду говорит Gradle, и его гоняет оркестратор.
set -uo pipefail

JAVAC=/usr/lib/jvm/java-25-openjdk-amd64/bin/javac
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

# Запуск из чужого каталога давал бы пустой список файлов и "0 ошибок" — самый опасный
# из возможных ответов. Проверяем явно.
[ -d src/main/java/com/ldtteam/structurize ] || {
  echo "запускать из /home/user/Structurize/26.2 (сейчас: $PWD)" >&2; exit 1; }

# Loom кладёт в loom-cache проекта несколько ремапнутых jar'ов: сначала базовый (только
# транзитивные AW из fabric-api), потом — с применённым structurize.accesswidener. Нужен
# последний, он же самый новый по mtime.
MCJAR=$(find .gradle/loom-cache/minecraftMaven -name 'minecraft-merged-*26.2*.jar' \
        ! -name '*sources*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$MCJAR" ]; then
  MCJAR=$(find /root/.gradle ~/.gradle -path '*minecraftMaven*' -name 'minecraft-merged-*26.2*.jar' \
          ! -name '*sources*' 2>/dev/null | head -1)
  [ -n "$MCJAR" ] || { echo "minecraft jar не найден — скажи оркестратору" >&2; exit 1; }
  echo "ВНИМАНИЕ: jar с AccessWidener не найден, взят сырой $MCJAR." >&2
  echo "          'has private/protected access' может быть ложным — сверяйся с structurize.accesswidener." >&2
fi

CP=$(find /root/.gradle/caches/modules-2/files-2.1 ~/.gradle/caches/modules-2/files-2.1 \
        -name '*.jar' ! -name '*sources*' 2>/dev/null | tr '\n' ':')$MCJAR:libs/domum_ornamentum-26.2-1.0.0.jar

"$JAVAC" -nowarn -proc:none -Xmaxerrs 5000 --release 25 -cp "$CP" -d "$OUT" \
  $(find src/main/java -name '*.java' \
      ! -path '*/client/gui/Window*' \
      ! -path '*/client/gui/Abstract*' \
      ! -path '*/client/gui/util/InputFilters.java' \
      ! -path '*/client/gui/util/ItemUtil.java') \
  > "$OUT/log" 2>&1

# javac печатает ошибку и в поток, и в сводку — оставляем уникальные строки.
ERRORS=$(grep -E ':[0-9]+: error:' "$OUT/log" | sed 's|.*/com/ldtteam/structurize/|structurize/|' | sort -u)

if [ "${1:-}" = "-c" ]; then
  echo "$ERRORS" | grep -c .
  exit 0
fi

if [ -n "${1:-}" ]; then
  PATTERN="structurize/(${1//,/|})/"
  echo "$ERRORS" | grep -E "$PATTERN"
else
  echo "$ERRORS"
fi
