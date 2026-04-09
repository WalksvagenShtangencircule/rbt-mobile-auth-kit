#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/opt/rbt"
SERVER_DIR="$ROOT_DIR/server"
ASTERISK_DIR="$ROOT_DIR/asterisk"
BACKUP_BASE="${BACKUP_BASE:-/opt/rbt/local-backups}"
NOW="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_BASE/mobile-auth-$NOW"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<USAGE
Использование:
  sudo bash install.sh \\
    --sip-host sip.example.ru \\
    --sip-user 4950000000 \\
    --sip-password 'secret' \\
    --did 4950000000 \\
    [--confirm-number +74950000000] \\
    [--sip-port 5060] \\
    [--transport tcp] \\
    [--trunk-name auth_call] \\
    [--skip-reload]
USAGE
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Ошибка: запустите от root (sudo)." >&2
    exit 1
  fi
}

check_paths() {
  local missing=0
  for p in \
    "$SERVER_DIR/config/config.json" \
    "$SERVER_DIR/backends/isdn/custom/custom.php" \
    "$ASTERISK_DIR/pjsip.conf" \
    "$ASTERISK_DIR/config.lua"; do
    if [[ ! -f "$p" ]]; then
      echo "Не найден файл: $p" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

SIP_HOST=""
SIP_USER=""
SIP_PASSWORD=""
DID=""
CONFIRM_NUMBER=""
SIP_PORT="5060"
TRANSPORT="tcp"
TRUNK_NAME="auth_call"
SKIP_RELOAD="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sip-host) SIP_HOST="$2"; shift 2 ;;
    --sip-user) SIP_USER="$2"; shift 2 ;;
    --sip-password) SIP_PASSWORD="$2"; shift 2 ;;
    --did) DID="$2"; shift 2 ;;
    --confirm-number) CONFIRM_NUMBER="$2"; shift 2 ;;
    --sip-port) SIP_PORT="$2"; shift 2 ;;
    --transport) TRANSPORT="$2"; shift 2 ;;
    --trunk-name) TRUNK_NAME="$2"; shift 2 ;;
    --skip-reload) SKIP_RELOAD="1"; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Неизвестный параметр: $1" >&2; usage; exit 1 ;;
  esac
 done

if [[ -z "$SIP_HOST" || -z "$SIP_USER" || -z "$SIP_PASSWORD" || -z "$DID" ]]; then
  echo "Нужно задать --sip-host, --sip-user, --sip-password, --did" >&2
  usage
  exit 1
fi

if [[ "$TRANSPORT" != "tcp" && "$TRANSPORT" != "udp" ]]; then
  echo "--transport должен быть tcp или udp" >&2
  exit 1
fi

DID10="$(echo "$DID" | tr -cd '0-9' | tail -c 11)"
if [[ ${#DID10} -gt 10 ]]; then
  DID10="${DID10:1}"
fi
if [[ ${#DID10} -ne 10 ]]; then
  echo "--did должен содержать 10 или 11 цифр" >&2
  exit 1
fi
DID11="7${DID10}"

if [[ -z "$CONFIRM_NUMBER" ]]; then
  CONFIRM_NUMBER="+${DID11}"
fi
if [[ -n "$CONFIRM_NUMBER" && "${CONFIRM_NUMBER:0:1}" != "+" ]]; then
  CONFIRM_NUMBER="+${CONFIRM_NUMBER}"
fi

require_root
check_paths

mkdir -p "$BACKUP_DIR"

echo "[1/7] Резервное копирование в $BACKUP_DIR"
cp -a "$SERVER_DIR/config/config.json" "$BACKUP_DIR/config.json.bak"
cp -a "$SERVER_DIR/backends/isdn/custom/custom.php" "$BACKUP_DIR/custom.php.bak"
cp -a "$ASTERISK_DIR/config.lua" "$BACKUP_DIR/config.lua.bak"
cp -a "$ASTERISK_DIR/pjsip.conf" "$BACKUP_DIR/pjsip.conf.bak"
mkdir -p "$BACKUP_DIR/trunks"
cp -a "$ASTERISK_DIR/trunks"/*.conf "$BACKUP_DIR/trunks/" 2>/dev/null || true


echo "[2/7] Обновление config.json (outgoingCall)"
python3 - "$SERVER_DIR/config/config.json" "$CONFIRM_NUMBER" <<'PY'
import json, sys
path, confirm = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)
backends = cfg.setdefault('backends', {})
isdn = backends.setdefault('isdn', {})
isdn['backend'] = 'custom'
isdn['confirm_method'] = 'outgoingCall'
isdn['confirm_number'] = confirm
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=4)
    f.write('\n')
PY


echo "[3/7] Обновление backend isdn/custom/custom.php"
cp -a "$SERVER_DIR/backends/isdn/custom/custom.php" "$SERVER_DIR/backends/isdn/custom/custom.php.tmp.before"
python3 - "$SERVER_DIR/backends/isdn/custom/custom.php" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
text = path.read_text()

normalize_block = '''
            private function normalizeMobile($id): string
            {
                $mobile = preg_replace('/\\D+/', '', (string)$id);
                if (!$mobile) {
                    return '';
                }

                if (strlen($mobile) === 11 && $mobile[0] === '8') {
                    $mobile[0] = '7';
                } elseif (strlen($mobile) === 10) {
                    $mobile = '7' . $mobile;
                }

                return $mobile;
            }
'''

check_block = '''
            function checkIncoming($id)
            {
                $mobile = $this->normalizeMobile($id);
                if ($mobile) {
                    if ($this->redis->get("isdn_incoming_+$mobile")) {
                        return 1;
                    }
                    if ($this->redis->get("isdn_incoming_$mobile")) {
                        return 1;
                    }
                    if ($mobile[0] === '7') {
                        $mobile8 = '8' . substr($mobile, 1);
                        if ($this->redis->get("isdn_incoming_$mobile8")) {
                            return 1;
                        }
                    }
                }

                return 0;
            }
'''

if 'private function normalizeMobile' not in text:
    text = text.replace('        {\n            use incoming;\n', '        {\n            use incoming;\n' + normalize_block)

text = re.sub(r'\n\s*function checkIncoming\(\$id\)\n\s*\{[\s\S]*?\n\s*\}\n\s*\}\n\s*\}\n\s*$', '\n', text)

if 'function checkIncoming($id)' not in text:
    text = text.rstrip()[:-1].rstrip()  # remove last }
    text += '\n' + check_block + '        }\n    }\n'

path.write_text(text)
PY
rm -f "$SERVER_DIR/backends/isdn/custom/custom.php.tmp.before"


echo "[4/7] Настройка custom Lua хука"
mkdir -p "$ASTERISK_DIR/custom"
cp "$SCRIPT_DIR/templates/mobile_auth.lua.tpl" "$ASTERISK_DIR/custom/mobile_auth.lua"
sed -i "s/__DID_10__/${DID10}/g; s/__DID_11__/${DID11}/g" "$ASTERISK_DIR/custom/mobile_auth.lua"


echo "[5/7] Подключение mobile_auth в config.lua"
python3 - "$ASTERISK_DIR/config.lua" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
text = p.read_text()
if 'custom = {' not in text:
    text = text.rstrip() + '\ncustom = {\n    "mobile_auth",\n}\n'
elif '"mobile_auth"' not in text:
    text = re.sub(r'custom\s*=\s*\{', 'custom = {\n    "mobile_auth",', text, count=1)
p.write_text(text)
PY


echo "[6/7] Настройка PJSIP include и trunk"
if ! grep -q '^#include trunks/\*\.conf' "$ASTERISK_DIR/pjsip.conf"; then
  printf "\n#include trunks/*.conf\n" >> "$ASTERISK_DIR/pjsip.conf"
fi

cp "$SCRIPT_DIR/templates/trunk.conf.tpl" "$ASTERISK_DIR/trunks/${TRUNK_NAME}.conf"
sed -i \
  -e "s/__TRUNK_NAME__/${TRUNK_NAME}/g" \
  -e "s/__TRANSPORT__/${TRANSPORT}/g" \
  -e "s/__SIP_HOST__/${SIP_HOST}/g" \
  -e "s/__SIP_USER__/${SIP_USER}/g" \
  -e "s/__SIP_PASSWORD__/${SIP_PASSWORD}/g" \
  -e "s/__SIP_PORT__/${SIP_PORT}/g" \
  "$ASTERISK_DIR/trunks/${TRUNK_NAME}.conf"


echo "[7/7] Валидация и reload"
php -l "$SERVER_DIR/backends/isdn/custom/custom.php" >/dev/null
python3 -m json.tool "$SERVER_DIR/config/config.json" >/dev/null

if [[ "$SKIP_RELOAD" == "0" ]]; then
  asterisk -rx 'module reload pbx_lua.so' >/dev/null
  asterisk -rx 'core reload' >/dev/null

  FPM_SERVICE="$(systemctl list-units --type=service --all | awk '/php.*fpm.service/ && /running/ {print $1; exit}')"
  if [[ -n "$FPM_SERVICE" ]]; then
    systemctl restart "$FPM_SERVICE"
  fi
fi

echo "Готово."
echo "Бэкап: $BACKUP_DIR"
echo "Проверка SIP: asterisk -rx 'pjsip show registrations'"
