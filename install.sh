#!/bin/bash

# ═══════════════════════════════════════════════════════════
# XRAYEBATOR INSTALLER v1.3.2 EXP
# Автоматическая установка Xray Reality VPN
# GitHub: https://github.com/d-rol/Xrayebator
# ═══════════════════════════════════════════════════════════

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# GitHub репозиторий
GITHUB_USER="d-rol"
GITHUB_REPO="Xrayebator"
SELF_RELEASE_TAG="v1.3.2-sec1"
SELF_RELEASE_BASE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${SELF_RELEASE_TAG}"
XTLS_INSTALL_REF="e741a4f56d368afbb9e5be3361b40c4552d3710d"
XTLS_INSTALL_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"

# Пути
CONFIG_FILE="/usr/local/etc/xray/config.json"
PROFILES_DIR="/usr/local/etc/xray/profiles"
DATA_DIR="/usr/local/etc/xray/data"
SCRIPTS_DIR="/usr/local/etc/xray/scripts"
PRIVATE_KEY_FILE="/usr/local/etc/xray/.private_key"
PUBLIC_KEY_FILE="/usr/local/etc/xray/.public_key"
TMP_XRAY_INSTALLER=""
TMP_RELEASE_CHECKSUMS=""
TMP_RELEASE_ASSET=""

cleanup_install_tmp() {
  [[ -n "$TMP_XRAY_INSTALLER" ]] && rm -f "$TMP_XRAY_INSTALLER"
  [[ -n "$TMP_RELEASE_CHECKSUMS" ]] && rm -f "$TMP_RELEASE_CHECKSUMS"
  [[ -n "$TMP_RELEASE_ASSET" ]] && rm -f "$TMP_RELEASE_ASSET"
}

download_file() {
  local url=$1
  local dst=$2
  curl --proto '=https' --tlsv1.2 --fail --show-error --silent --location "$url" -o "$dst"
}

download_bash_script() {
  local url=$1
  local dst=$2

  if ! download_file "$url" "$dst"; then
    return 1
  fi

  [[ -s "$dst" ]] && head -n 1 "$dst" | grep -q "^#!/bin/bash"
}

expected_sha256_from_file() {
  local checksum_file=$1
  local asset_name=$2
  awk -v asset="$asset_name" '{ sub(/\r$/, "", $2); if ($2 == asset) { print $1; exit } }' "$checksum_file"
}

verify_sha256() {
  local file_path=$1
  local expected_sha=$2
  local actual_sha

  actual_sha=$(sha256sum "$file_path" | awk '{print $1}')
  [[ -n "$expected_sha" ]] && [[ "$actual_sha" == "$expected_sha" ]]
}

download_verified_bash_script() {
  local url=$1
  local dst=$2
  local expected_sha=$3

  if ! download_bash_script "$url" "$dst"; then
    return 1
  fi

  verify_sha256 "$dst" "$expected_sha"
}

load_release_checksums() {
  TMP_RELEASE_CHECKSUMS=$(mktemp)
  download_file "${SELF_RELEASE_BASE_URL}/checksums.txt" "$TMP_RELEASE_CHECKSUMS"
}

download_release_asset_verified() {
  local asset_name=$1
  local destination=$2
  local mode=$3
  local expected_sha

  expected_sha=$(expected_sha256_from_file "$TMP_RELEASE_CHECKSUMS" "$asset_name")
  [[ -n "$expected_sha" ]] || return 1

  TMP_RELEASE_ASSET=$(mktemp)
  if ! download_file "${SELF_RELEASE_BASE_URL}/${asset_name}" "$TMP_RELEASE_ASSET"; then
    rm -f "$TMP_RELEASE_ASSET"
    TMP_RELEASE_ASSET=""
    return 1
  fi

  if ! verify_sha256 "$TMP_RELEASE_ASSET" "$expected_sha"; then
    rm -f "$TMP_RELEASE_ASSET"
    TMP_RELEASE_ASSET=""
    return 1
  fi

  install -m "$mode" "$TMP_RELEASE_ASSET" "$destination"
  rm -f "$TMP_RELEASE_ASSET"
  TMP_RELEASE_ASSET=""
}

trap cleanup_install_tmp EXIT

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}✗ Требуются права root для установки${NC}"
  exit 1
fi

clear
echo -e "${CYAN}"
echo '╔═══════════════════════════════════════════════════════════╗'
echo '║                                                           ║'
echo '║            XRAYEBATOR INSTALLER v1.3.2 EXP               ║'
echo '║       Автоматическая установка Xray Reality VPN          ║'
echo '║                                                           ║'
echo '╚═══════════════════════════════════════════════════════════╝'
echo -e "${NC}\n"
echo -e "${YELLOW}Начало установки...${NC}\n"
sleep 2

# [1/10] Установка зависимостей
echo -e "${BLUE}[1/10]${NC} ${YELLOW}Установка необходимых пакетов...${NC}"
apt update > /dev/null 2>&1
apt install -y curl wget jq qrencode uuid-runtime ufw > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
  echo -e "${GREEN}✓ Зависимости установлены${NC}\n"
else
  echo -e "${RED}✗ Ошибка установки зависимостей${NC}"
  exit 1
fi

# [2/10] Установка Xray-core
echo -e "${BLUE}[2/10]${NC} ${YELLOW}Установка Xray-core...${NC}"
TMP_XRAY_INSTALLER=$(mktemp)
if download_verified_bash_script "https://raw.githubusercontent.com/XTLS/Xray-install/${XTLS_INSTALL_REF}/install-release.sh" "$TMP_XRAY_INSTALLER" "$XTLS_INSTALL_SHA256" && \
   bash "$TMP_XRAY_INSTALLER" @ install > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Xray-core установлен${NC}\n"
else
  echo -e "${RED}✗ Ошибка установки Xray-core${NC}"
  exit 1
fi

# [3/10] Исправление systemd сервиса
echo -e "${BLUE}[3/10]${NC} ${YELLOW}Настройка Xray сервиса...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✓ Сервис оставлен со штатными минимальными привилегиями${NC}\n"

# [3.5/10] Загрузка расширенных geo-баз (Loyalsoldier)
echo -e "${BLUE}[3.5/10]${NC} ${YELLOW}Загрузка расширенных geo-баз...${NC}"
XRAY_DAT_DIR="/usr/local/share/xray"
LOYALSOLDIER_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"

mkdir -p "$XRAY_DAT_DIR"

# Download geoip.dat
echo -e "${CYAN}  → Загрузка geoip.dat...${NC}"
if curl -fsSL "${LOYALSOLDIER_URL}/geoip.dat" -o "${XRAY_DAT_DIR}/geoip.dat.tmp"; then
  if [[ -s "${XRAY_DAT_DIR}/geoip.dat.tmp" ]]; then
    mv "${XRAY_DAT_DIR}/geoip.dat.tmp" "${XRAY_DAT_DIR}/geoip.dat"
    echo -e "${GREEN}  ✓ geoip.dat загружен${NC}"
  else
    rm -f "${XRAY_DAT_DIR}/geoip.dat.tmp"
    echo -e "${YELLOW}  ⚠ geoip.dat пустой, используется стандартный${NC}"
  fi
else
  echo -e "${YELLOW}  ⚠ Не удалось загрузить geoip.dat, используется стандартный${NC}"
fi

# Download geosite.dat
echo -e "${CYAN}  → Загрузка geosite.dat...${NC}"
if curl -fsSL "${LOYALSOLDIER_URL}/geosite.dat" -o "${XRAY_DAT_DIR}/geosite.dat.tmp"; then
  if [[ -s "${XRAY_DAT_DIR}/geosite.dat.tmp" ]]; then
    mv "${XRAY_DAT_DIR}/geosite.dat.tmp" "${XRAY_DAT_DIR}/geosite.dat"
    echo -e "${GREEN}  ✓ geosite.dat загружен${NC}"
  else
    rm -f "${XRAY_DAT_DIR}/geosite.dat.tmp"
    echo -e "${YELLOW}  ⚠ geosite.dat пустой, используется стандартный${NC}"
  fi
else
  echo -e "${YELLOW}  ⚠ Не удалось загрузить geosite.dat, используется стандартный${NC}"
fi

echo -e "${GREEN}✓ Geo-базы настроены (Loyalsoldier enhanced)${NC}\n"

# [4/10] Создание структуры директорий
echo -e "${BLUE}[4/10]${NC} ${YELLOW}Создание структуры директорий...${NC}"
mkdir -p "$PROFILES_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$SCRIPTS_DIR"
if ! load_release_checksums; then
  echo -e "${RED}вњ— РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё checksums.txt РёР· release${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Директории созданы${NC}\n"

# [5/10] Генерация ключей Reality
echo -e "${BLUE}[5/10]${NC} ${YELLOW}Генерация ключей Reality...${NC}"
KEYS_OUTPUT=$(/usr/local/bin/xray x25519 2>&1)
PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep "PrivateKey:" | cut -d' ' -f2)
PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep "Password:" | cut -d' ' -f2)

if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]]; then
  echo -e "${RED}✗ Ошибка генерации ключей${NC}"
  echo "Вывод xray x25519:"
  echo "$KEYS_OUTPUT"
  exit 1
fi

printf "%s" "$PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
printf "%s" "$PUBLIC_KEY" > "$PUBLIC_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"
chmod 644 "$PUBLIC_KEY_FILE"
echo -e "${GREEN}✓ Ключи сгенерированы${NC}"
echo -e "${CYAN}  Private: ${PRIVATE_KEY:0:16}...${NC}"
echo -e "${CYAN}  Public: ${PUBLIC_KEY:0:16}...${NC}\n"

# [6/10] Создание базовой конфигурации
echo -e "${BLUE}[6/10]${NC} ${YELLOW}Создание конфигурации Xray...${NC}"
cat > "$CONFIG_FILE" << 'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      "https://dns.adguard-dns.com/dns-query",
      {
        "address": "1.1.1.1",
        "domains": ["geosite:geolocation-!cn"]
      },
      "localhost"
    ],
    "queryStrategy": "UseIPv4",
    "disableCache": false
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "network": "udp",
        "port": 443,
        "outboundTag": "block"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

chown root:root "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"
echo -e "${GREEN}✓ Конфигурация создана${NC}\n"

# [7/10] Настройка Firewall
echo -e "${BLUE}[7/10]${NC} ${YELLOW}Настройка firewall...${NC}"
if ! ufw status | grep -q "Status: active"; then
  ufw --force enable > /dev/null 2>&1
fi

UFW_ERRORS=0
for ufw_port in 22 80 443 8443 2053 2083 2087 8080 2096 8880 9443; do
  if ! ufw allow "${ufw_port}/tcp" > /dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ Не удалось открыть порт ${ufw_port}/tcp${NC}"
    ((UFW_ERRORS++))
  fi
done

ufw reload > /dev/null 2>&1
echo -e "${GREEN}✓ Firewall настроен${NC}"
echo -e "${CYAN}  Открытые порты: 443, 2053, 2096, 8080, 8443, 8880, 9443${NC}\n"

# [8/10] Оптимизация TCP (BBR)
echo -e "${BLUE}[8/10]${NC} ${YELLOW}Настройка BBR TCP Congestion Control...${NC}"
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
  cat >> /etc/sysctl.conf << 'EOF'
# BBR TCP Congestion Control Optimization
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1
net.core.netdev_max_backlog=16384
net.ipv4.tcp_max_syn_backlog=8192
EOF
  sysctl -p > /dev/null 2>&1
  echo -e "${GREEN}✓ BBR включен и настроен${NC}\n"
else
  echo -e "${CYAN}✓ BBR уже настроен${NC}\n"
fi

# [9/10] Загрузка данных
echo -e "${BLUE}[9/10]${NC} ${YELLOW}Загрузка данных приложения...${NC}"
if download_release_asset_verified "sni_list.txt" "${DATA_DIR}/sni_list.txt" 0644; then
  echo -e "${GREEN}✓ Список SNI загружен${NC}"
else
  echo -e "${YELLOW}⚠ Не удалось загрузить список SNI, создаю базовый...${NC}"
  cat > "${DATA_DIR}/sni_list.txt" << 'EOF'
ozone.ru|ru_whitelist|1
wildberries.ru|ru_whitelist|1
sberbank.ru|ru_whitelist|1
nspk.ru|ru_whitelist|1
speller.yandex.net|yandex_cdn|2
gosuslugi.ru|ru_whitelist|1
stats.vk-portal.net|ru_whitelist|1
github.com|foreign|3
cloudflare.com|foreign|3
www.microsoft.com|foreign|3
EOF
fi

if download_release_asset_verified "ascii_art.txt" "${DATA_DIR}/ascii_art.txt" 0644 2>/dev/null; then
  echo -e "${GREEN}✓ ASCII арт загружен${NC}\n"
else
  echo -e "${CYAN}✓ ASCII арт недоступен (не критично)${NC}\n"
fi

# [10/10] Установка приложения
echo -e "${BLUE}[10/10]${NC} ${YELLOW}Установка управляющего приложения...${NC}"
if download_release_asset_verified "xrayebator" "/usr/local/bin/xrayebator" 0755; then
  echo -e "${GREEN}✓ Приложение xrayebator установлено${NC}"
else
  echo -e "${RED}✗ Ошибка загрузки xrayebator${NC}"
  exit 1
fi

# Скрипты управления
download_release_asset_verified "update.sh" "${SCRIPTS_DIR}/update.sh" 0755 > /dev/null 2>&1
download_release_asset_verified "uninstall.sh" "${SCRIPTS_DIR}/uninstall.sh" 0755 > /dev/null 2>&1
ln -sf "${SCRIPTS_DIR}/update.sh" /usr/local/bin/xrayebator-update 2>/dev/null
ln -sf "${SCRIPTS_DIR}/uninstall.sh" /usr/local/bin/xrayebator-uninstall 2>/dev/null
echo -e "${GREEN}✓ Скрипты установлены${NC}\n"

# Запуск Xray
systemctl enable xray > /dev/null 2>&1
systemctl restart xray > /dev/null 2>&1
if systemctl is-active --quiet xray; then
  echo -e "${GREEN}✓ Xray успешно запущен${NC}\n"
else
  echo -e "${CYAN}✓ Xray установлен (запустится при создании профиля)${NC}\n"
fi

# Финальное сообщение
clear
echo -e "${GREEN}"
echo '╔═══════════════════════════════════════════════════════════╗'
echo '║                                                           ║'
echo '║          ✓ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!                 ║'
echo '║                                                           ║'
echo '╚═══════════════════════════════════════════════════════════╝'
echo -e "${NC}\n"
echo -e "${CYAN}Для управления профилями используйте команду:${NC}"
echo -e "${YELLOW}╭──────────────────────────╮${NC}"
echo -e "${YELLOW}│ ${GREEN}sudo xrayebator${YELLOW}          │${NC}"
echo -e "${YELLOW}╰──────────────────────────╯${NC}\n"
echo -e "${BLUE}Дополнительные команды:${NC}"
echo -e "  ${CYAN}sudo xrayebator-update${NC}    - обновить Xrayebator"
echo -e "  ${CYAN}sudo xrayebator-uninstall${NC} - удалить Xrayebator"
echo ""
echo -e "${BLUE}Открытые порты в firewall:${NC}"
echo -e "  ${GREEN}443/tcp${NC}  - HTTPS (основной)"
echo -e "  ${GREEN}8443/tcp${NC} - Альтернативный порт"
echo ""
echo -e "${BLUE}GitHub:${NC} https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
echo -e "${BLUE}Версия:${NC} 1.3.2 EXP"
echo ""
echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
