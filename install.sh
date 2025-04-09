#!/bin/bash

# ========== NHẬP THÔNG TIN TỪ NGƯỜI DÙNG ==========
read -p "🔌 Nhập IP Proxy: " PROXY_IP
read -p "🎯 Nhập Port Proxy: " PROXY_PORT
read -p "👤 Nhập Username SOCKS5: " PROXY_USER
read -p "🔐 Nhập Password SOCKS5: " PROXY_PASS
read -p "🌐 Nhập tên giao diện VPN (tun0/wg0): " VPN_IFACE

read -p "📬 Nhập Telegram Bot Token: " TG_TOKEN
read -p "📨 Nhập Telegram Chat ID: " TG_CHAT_ID

CHECK_SCRIPT="/root/check-proxy.sh"
CRON_JOB="*/5 * * * * $CHECK_SCRIPT >> /var/log/check-proxy.log 2>&1"

# ========== HÀM GỬI TELEGRAM ==========
send_alert() {
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    -d parse_mode="Markdown" \
    -d text="$1"
}

echo "[+] Cài redsocks & curl..."
apt update && apt install -y redsocks curl

echo "[+] Tạo file cấu hình redsocks..."
cat > /etc/redsocks.conf <<EOF
base {
  log_debug = off;
  log_info = on;
  daemon = on;
  redirector = iptables;
}

redsocks {
  local_ip = 127.0.0.1;
  local_port = 12345;

  ip = $PROXY_IP;
  port = $PROXY_PORT;

  type = socks5;
  login = "$PROXY_USER";
  password = "$PROXY_PASS";
}
EOF

echo "[+] Bật IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1

echo "[+] Khởi động lại redsocks..."
systemctl restart redsocks
systemctl enable redsocks

echo "[+] Thiết lập iptables redirect từ $VPN_IFACE..."
iptables -t nat -F
iptables -t nat -A PREROUTING -i $VPN_IFACE -p tcp -j REDIRECT --to-ports 12345

echo "[+] Kiểm tra IP hiện tại..."
IP_NOW=$(curl -s --max-time 10 https://ipinfo.io/ip)
echo "🔍 IP hiện tại: $IP_NOW"

if [[ "$IP_NOW" == "$PROXY_IP" ]]; then
  echo "[✅] Proxy hoạt động đúng!"
else
  echo "[❌] Proxy lỗi hoặc IP không khớp!"
  send_alert "🚨 *Cảnh báo từ VPS*\nProxy SOCKS5 có thể bị lỗi!\nIP hiện tại: \`$IP_NOW\`\nKhông trùng với IP proxy: \`$PROXY_IP\`"
fi

echo "[+] Tạo script kiểm tra proxy định kỳ tại $CHECK_SCRIPT..."
cat > "$CHECK_SCRIPT" <<EOF
#!/bin/bash
PROXY_IP="$PROXY_IP"
TG_TOKEN="$TG_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"

send_alert() {
  curl -s -X POST "https://api.telegram.org/bot\$TG_TOKEN/sendMessage" \\
    -d chat_id="\$TG_CHAT_ID" \\
    -d parse_mode="Markdown" \\
    -d text="\$1"
}

IP_NOW=\$(curl -s --max-time 10 https://ipinfo.io/ip)
if [[ "\$IP_NOW" != "\$PROXY_IP" ]]; then
  send_alert "🚨 *Cảnh báo định kỳ*\nProxy SOCKS5 có thể lỗi!\nIP hiện tại: \\\`\$IP_NOW\\\`\nKhông khớp với proxy: \\\`\$PROXY_IP\\\`"
fi
EOF

chmod +x "$CHECK_SCRIPT"

echo "[+] Thêm cron job kiểm tra mỗi 5 phút..."
(crontab -l 2>/dev/null; echo "$CRON_JOB") | sort -u | crontab -

echo "✅ Hoàn tất cài đặt proxy + theo dõi định kỳ!"
