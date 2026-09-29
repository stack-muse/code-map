#!/usr/bin/env bash
# inventory.sh <target-dir> — scripted, read-only facts pass over a local repo checkout.
# Prints a single markdown report to stdout covering: provenance, size/shape, source
# root, technology/versions, config shape (downstream URL keys), entry points,
# scheduling/messaging, entities/migrations, API specs, outbound clients, framework
# pitfalls, test posture and ownership. No cloning here — Step 1 of the code-map skill
# resolves and clones the target before calling this script on a local directory.
set -uo pipefail

TARGET="${1:-.}"
cd "$TARGET" || { echo "inventory.sh: cannot cd into '$TARGET'" >&2; exit 1; }
TARGET_ABS="$(pwd)"

# Directories we never want to walk into.
PRUNE_DIRS=(.git node_modules target build dist out .idea .gradle .mvn vendor .venv venv __pycache__ .next .nuxt coverage)

prune_expr() {
  local expr=()
  for d in "${PRUNE_DIRS[@]}"; do
    expr+=(-path "*/$d" -o)
  done
  unset 'expr[${#expr[@]}-1]'
  printf '%s\n' "${expr[@]}"
}

find_files() {
  # find_files <find-args...>  — applies the standard prune list first.
  # Appends "-print" unless the caller already supplied its own print action
  # (e.g. "-print0" for a null-safe pipe to xargs) — GNU find only adds a
  # default -print when no action appears anywhere in the expression, and
  # "-prune" already counts as one, so without this every call would go silent.
  local has_print=0
  for a in "$@"; do
    [[ "$a" == "-print0" || "$a" == "-print" ]] && has_print=1
  done
  if [[ "$has_print" -eq 1 ]]; then
    find . \( -path "./.git" -o -name node_modules -o -name target -o -name build -o -name dist -o -name out -o -name .idea -o -name .gradle -o -name .mvn -o -name vendor -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name .nuxt -o -name coverage \) -prune -o "$@" 2>/dev/null
  else
    find . \( -path "./.git" -o -name node_modules -o -name target -o -name build -o -name dist -o -name out -o -name .idea -o -name .gradle -o -name .mvn -o -name vendor -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name .nuxt -o -name coverage \) -prune -o "$@" -print 2>/dev/null
  fi
}

grep_src() {
  # grep_src <pattern> [extra grep args...] — recursive grep excluding noise dirs.
  local pattern="$1"; shift
  grep -rn "$@" \
    --include='*.java' --include='*.kt' --include='*.kts' --include='*.ts' --include='*.tsx' \
    --include='*.js' --include='*.jsx' --include='*.py' --include='*.go' --include='*.rb' \
    --include='*.scala' --include='*.cs' --include='*.php' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=target --exclude-dir=build \
    --exclude-dir=dist --exclude-dir=out --exclude-dir=.idea --exclude-dir=.gradle \
    --exclude-dir=.mvn --exclude-dir=vendor --exclude-dir=.venv --exclude-dir=venv \
    --exclude-dir=__pycache__ --exclude-dir=.next --exclude-dir=.nuxt --exclude-dir=coverage \
    -E "$pattern" . 2>/dev/null
}

section() { printf '\n## %s\n\n' "$1"; }

echo "# Inventory of $TARGET_ABS"
echo
echo "_Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)_"

# ---------------------------------------------------------------------------
section "Provenance"
if git -C "$TARGET_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REMOTE="$(git -C "$TARGET_ABS" remote get-url origin 2>/dev/null || echo 'not determined')"
  BRANCH="$(git -C "$TARGET_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not determined')"
  SHA="$(git -C "$TARGET_ABS" rev-parse HEAD 2>/dev/null || echo 'not determined')"
  COMMIT_DATE="$(git -C "$TARGET_ABS" log -1 --format=%cI 2>/dev/null || echo 'not determined')"
  echo "- Remote: $REMOTE"
  echo "- Branch: $BRANCH"
  echo "- HEAD: $SHA"
  echo "- Last commit date: $COMMIT_DATE"
  echo
  echo "Top committers, last 90 days (recent activity only, not overall ownership):"
  echo
  git -C "$TARGET_ABS" log --since="90 days ago" --format='%an' 2>/dev/null | sort | uniq -c | sort -rn | head -10 | sed 's/^/    /'
else
  echo "- Not a git repository (or git metadata unavailable)."
fi

# ---------------------------------------------------------------------------
section "Size and shape"
TOTAL_FILES=$(find_files -type f | wc -l)
echo "- Total tracked-type files (excluding build/vendor/.git): $TOTAL_FILES"
echo
echo "File count by extension (top 15):"
echo
find_files -type f -name '*.*' | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -15 | sed 's/^/    /'
echo
echo "Line counts for common source extensions:"
echo
for ext in java kt ts tsx js jsx py go rb scala cs php; do
  files=$(find_files -type f -name "*.${ext}")
  if [[ -n "$files" ]]; then
    lines=$(echo "$files" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    count=$(echo "$files" | grep -c .)
    echo "    .$ext: $count files, $lines lines"
  fi
done
echo
echo "Top-level directory shape:"
echo
find "$TARGET_ABS" -maxdepth 1 -mindepth 1 -type d ! -name .git | sed "s|$TARGET_ABS/||" | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "Source root"
echo "Candidate main source roots (src/main/* or equivalent):"
echo
find_files -type d \( -path '*/src/main/java' -o -path '*/src/main/kotlin' -o -path '*/src/main/resources' -o -path '*/src' -o -name 'lib' -o -name 'app' \) | sed "s|^\./||" | sort -u | head -20 | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "Technology and versions"
echo "Build/dependency manifests found:"
echo
find_files -maxdepth 3 -type f \( -name 'pom.xml' -o -name 'build.gradle' -o -name 'build.gradle.kts' -o -name 'package.json' -o -name 'go.mod' -o -name 'requirements.txt' -o -name 'Cargo.toml' -o -name '*.csproj' \) | sed "s|^\./||" | sort | sed 's/^/    /'

ROOT_POM="$TARGET_ABS/pom.xml"
if [[ -f "$ROOT_POM" ]]; then
  echo
  echo "Root pom.xml — key version properties:"
  echo
  grep -E '<(java|kotlin|spring[-.]boot|maven\.compiler)[^>]*\.version>' "$ROOT_POM" 2>/dev/null | sed 's/^\s*/    /' | head -20
  echo
  echo "Root pom.xml — declared modules:"
  echo
  grep -E '<module>' "$ROOT_POM" 2>/dev/null | sed -E 's/<\/?module>//g; s/^\s*/    /'
fi

ROOT_PKG="$TARGET_ABS/package.json"
if [[ -f "$ROOT_PKG" ]]; then
  echo
  echo "Root package.json — name/version/engines:"
  echo
  grep -E '"(name|version|engines)"' "$ROOT_PKG" 2>/dev/null | sed 's/^\s*/    /'
fi

# ---------------------------------------------------------------------------
section "Config shape (downstream URL keys)"
echo "Config files found:"
echo
find_files -type f \( -name 'application*.yml' -o -name 'application*.yaml' -o -name 'application*.properties' -o -name '*.env' -o -name '.env*' -o -name 'config.yml' -o -name 'config.yaml' \) | sed "s|^\./||" | sort | sed 's/^/    /'
echo
echo "Downstream-looking keys (url/host/endpoint/uri) in those files, name only (values may be secrets):"
echo
find_files -type f \( -name 'application*.yml' -o -name 'application*.yaml' -o -name 'application*.properties' -o -name 'config.yml' -o -name 'config.yaml' \) -print0 2>/dev/null | \
  xargs -0 grep -inE '(url|uri|host|endpoint)\s*[:=]' 2>/dev/null | sed 's/^/    /' | head -40

# ---------------------------------------------------------------------------
section "Entry points"
echo "HTTP controllers / mappings:"
echo
grep_src '@(RestController|Controller|RequestMapping|GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping)' | head -60 | sed 's/^/    /'
echo
echo "Route-style frameworks (Express/Flask/Fastify/etc.):"
echo
grep_src "(app\.(get|post|put|delete|patch)\(|@(app|router)\.(route|get|post|put|delete))" | head -30 | sed 's/^/    /'
echo
echo "Application entry points (main / SpringBootApplication):"
echo
grep_src '@SpringBootApplication|public static void main\(' | head -20 | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "Scheduling and messaging"
echo "Scheduled jobs:"
echo
grep_src '@Scheduled' | head -30 | sed 's/^/    /'
echo
echo "Messaging listeners/producers (Kafka/Rabbit/JMS):"
echo
grep_src '@(KafkaListener|RabbitListener|JmsListener)|KafkaTemplate|RabbitTemplate|JmsTemplate' | head -40 | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "Entities and migrations"
echo "JPA/ORM entities:"
echo
grep_src '@(Entity|Table)\b' | head -60 | sed 's/^/    /'
echo
echo "Migration files (Flyway/Liquibase/raw SQL):"
echo
find_files -type f \( -path '*db/migration*' -o -path '*migrations*' -o -name '*.sql' -o -name 'changelog*.xml' -o -name 'changelog*.yml' \) | sed "s|^\./||" | sort | head -60 | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "API specs"
find_files -type f \( -iname 'openapi*.yml' -o -iname 'openapi*.yaml' -o -iname 'openapi*.json' -o -iname 'swagger*.yml' -o -iname 'swagger*.yaml' -o -iname 'swagger*.json' -o -name '*.proto' \) | sed "s|^\./||" | sort | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "Outbound clients"
echo "HTTP/RPC client usage:"
echo
grep_src '(RestTemplate|WebClient|FeignClient|HttpClient|OkHttpClient|axios\.|fetch\(|requests\.(get|post|put|delete))' | head -50 | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "Framework pitfalls"
echo "Empty or log-only catch blocks (heuristic — verify at call site):"
echo
grep_src 'catch\s*\([^)]*\)\s*\{\s*\}' | head -20 | sed 's/^/    /'
echo
echo "TODO / FIXME clusters:"
echo
grep_src 'TODO|FIXME' -c 2>/dev/null | awk -F: '{sum+=$2} END{print "    total occurrences: " sum+0}'
grep_src 'TODO|FIXME' | head -30 | sed 's/^/    /'
echo
echo "Disabled/ignored tests:"
echo
grep_src '@(Disabled|Ignore)\b' | head -30 | sed 's/^/    /'

# ---------------------------------------------------------------------------
section "Test posture"
TEST_FILES=$(find_files -type f \( -path '*/test/*' -o -path '*/tests/*' -o -name '*Test.java' -o -name '*Tests.java' -o -name '*_test.py' -o -name 'test_*.py' -o -name '*.test.ts' -o -name '*.test.js' -o -name '*.spec.ts' -o -name '*.spec.js' \) | grep -c .)
echo "- Test-like files found: $TEST_FILES"
echo "- Main source files (see Size and shape above) for comparison."

# ---------------------------------------------------------------------------
section "Contacts and ownership"
if [[ -f "$TARGET_ABS/CODEOWNERS" ]]; then
  echo "CODEOWNERS:"
  echo
  sed 's/^/    /' "$TARGET_ABS/CODEOWNERS"
elif [[ -f "$TARGET_ABS/.github/CODEOWNERS" ]]; then
  echo "CODEOWNERS (.github/):"
  echo
  sed 's/^/    /' "$TARGET_ABS/.github/CODEOWNERS"
else
  echo "- No CODEOWNERS file found."
fi
echo
CATALOG_INFO=$(find_files -maxdepth 2 -iname 'catalog-info.yml' -o -iname 'catalog-info.yaml' 2>/dev/null | head -1)
if [[ -n "${CATALOG_INFO:-}" ]]; then
  echo "catalog-info owner field ($CATALOG_INFO):"
  echo
  grep -i 'owner' "$TARGET_ABS/$CATALOG_INFO" 2>/dev/null | sed 's/^/    /'
fi
if git -C "$TARGET_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo
  echo "All-time top committers (git shortlog):"
  echo
  git -C "$TARGET_ABS" shortlog -sn --all 2>/dev/null | head -10 | sed 's/^/    /'
fi

echo
echo "---"
echo "_End of scripted inventory. This is a mechanical scan (grep/find heuristics) —_"
echo "_verify anything load-bearing at its call site before writing it into the map._"
