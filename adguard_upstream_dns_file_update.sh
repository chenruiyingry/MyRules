#!/bin/sh

# ========= 配置 =========
PATH=/usr/sbin:/usr/bin:/sbin:/bin

TARGET_FILE="/opt/adguard_upstream_dns_file.txt"
TMP_FILE="/tmp/adguard_upstream_dns_file.tmp"
BACKUP_FILE="/opt/adguard_upstream_dns_file.bak"

URL_MAIN="https://gh.ryanchan.top/https://raw.githubusercontent.com/joyanhui/adguardhome-rules/refs/heads/release_file/ADG_chinaDirect_WinUpdate_Gfw.txt"
URL_BACKUP="https://cdn.jsdelivr.net/gh/joyanhui/adguardhome-rules@release_file/ADG_chinaDirect_WinUpdate_Gfw.txt"

# ======= 通知配置 =======
# Bark（推荐）
BARK_URL="https://api.day.app/你的key"

# Telegram（可选）
TG_BOT_TOKEN=""
TG_CHAT_ID=""

# ========= 通知函数 =========
notify() {
  MSG="$1"

  # Bark
  if [ -n "$BARK_URL" ]; then
    curl -s "$BARK_URL/$MSG" >/dev/null 2>&1
  fi

  # Telegram
  if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
      -d "chat_id=$TG_CHAT_ID&text=$MSG" >/dev/null 2>&1
  fi
}

echo "========== 开始更新规则 =========="

# ========= 1. 下载 =========
wget -T 10 -O "$TMP_FILE" "$URL_MAIN"

if [ $? -ne 0 ] || [ ! -s "$TMP_FILE" ]; then
  echo "主源失败，尝试备用源..."
  wget -T 10 -O "$TMP_FILE" "$URL_BACKUP"
fi

# ========= 2. 校验下载 =========
if [ $? -ne 0 ] || [ ! -s "$TMP_FILE" ]; then
  notify "AdGuard规则更新失败：下载失败"
  rm -f "$TMP_FILE"
  exit 1
fi

# ========= 3. 内容校验 =========

# 防 HTML
if grep -qi "<html" "$TMP_FILE"; then
  notify "AdGuard规则更新失败：HTML污染"
  rm -f "$TMP_FILE"
  exit 1
fi

# 替换内容
sed -i \
  -e 's/d-o-h.you-cf-domain.com/dns.cloudflare.com/g' \
  -e 's/your-suffix/dns-query/g' \
  "$TMP_FILE"

# 校验关键字段
if ! grep -q "dns.cloudflare.com" "$TMP_FILE"; then
  notify "AdGuard规则更新失败：关键字段缺失"
  rm -f "$TMP_FILE"
  exit 1
fi

# 校验行数
LINE_COUNT=$(wc -l < "$TMP_FILE")
if [ "$LINE_COUNT" -lt 50 ]; then
  notify "AdGuard规则更新失败：规则数量异常($LINE_COUNT)"
  rm -f "$TMP_FILE"
  exit 1
fi

echo "校验通过 ✅"

# ========= 4. 判断是否有变化 =========

if [ -f "$TARGET_FILE" ]; then
  OLD_MD5=$(md5sum "$TARGET_FILE" | awk '{print $1}')
  NEW_MD5=$(md5sum "$TMP_FILE" | awk '{print $1}')

  if [ "$OLD_MD5" = "$NEW_MD5" ]; then
    echo "内容无变化，不更新、不重启 👍"
    rm -f "$TMP_FILE"
    exit 0
  fi
fi

echo "检测到内容变更，继续更新..."

# ========= 5. 备份 =========
if [ -f "$TARGET_FILE" ]; then
  cp "$TARGET_FILE" "$BACKUP_FILE"
fi

# ========= 6. 替换 =========
mv "$TMP_FILE" "$TARGET_FILE"

if [ $? -ne 0 ]; then
  notify "AdGuard规则更新失败：替换失败"
  [ -f "$BACKUP_FILE" ] && cp "$BACKUP_FILE" "$TARGET_FILE"
  exit 1
fi

echo "替换成功 ✅"

# ========= 7. 重启 =========
/etc/init.d/adguardhome restart 2>/dev/null || /etc/init.d/AdGuardHome restart

if [ $? -ne 0 ]; then
  notify "AdGuard规则更新失败：重启失败"
  exit 1
fi

# ========= 8. 成功通知 =========
notify "AdGuard规则更新成功 🎉（$LINE_COUNT 条）"

echo "========== 更新完成 =========="