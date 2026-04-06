#!/bin/sh

# ========= 配置 =========
TARGET_FILE="/opt/adguard_upstream_dns_file.txt"
TMP_FILE="/tmp/adguard_upstream_dns_file.tmp"
BACKUP_FILE="/opt/adguard_upstream_dns_file.bak"

URL_MAIN="https://gh.ryanchan.top/https://raw.githubusercontent.com/joyanhui/adguardhome-rules/refs/heads/release_file/ADG_chinaDirect_WinUpdate_Gfw.txt"
URL_BACKUP="https://cdn.jsdelivr.net/gh/joyanhui/adguardhome-rules@release_file/ADG_chinaDirect_WinUpdate_Gfw.txt"

echo "========== 开始更新规则 =========="

# ========= 1. 下载（主源 + 备用源） =========
echo "下载主源..."
wget -T 10 -O "$TMP_FILE" "$URL_MAIN"

if [ $? -ne 0 ] || [ ! -s "$TMP_FILE" ]; then
  echo "主源失败，尝试备用源..."
  wget -T 10 -O "$TMP_FILE" "$URL_BACKUP"
fi

# ========= 2. 校验下载 =========
if [ $? -ne 0 ] || [ ! -s "$TMP_FILE" ]; then
  echo "下载失败或文件为空 ❌"
  rm -f "$TMP_FILE"
  exit 1
fi

# ========= 3. 内容校验 =========

# 3.1 防 HTML 污染
if grep -qi "<html" "$TMP_FILE"; then
  echo "检测到HTML页面（可能被劫持）❌"
  rm -f "$TMP_FILE"
  exit 1
fi

# 3.2 替换内容（先替换再校验）
sed -i \
  -e 's/d-o-h.you-cf-domain.com/dns.cloudflare.com/g' \
  -e 's/your-suffix/dns-query/g' \
  "$TMP_FILE"

# 3.3 校验关键字段
if ! grep -q "dns.cloudflare.com" "$TMP_FILE"; then
  echo "未找到关键字段 dns.cloudflare.com ❌"
  rm -f "$TMP_FILE"
  exit 1
fi

# 3.4 校验规则数量
LINE_COUNT=$(wc -l < "$TMP_FILE")
if [ "$LINE_COUNT" -lt 50 ]; then
  echo "规则数量异常（$LINE_COUNT），终止 ❌"
  rm -f "$TMP_FILE"
  exit 1
fi

echo "内容校验通过 ✅（$LINE_COUNT 行）"

# ========= 4. 备份旧文件 =========
if [ -f "$TARGET_FILE" ]; then
  cp "$TARGET_FILE" "$BACKUP_FILE"
  echo "已备份旧文件 → $BACKUP_FILE"
fi

# ========= 5. 原子替换 =========
mv "$TMP_FILE" "$TARGET_FILE"

if [ $? -ne 0 ]; then
  echo "替换失败，尝试回滚 ❌"
  if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$TARGET_FILE"
    echo "已回滚到旧版本"
  fi
  exit 1
fi

echo "替换成功 ✅"

# ========= 6. 重启服务 =========
echo "重启 AdGuardHome..."

/etc/init.d/adguardhome restart 2>/dev/null || /etc/init.d/AdGuardHome restart

if [ $? -ne 0 ]; then
  echo "重启失败 ⚠️（请手动检查）"
  exit 1
fi

echo "========== 更新完成 🎉 =========="