#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy_to_chr.sh — Сборка awg2-webui и деплой на MikroTik CHR
#
# Запуск: bash deploy_to_chr.sh
#
# Что делает:
#   1. Собирает образ linux/amd64 из текущей папки
#   2. Сохраняет в /tmp/awg2-webui.tar
#   3. Заливает tar на CHR по SCP
#   4. SSH: удаляет старый контейнер, добавляет новый, стартует
# ─────────────────────────────────────────────────────────────────────────────

set -e

# ── Параметры CHR ─────────────────────────────────────────────────────────────
CHR_HOST="194.116.172.251"
CHR_PORT="2222"
CHR_USER="claude"
CHR_PASS="P@shamar12"

# ── Параметры образа ─────────────────────────────────────────────────────────
IMAGE_NAME="awg2-webui"
IMAGE_TAG="amd64"
LOCAL_TAR="/tmp/awg2-webui.tar"
REMOTE_TAR="disk1/awg2-webui.tar"

# ── Параметры контейнера ──────────────────────────────────────────────────────
CONTAINER_OLD_IDX="3"          # старый awgui-test
ENVLIST="awgui-env"            # существующий envlist (обновим переменные)
VETH="veth-awgui"              # существующий veth (не трогаем)
CONTAINER_IP="10.10.6.2"
WEB_EXT_PORT="9080"
AWG_EXT_PORT="51821"
AWG_ENDPOINT="194.116.172.251:${AWG_EXT_PORT}"
WEB_USER="admin"
WEB_PASS="AmneziaTest2026"
DATA_DIR="disk1/docker/awg2-webui-data"

# ── Фикс: Docker Desktop credential helper ────────────────────────────────────
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
if ! command -v docker-credential-desktop &>/dev/null; then
    DOCKER_CFG="$HOME/.docker/config.json"
    if [ -f "$DOCKER_CFG" ] && grep -q '"credsStore"' "$DOCKER_CFG"; then
        echo "ℹ  Фикс credsStore..."
        cp "$DOCKER_CFG" "${DOCKER_CFG}.bak"
        python3 -c "
import json
with open('$DOCKER_CFG') as f: c = json.load(f)
c.pop('credsStore', None); c.pop('credStore', None)
with open('$DOCKER_CFG', 'w') as f: json.dump(c, f, indent=2)
"
        trap "mv '${DOCKER_CFG}.bak' '$DOCKER_CFG' 2>/dev/null" EXIT
    fi
fi

# ── sshpass helper ────────────────────────────────────────────────────────────
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -p ${CHR_PORT}"
run_ssh() {
    sshpass -p "${CHR_PASS}" ssh ${SSH_OPTS} "${CHR_USER}@${CHR_HOST}" "$@"
}
run_scp_upload() {
    sshpass -p "${CHR_PASS}" scp -P "${CHR_PORT}" -o StrictHostKeyChecking=no "$1" "${CHR_USER}@${CHR_HOST}:$2"
}

# Проверяем sshpass
if ! command -v sshpass &>/dev/null; then
    echo "❌ Нужен sshpass: brew install hudochenkov/sshpass/sshpass"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWG 2.0 Web UI — Deploy to CHR"
echo "  Target: ${CHR_HOST}:${CHR_PORT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ────────────────────────────────────────────────────
# ШАГ 1 — Сборка образа linux/amd64
# ────────────────────────────────────────────────────
echo ""
echo "▶ [1/5] Сборка образа ${IMAGE_NAME}:${IMAGE_TAG} (linux/amd64)..."
docker build \
    --platform linux/amd64 \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    "$SCRIPT_DIR"
echo "  ✅ Образ собран"

# ────────────────────────────────────────────────────
# ШАГ 2 — Сохранение в tar
# ────────────────────────────────────────────────────
echo ""
echo "▶ [2/5] Сохранение в ${LOCAL_TAR}..."
docker save "${IMAGE_NAME}:${IMAGE_TAG}" -o "$LOCAL_TAR"
TAR_SIZE=$(du -sh "$LOCAL_TAR" | cut -f1)
echo "  ✅ Готово (${TAR_SIZE})"

# ────────────────────────────────────────────────────
# ШАГ 3 — Заливка на CHR
# ────────────────────────────────────────────────────
echo ""
echo "▶ [3/5] Заливка на CHR: ${REMOTE_TAR} ..."
echo "  (может занять 1-3 минуты в зависимости от канала)"
run_scp_upload "$LOCAL_TAR" "$REMOTE_TAR"
echo "  ✅ Файл залит"

# ────────────────────────────────────────────────────
# ШАГ 4 — RouterOS: удалить старый, настроить новый
# ────────────────────────────────────────────────────
echo ""
echo "▶ [4/5] Настройка RouterOS..."

run_ssh "
# Удаляем старый контейнер
/container/remove ${CONTAINER_OLD_IDX}

# Удаляем старый tar
/file/remove awgui-test.tar

# Создаём папку для данных AWG (конфиги, ключи)
/file/make-directory ${DATA_DIR}

# Обновляем envlist под наш образ (удаляем старые ключи, добавляем новые)
/container/envs/remove [find name=\"${ENVLIST}\"]
/container/envs/add name=\"${ENVLIST}\" key=\"WEB_USER\"     value=\"${WEB_USER}\"
/container/envs/add name=\"${ENVLIST}\" key=\"WEB_PASS\"     value=\"${WEB_PASS}\"
/container/envs/add name=\"${ENVLIST}\" key=\"AWG_PORT\"     value=\"51820\"
/container/envs/add name=\"${ENVLIST}\" key=\"AWG_ENDPOINT\" value=\"${AWG_ENDPOINT}\"
/container/envs/add name=\"${ENVLIST}\" key=\"AWG_SUBNET\"   value=\"10.8.0.0/24\"
/container/envs/add name=\"${ENVLIST}\" key=\"AWG_DNS\"      value=\"1.1.1.1,8.8.8.8\"
/container/envs/add name=\"${ENVLIST}\" key=\"AWG_INTERFACE\" value=\"awg0\"
/container/envs/add name=\"${ENVLIST}\" key=\"AMNEZIAWG_FORCE_USERSPACE\" value=\"1\"

# Добавляем новый контейнер
/container/add \
  file=${REMOTE_TAR} \
  interface=${VETH} \
  root-dir=${DATA_DIR} \
  envlist=${ENVLIST} \
  logging=yes \
  start-on-boot=yes \
  comment=\"AWG 2.0 Web UI\"

# NAT: 9080 -> контейнер :80
/ip/firewall/nat/add \
  chain=dstnat \
  protocol=tcp \
  dst-port=${WEB_EXT_PORT} \
  action=dst-nat \
  to-addresses=${CONTAINER_IP} \
  to-ports=80 \
  comment=\"awg2-webui HTTP\"

# NAT: 51821/udp -> контейнер :51820
/ip/firewall/nat/add \
  chain=dstnat \
  protocol=udp \
  dst-port=${AWG_EXT_PORT} \
  action=dst-nat \
  to-addresses=${CONTAINER_IP} \
  to-ports=51820 \
  comment=\"awg2-webui UDP\"
"

echo "  ✅ RouterOS настроен"

# ────────────────────────────────────────────────────
# ШАГ 5 — Ждём импорта и стартуем
# ────────────────────────────────────────────────────
echo ""
echo "▶ [5/5] Ожидание импорта tar и запуск..."
echo "  (RouterOS распаковывает образ — ~30-60 сек)"
sleep 45

run_ssh "/container/start [find comment~\"AWG 2.0 Web UI\"]"
echo "  ✅ Контейнер запущен"

sleep 5
echo ""
echo "▶ Проверка статуса:"
run_ssh "/container/print detail where comment~\"AWG 2.0\""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Деплой завершён!"
echo ""
echo "  Web UI : http://${CHR_HOST}:${WEB_EXT_PORT}"
echo "  Логин  : ${WEB_USER} / ${WEB_PASS}"
echo "  AWG UDP: ${CHR_HOST}:${AWG_EXT_PORT}"
echo ""
echo "  Логи контейнера:"
echo "  run_ssh /log/print where topics~\"container\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
