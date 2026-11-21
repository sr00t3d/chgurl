#!/usr/bin/env bash
# ==============================================================================
#  chgurl.sh — Multi-CMS URL & Domain Changer CLI
# ==============================================================================
#  Author       : Percio Castelo (Percio Andrade) <percio@perciocastelo.com.br>
#  Contributors : Jose Terra, Leonardo Bolsoni (original 2012 beta)
#  Website      : https://perciocastelo.com.br
#  Project      : https://perciocastelo.com.br/projetos/en/chgurl.html
#  Repo         : https://github.com/sr00t3d/chgurl
#  License      : Apache-2.0
#  Version      : 2.0.0
# ==============================================================================

set -uo pipefail

readonly SCRIPT_NAME="chgurl.sh"
readonly SCRIPT_VERSION="2.0.0"

# Runtime options
CMS_TYPE="auto"           # auto | wordpress | magento | joomla | prestashop | whmcs | drupal
TARGET_DIR="."
NEW_DOMAIN=""
OLD_URL_OVERRIDE=""
SCHEME="https"
USE_CPANEL_DOMAIN=0
BACKUP_DIR=""
SKIP_BACKUP=0
AUTO_YES=0
DRY_RUN=0
FORMAT="table"
QUIET=0
NO_COLOR=0

# Internal state
CNF_TMP=""
TIMESTAMP_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
DETECTED_CMS=""
CONFIG_FILE=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST="localhost"
DB_PREFIX=""
CURRENT_URL=""
TARGET_URL=""
BACKUP_PATH=""
ROWS_AFFECTED=0
STATUS_MSG=""

# Colors
RED="" GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""
OK="[OK]" ATT="[!]" FAIL="[ERR]"

cleanup() {
  [[ -n "$CNF_TMP" && -f "$CNF_TMP" ]] && rm -f "$CNF_TMP"
}
trap cleanup EXIT

init_colors() {
  if [[ "$NO_COLOR" -eq 0 && -t 1 && -z "${NO_COLOR:-}" && "$FORMAT" == "table" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
    OK="${GREEN}[OK]${RESET}"
    ATT="${YELLOW}[!]${RESET}"
    FAIL="${RED}[ERR]${RESET}"
  else
    RED="" GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""
    OK="[OK]" ATT="[!]" FAIL="[ERR]"
  fi
}

show_help() {
  cat <<'USAGE'
chgurl.sh v2.0.0 — Multi-CMS URL & Domain Changer CLI
Original 2012 concept by Percio Andrade with contributors Jose Terra & Leonardo Bolsoni.

Usage:
  chgurl.sh [CMS flag] [options] <new-domain-or-url>
  chgurl.sh --auto --domain [--dry-run]

CMS Selection (default: --auto):
  --auto                     Auto-detect CMS in target directory
  -w, --wordpress            WordPress (wp-config.php + MySQL/MariaDB)
  -m, --magento              Magento 1 (app/etc/local.xml) & Magento 2 (app/etc/env.php)
  -j, --joomla               Joomla (configuration.php $live_site)
  -p, --prestashop           PrestaShop 1.6 (settings.inc.php) & 1.7/8 (parameters.php)
  -s, --whmcs                WHMCS (configuration.php + tblconfiguration)
  -l, --drupal               Drupal 7 ($base_url) & Drupal 8/9/10 (trusted_host_patterns)

Options:
  --dir <path>               CMS root directory (default: current directory)
  -d, --domain               Auto-detect primary domain from cPanel /etc/trueuserdomains
  --old-url <url>            Override detected old URL (WordPress search/replace)
  --scheme <https|http>      Target URL scheme (default: https)
  --backup-dir <dir>         Directory for chmod 600 SQL/config backups (default: /tmp)
  --skip-backup              Skip automatic backup before modifying DB/config
  -y, --yes                  Skip interactive confirmation prompt
  --dry-run                  Inspect config/DB and preview changes without modifying anything
  -o, --output <fmt>         Output format: table (default), json, csv
  -q, --quiet                Suppress banner header
  --no-color                 Disable ANSI colors
  -V, --version              Show version and exit
  -h, --help                 Show this help and exit

Examples:
  chgurl.sh -w --dir /home/user/public_html --dry-run newdomain.com
  chgurl.sh --auto --yes https://shop.example.com
  chgurl.sh -m --dir /var/www/magento --scheme https --yes store.example.com
  chgurl.sh -j --dir /var/www/joomla --yes portal.example.com
  chgurl.sh -s --dir /var/www/whmcs --dry-run -o json billing.example.com
USAGE
}

normalize_target() {
  local raw="$1"
  if [[ "$raw" == https://* ]]; then
    SCHEME="https"
    raw="${raw#https://}"
  elif [[ "$raw" == http://* ]]; then
    SCHEME="http"
    raw="${raw#http://}"
  fi
  raw="${raw%/}"
  raw="${raw,,}"
  NEW_DOMAIN="$raw"
  TARGET_URL="${SCHEME}://${NEW_DOMAIN}"
}

validate_domain() {
  local host="${NEW_DOMAIN%%/*}"
  host="${host%%:*}"
  if [[ -z "$host" || "${#host}" -gt 253 ]] || \
     ! printf '%s' "$host" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*(\.[a-z]{2,})?$'; then
    printf '%s Invalid target domain/URL: %s\n' "$FAIL" "${NEW_DOMAIN:-<empty>}" >&2
    exit 1
  fi
}

detect_cpanel_domain() {
  if [[ ! -r /etc/trueuserdomains ]]; then
    printf '%s /etc/trueuserdomains not found (not a cPanel host). Provide the domain as an argument.\n' "$FAIL" >&2
    exit 1
  fi
  local abs_dir user dom
  abs_dir="$(cd "$TARGET_DIR" && pwd)"
  user="$(printf '%s' "$abs_dir" | cut -d/ -f3)"
  dom="$(awk -F: -v u="$user" '{gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 == u) {print $1; exit}}' /etc/trueuserdomains 2>/dev/null || true)"
  if [[ -z "$dom" ]]; then
    printf '%s Could not resolve cPanel domain for user "%s" in /etc/trueuserdomains.\n' "$FAIL" "$user" >&2
    exit 1
  fi
  normalize_target "$dom"
}

detect_cms() {
  if [[ "$CMS_TYPE" != "auto" ]]; then
    DETECTED_CMS="$CMS_TYPE"
    return 0
  fi
  if [[ -f "${TARGET_DIR}/wp-config.php" ]]; then
    DETECTED_CMS="wordpress"
  elif [[ -f "${TARGET_DIR}/app/etc/env.php" || -f "${TARGET_DIR}/app/etc/local.xml" ]]; then
    DETECTED_CMS="magento"
  elif [[ -f "${TARGET_DIR}/app/config/parameters.php" || -f "${TARGET_DIR}/config/settings.inc.php" ]]; then
    DETECTED_CMS="prestashop"
  elif [[ -f "${TARGET_DIR}/sites/default/settings.php" ]]; then
    DETECTED_CMS="drupal"
  elif [[ -f "${TARGET_DIR}/configuration.php" ]]; then
    if grep -q '\$db_name' "${TARGET_DIR}/configuration.php" 2>/dev/null; then
      DETECTED_CMS="whmcs"
    else
      DETECTED_CMS="joomla"
    fi
  else
    printf '%s Could not auto-detect CMS in %s. Specify -w|-m|-j|-p|-s|-l.\n' "$FAIL" "$TARGET_DIR" >&2
    exit 1
  fi
}

sql_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\'\'}"
  printf '%s' "$s"
}

cnf_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

setup_mysql_cnf() {
  if ! command -v mysql >/dev/null 2>&1; then
    printf '%s Required command "mysql" not found.\n' "$FAIL" >&2
    exit 1
  fi
  if [[ -n "$DB_USER" ]]; then
    CNF_TMP="$(mktemp)"
    chmod 600 "$CNF_TMP"
    {
      printf '[client]\n'
      printf 'user="%s"\n' "$(cnf_escape "$DB_USER")"
      [[ -n "$DB_PASS" ]] && printf 'password="%s"\n' "$(cnf_escape "$DB_PASS")"
      printf 'host="%s"\n' "$(cnf_escape "${DB_HOST%%:*}")"
      if [[ "$DB_HOST" == *:* ]]; then
        printf 'port=%s\n' "${DB_HOST##*:}"
      fi
    } > "$CNF_TMP"
  fi
}

run_mysql() {
  local query="$1"
  if [[ -n "$CNF_TMP" ]]; then
    mysql --defaults-extra-file="$CNF_TMP" --batch --skip-column-names "$DB_NAME" -e "$query"
  else
    mysql --batch --skip-column-names "$DB_NAME" -e "$query"
  fi
}

backup_database() {
  [[ "$SKIP_BACKUP" -eq 1 || "$DRY_RUN" -eq 1 ]] && return 0
  command -v mysqldump >/dev/null 2>&1 || { printf '%s mysqldump not found; skipping SQL backup.\n' "$ATT" >&2; return 0; }
  local bdir="${BACKUP_DIR:-/tmp}"
  local ts
  ts="$(date -u '+%Y%m%d-%H%M%S')"
  BACKUP_PATH="${bdir}/chgurl-${DETECTED_CMS}-${DB_NAME}-${ts}.sql.gz"
  (
    umask 077
    mkdir -p "$bdir"
    if [[ -n "$CNF_TMP" ]]; then
      mysqldump --defaults-extra-file="$CNF_TMP" --single-transaction --quick "$DB_NAME" | gzip -9 > "$BACKUP_PATH"
    else
      mysqldump --single-transaction --quick "$DB_NAME" | gzip -9 > "$BACKUP_PATH"
    fi
    chmod 600 "$BACKUP_PATH"
  )
}

backup_file() {
  local src="$1"
  [[ "$SKIP_BACKUP" -eq 1 || "$DRY_RUN" -eq 1 ]] && return 0
  local bdir="${BACKUP_DIR:-/tmp}"
  local ts base
  ts="$(date -u '+%Y%m%d-%H%M%S')"
  base="$(basename "$src")"
  BACKUP_PATH="${bdir}/chgurl-${DETECTED_CMS}-${base}.${ts}.bak"
  (
    umask 077
    mkdir -p "$bdir"
    cp -p "$src" "$BACKUP_PATH"
    chmod 600 "$BACKUP_PATH"
  )
}

confirm_action() {
  [[ "$DRY_RUN" -eq 1 || "$AUTO_YES" -eq 1 ]] && return 0
  local ans=""
  read -r -p "Proceed changing ${DETECTED_CMS} URL (${CURRENT_URL:-unknown} -> ${TARGET_URL})? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    printf '%s Aborted by user.\n' "$ATT"
    exit 0
  fi
}

# ─── CMS Handlers ─────────────────────────────────────────────────────────────

handle_wordpress() {
  CONFIG_FILE="${TARGET_DIR}/wp-config.php"
  [[ -r "$CONFIG_FILE" ]] || { printf '%s wp-config.php not found in %s\n' "$FAIL" "$TARGET_DIR" >&2; exit 1; }

  DB_NAME="$(sed -nE "s/.*define\(\s*['\"]DB_NAME['\"]\s*,\s*['\"]([^'\"]+)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_USER="$(sed -nE "s/.*define\(\s*['\"]DB_USER['\"]\s*,\s*['\"]([^'\"]+)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_PASS="$(sed -nE "s/.*define\(\s*['\"]DB_PASSWORD['\"]\s*,\s*['\"]([^'\"]*)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_HOST="$(sed -nE "s/.*define\(\s*['\"]DB_HOST['\"]\s*,\s*['\"]([^'\"]+)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_PREFIX="$(sed -nE "s/.*\\\$table_prefix\s*=\s*['\"]([^'\"]+)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_HOST="${DB_HOST:-localhost}"
  DB_PREFIX="${DB_PREFIX:-wp_}"

  [[ -n "$DB_NAME" ]] || { printf '%s Could not parse DB_NAME from %s\n' "$FAIL" "$CONFIG_FILE" >&2; exit 1; }
  setup_mysql_cnf

  CURRENT_URL="${OLD_URL_OVERRIDE:-$(run_mysql "SELECT option_value FROM \`${DB_PREFIX}options\` WHERE option_name='siteurl' LIMIT 1;" 2>/dev/null || true)}"
  CURRENT_URL="${CURRENT_URL%/}"
  [[ -n "$CURRENT_URL" ]] || { printf '%s Could not read siteurl from %soptions.\n' "$FAIL" "$DB_PREFIX" >&2; exit 1; }

  local old_esc new_esc
  old_esc="$(sql_escape "$CURRENT_URL")"
  new_esc="$(sql_escape "$TARGET_URL")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    ROWS_AFFECTED="$(run_mysql "
      SELECT
        (SELECT COUNT(*) FROM \`${DB_PREFIX}options\` WHERE option_value LIKE '%${old_esc}%') +
        (SELECT COUNT(*) FROM \`${DB_PREFIX}posts\` WHERE guid LIKE '%${old_esc}%' OR post_content LIKE '%${old_esc}%') +
        (SELECT COUNT(*) FROM \`${DB_PREFIX}postmeta\` WHERE meta_value LIKE '%${old_esc}%') +
        (SELECT COUNT(*) FROM \`${DB_PREFIX}comments\` WHERE comment_content LIKE '%${old_esc}%');
    ")"
    STATUS_MSG="dry-run-preview"
    return 0
  fi

  confirm_action
  backup_database
  ROWS_AFFECTED="$(run_mysql "
    UPDATE \`${DB_PREFIX}options\` SET option_value = REPLACE(option_value, '${old_esc}', '${new_esc}') WHERE option_name IN ('siteurl', 'home');
    SET @r1 = ROW_COUNT();
    UPDATE \`${DB_PREFIX}posts\` SET guid = REPLACE(guid, '${old_esc}', '${new_esc}') WHERE guid LIKE '%${old_esc}%';
    SET @r2 = ROW_COUNT();
    UPDATE \`${DB_PREFIX}posts\` SET post_content = REPLACE(post_content, '${old_esc}', '${new_esc}') WHERE post_content LIKE '%${old_esc}%';
    SET @r3 = ROW_COUNT();
    UPDATE \`${DB_PREFIX}postmeta\` SET meta_value = REPLACE(meta_value, '${old_esc}', '${new_esc}') WHERE meta_value LIKE '%${old_esc}%';
    SET @r4 = ROW_COUNT();
    UPDATE \`${DB_PREFIX}comments\` SET comment_content = REPLACE(comment_content, '${old_esc}', '${new_esc}') WHERE comment_content LIKE '%${old_esc}%';
    SET @r5 = ROW_COUNT();
    SELECT @r1 + @r2 + @r3 + @r4 + @r5;
  ")"
  STATUS_MSG="updated"
}

handle_magento() {
  if [[ -r "${TARGET_DIR}/app/etc/env.php" ]]; then
    CONFIG_FILE="${TARGET_DIR}/app/etc/env.php"
    DB_NAME="$(sed -nE "s/.*'dbname'\s*=>\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_USER="$(sed -nE "s/.*'username'\s*=>\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_PASS="$(sed -nE "s/.*'password'\s*=>\s*'([^']*)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_HOST="$(sed -nE "s/.*'host'\s*=>\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_PREFIX="$(sed -nE "s/.*'table_prefix'\s*=>\s*'([^']*)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
  elif [[ -r "${TARGET_DIR}/app/etc/local.xml" ]]; then
    CONFIG_FILE="${TARGET_DIR}/app/etc/local.xml"
    DB_NAME="$(sed -nE 's/.*<dbname><!\[CDATA\[([^]]+)\]\]><\/dbname>.*/\1/p' "$CONFIG_FILE" | head -n1)"
    DB_USER="$(sed -nE 's/.*<username><!\[CDATA\[([^]]+)\]\]><\/username>.*/\1/p' "$CONFIG_FILE" | head -n1)"
    DB_PASS="$(sed -nE 's/.*<password><!\[CDATA\[([^]]*)\]\]><\/password>.*/\1/p' "$CONFIG_FILE" | head -n1)"
    DB_HOST="$(sed -nE 's/.*<host><!\[CDATA\[([^]]+)\]\]><\/host>.*/\1/p' "$CONFIG_FILE" | head -n1)"
    DB_PREFIX="$(sed -nE 's/.*<table_prefix><!\[CDATA\[([^]]*)\]\]><\/table_prefix>.*/\1/p' "$CONFIG_FILE" | head -n1)"
  else
    printf '%s Magento config (app/etc/env.php or app/etc/local.xml) not found in %s\n' "$FAIL" "$TARGET_DIR" >&2
    exit 1
  fi

  DB_HOST="${DB_HOST:-localhost}"
  [[ -n "$DB_NAME" ]] || { printf '%s Could not parse Magento database name from %s\n' "$FAIL" "$CONFIG_FILE" >&2; exit 1; }
  setup_mysql_cnf

  CURRENT_URL="$(run_mysql "SELECT value FROM \`${DB_PREFIX}core_config_data\` WHERE path='web/unsecure/base_url' LIMIT 1;" 2>/dev/null || true)"
  local target_slash="${TARGET_URL}/"
  local new_esc
  new_esc="$(sql_escape "$target_slash")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    ROWS_AFFECTED="$(run_mysql "SELECT COUNT(*) FROM \`${DB_PREFIX}core_config_data\` WHERE path IN ('web/unsecure/base_url','web/secure/base_url');")"
    STATUS_MSG="dry-run-preview"
    return 0
  fi

  confirm_action
  backup_database
  ROWS_AFFECTED="$(run_mysql "
    UPDATE \`${DB_PREFIX}core_config_data\` SET value='${new_esc}' WHERE path IN ('web/unsecure/base_url','web/secure/base_url');
    SELECT ROW_COUNT();
  ")"
  [[ -d "${TARGET_DIR}/var/cache" ]] && rm -rf "${TARGET_DIR}/var/cache/"*
  [[ -d "${TARGET_DIR}/var/session" ]] && rm -rf "${TARGET_DIR}/var/session/"*
  STATUS_MSG="updated"
}

handle_prestashop() {
  if [[ -r "${TARGET_DIR}/app/config/parameters.php" ]]; then
    CONFIG_FILE="${TARGET_DIR}/app/config/parameters.php"
    DB_NAME="$(sed -nE "s/.*'database_name'\s*=>\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_USER="$(sed -nE "s/.*'database_user'\s*=>\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_PASS="$(sed -nE "s/.*'database_password'\s*=>\s*'([^']*)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_HOST="$(sed -nE "s/.*'database_host'\s*=>\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_PREFIX="$(sed -nE "s/.*'database_prefix'\s*=>\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
  elif [[ -r "${TARGET_DIR}/config/settings.inc.php" ]]; then
    CONFIG_FILE="${TARGET_DIR}/config/settings.inc.php"
    DB_NAME="$(sed -nE "s/.*define\(\s*'_DB_NAME_'\s*,\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_USER="$(sed -nE "s/.*define\(\s*'_DB_USER_'\s*,\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_PASS="$(sed -nE "s/.*define\(\s*'_DB_PASSWD_'\s*,\s*'([^']*)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_HOST="$(sed -nE "s/.*define\(\s*'_DB_SERVER_'\s*,\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
    DB_PREFIX="$(sed -nE "s/.*define\(\s*'_DB_PREFIX_'\s*,\s*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
  else
    printf '%s PrestaShop config not found in %s\n' "$FAIL" "$TARGET_DIR" >&2
    exit 1
  fi

  DB_HOST="${DB_HOST:-localhost}"
  DB_PREFIX="${DB_PREFIX:-ps_}"
  [[ -n "$DB_NAME" ]] || { printf '%s Could not parse PrestaShop database name.\n' "$FAIL" >&2; exit 1; }
  setup_mysql_cnf

  CURRENT_URL="$(run_mysql "SELECT value FROM \`${DB_PREFIX}configuration\` WHERE name='PS_SHOP_DOMAIN' LIMIT 1;" 2>/dev/null || true)"
  local dom_only="${NEW_DOMAIN%%/*}"
  local dom_esc
  dom_esc="$(sql_escape "$dom_only")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    ROWS_AFFECTED="$(run_mysql "SELECT COUNT(*) FROM \`${DB_PREFIX}configuration\` WHERE name IN ('PS_SHOP_DOMAIN','PS_SHOP_DOMAIN_SSL');")"
    STATUS_MSG="dry-run-preview"
    return 0
  fi

  confirm_action
  backup_database
  ROWS_AFFECTED="$(run_mysql "
    UPDATE \`${DB_PREFIX}configuration\` SET value='${dom_esc}' WHERE name IN ('PS_SHOP_DOMAIN','PS_SHOP_DOMAIN_SSL');
    SET @r1 = ROW_COUNT();
    UPDATE \`${DB_PREFIX}shop_url\` SET domain='${dom_esc}', domain_ssl='${dom_esc}';
    SET @r2 = ROW_COUNT();
    SELECT @r1 + @r2;
  ")"
  STATUS_MSG="updated"
}

handle_whmcs() {
  CONFIG_FILE="${TARGET_DIR}/configuration.php"
  [[ -r "$CONFIG_FILE" ]] || { printf '%s WHMCS configuration.php not found in %s\n' "$FAIL" "$TARGET_DIR" >&2; exit 1; }

  DB_NAME="$(sed -nE "s/.*\\\$db_name\s*=\s*['\"]([^'\"]+)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_USER="$(sed -nE "s/.*\\\$db_username\s*=\s*['\"]([^'\"]+)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_PASS="$(sed -nE "s/.*\\\$db_password\s*=\s*['\"]([^'\"]*)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_HOST="$(sed -nE "s/.*\\\$db_host\s*=\s*['\"]([^'\"]+)['\"].*/\1/p" "$CONFIG_FILE" | head -n1)"
  DB_HOST="${DB_HOST:-localhost}"
  [[ -n "$DB_NAME" ]] || { printf '%s Could not parse $db_name from %s\n' "$FAIL" "$CONFIG_FILE" >&2; exit 1; }
  setup_mysql_cnf

  CURRENT_URL="$(run_mysql "SELECT value FROM tblconfiguration WHERE setting='SystemURL' LIMIT 1;" 2>/dev/null || true)"
  local url_slash="${TARGET_URL}/"
  local dom_esc url_esc
  dom_esc="$(sql_escape "$TARGET_URL")"
  url_esc="$(sql_escape "$url_slash")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    ROWS_AFFECTED="$(run_mysql "SELECT COUNT(*) FROM tblconfiguration WHERE setting IN ('Domain','SystemURL');")"
    STATUS_MSG="dry-run-preview"
    return 0
  fi

  confirm_action
  backup_database
  ROWS_AFFECTED="$(run_mysql "
    UPDATE tblconfiguration SET value='${dom_esc}' WHERE setting='Domain';
    SET @r1 = ROW_COUNT();
    UPDATE tblconfiguration SET value='${url_esc}' WHERE setting='SystemURL';
    SET @r2 = ROW_COUNT();
    SELECT @r1 + @r2;
  ")"
  STATUS_MSG="updated"
}

handle_joomla() {
  CONFIG_FILE="${TARGET_DIR}/configuration.php"
  [[ -r "$CONFIG_FILE" ]] || { printf '%s Joomla configuration.php not found in %s\n' "$FAIL" "$TARGET_DIR" >&2; exit 1; }

  CURRENT_URL="$(sed -nE "s/.*public\s+\\\$live_site\s*=\s*'([^']*)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    ROWS_AFFECTED=1
    STATUS_MSG="dry-run-preview"
    return 0
  fi

  confirm_action
  backup_file "$CONFIG_FILE"
  local tmpf
  tmpf="$(mktemp)"
  awk -v target="$TARGET_URL" '
    /public[[:space:]]+\$live_site[[:space:]]*=/ {
      sub(/\$live_site[[:space:]]*=[[:space:]]*\x27[^\x27]*\x27/, "$live_site = \x27" target "\x27")
    }
    { print }
  ' "$CONFIG_FILE" > "$tmpf"
  cat "$tmpf" > "$CONFIG_FILE"
  rm -f "$tmpf"
  ROWS_AFFECTED=1
  STATUS_MSG="updated"
}

handle_drupal() {
  CONFIG_FILE="${TARGET_DIR}/sites/default/settings.php"
  [[ -r "$CONFIG_FILE" ]] || { printf '%s Drupal settings.php not found at %s\n' "$FAIL" "$CONFIG_FILE" >&2; exit 1; }

  CURRENT_URL="$(sed -nE "s/^[[:space:]#]*\\\$base_url[[:space:]]*=[[:space:]]*'([^']+)'.*/\1/p" "$CONFIG_FILE" | head -n1)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    ROWS_AFFECTED=1
    STATUS_MSG="dry-run-preview"
    return 0
  fi

  confirm_action
  backup_file "$CONFIG_FILE"
  chmod u+w "$CONFIG_FILE" 2>/dev/null || true
  if grep -Eq '^[[:space:]#]*\$base_url[[:space:]]*=' "$CONFIG_FILE"; then
    local tmpf
    tmpf="$(mktemp)"
    awk -v target="$TARGET_URL" '
      /^[[:space:]#]*\$base_url[[:space:]]*=/ {
        print "$base_url = \x27" target "\x27;"
        next
      }
      { print }
    ' "$CONFIG_FILE" > "$tmpf"
    cat "$tmpf" > "$CONFIG_FILE"
    rm -f "$tmpf"
  else
    printf "\n\$base_url = '%s';\n" "$TARGET_URL" >> "$CONFIG_FILE"
  fi
  ROWS_AFFECTED=1
  STATUS_MSG="updated"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

render_output() {
  case "$FORMAT" in
    json)
      cat <<EOF
{
  "tool": "${SCRIPT_NAME}",
  "version": "${SCRIPT_VERSION}",
  "timestamp": "$(json_escape "$TIMESTAMP_UTC")",
  "cms": "$(json_escape "$DETECTED_CMS")",
  "config_file": "$(json_escape "$CONFIG_FILE")",
  "database": "$(json_escape "${DB_NAME:-file-only}")",
  "old_url": "$(json_escape "${CURRENT_URL:-none}")",
  "new_url": "$(json_escape "$TARGET_URL")",
  "rows_or_files_affected": ${ROWS_AFFECTED:-0},
  "backup_path": "$(json_escape "${BACKUP_PATH:-none}")",
  "dry_run": $([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false),
  "status": "$(json_escape "$STATUS_MSG")"
}
EOF
      ;;
    csv)
      printf 'cms,database,old_url,new_url,affected,backup,dry_run,status\n'
      printf '"%s","%s","%s","%s","%s","%s","%s","%s"\n' \
        "$DETECTED_CMS" "${DB_NAME:-file-only}" "${CURRENT_URL:-none}" "$TARGET_URL" \
        "${ROWS_AFFECTED:-0}" "${BACKUP_PATH:-none}" "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)" "$STATUS_MSG"
      ;;
    table)
      if [[ "$QUIET" -eq 0 ]]; then
        printf '%s=====================================================================%s\n' "$CYAN" "$RESET"
        printf ' %s%s v%s%s | CMS: %s | %s\n' "$BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$RESET" "$DETECTED_CMS" "$TIMESTAMP_UTC"
        printf '%s=====================================================================%s\n' "$CYAN" "$RESET"
      fi
      printf '  CMS Detected  : %s (%s)\n' "$DETECTED_CMS" "$CONFIG_FILE"
      [[ -n "$DB_NAME" ]] && printf '  Database      : %s (prefix: %s)\n' "$DB_NAME" "${DB_PREFIX:-none}"
      printf '  Old URL       : %s\n' "${CURRENT_URL:-none}"
      printf '  New URL       : %s\n' "$TARGET_URL"
      printf '  Affected      : %s\n' "${ROWS_AFFECTED:-0}"
      printf '  Backup        : %s\n' "${BACKUP_PATH:-none}"
      printf '  Status        : %s\n' "$STATUS_MSG"
      ;;
  esac
}

main() {
  [[ "$#" -eq 0 ]] && { show_help; exit 1; }

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help)         show_help; exit 0 ;;
      -V|--version)      printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      --auto)            CMS_TYPE="auto"; shift ;;
      -w|--wordpress)    CMS_TYPE="wordpress"; shift ;;
      -m|--magento)      CMS_TYPE="magento"; shift ;;
      -j|--joomla)       CMS_TYPE="joomla"; shift ;;
      -p|--prestashop)   CMS_TYPE="prestashop"; shift ;;
      -s|--whmcs)        CMS_TYPE="whmcs"; shift ;;
      -l|--drupal)       CMS_TYPE="drupal"; shift ;;
      -d|--domain)       USE_CPANEL_DOMAIN=1; shift ;;
      --dir)             TARGET_DIR="${2:-.}"; shift 2 ;;
      --old-url)         OLD_URL_OVERRIDE="${2:-}"; shift 2 ;;
      --scheme)          SCHEME="${2:-https}"; shift 2 ;;
      --backup-dir)      BACKUP_DIR="${2:-}"; shift 2 ;;
      --skip-backup)     SKIP_BACKUP=1; shift ;;
      -y|--yes)          AUTO_YES=1; shift ;;
      --dry-run)         DRY_RUN=1; shift ;;
      -q|--quiet)        QUIET=1; shift ;;
      --no-color)        NO_COLOR=1; shift ;;
      -o|--output)       FORMAT="${2:-table}"; shift 2 ;;
      --output=*)        FORMAT="${1#*=}"; shift ;;
      --*)               printf '[ERR] Unknown option: %s (use -h for help)\n' "$1" >&2; exit 1 ;;
      *)                 normalize_target "$1"; shift ;;
    esac
  done

  case "$FORMAT" in
    table|json|csv) ;;
    *) printf '[ERR] Invalid output format: %s (expected table, json, or csv)\n' "$FORMAT" >&2; exit 1 ;;
  esac

  case "$SCHEME" in
    http|https) ;;
    *) printf '[ERR] Invalid --scheme: %s (expected https or http)\n' "$SCHEME" >&2; exit 1 ;;
  esac

  init_colors

  if [[ "$USE_CPANEL_DOMAIN" -eq 1 && -z "$NEW_DOMAIN" ]]; then
    detect_cpanel_domain
  fi

  validate_domain
  detect_cms

  case "$DETECTED_CMS" in
    wordpress)  handle_wordpress ;;
    magento)    handle_magento ;;
    prestashop) handle_prestashop ;;
    whmcs)      handle_whmcs ;;
    joomla)     handle_joomla ;;
    drupal)     handle_drupal ;;
    *)          printf '%s Unsupported CMS: %s\n' "$FAIL" "$DETECTED_CMS" >&2; exit 1 ;;
  esac

  render_output
}

main "$@"
