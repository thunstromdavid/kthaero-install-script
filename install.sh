#!/bin/bash

# Avbryt direkt om något går fel
set -e

echo "=================================================="
echo "  DRONE COMPANION INSTALLER (Pixhawk + 4G/Tailscale)"
echo "=================================================="

# Kolla att vi kör som root
if [ "$EUID" -ne 0 ]; then
  echo "Vänligen kör som root (använd sudo)"
  exit
fi

echo "[1/12] Konfigurerar swap för stabilitet..."
# Skapa 1GB swap om den inte finns (hjälper vid kompilering)
if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "   -> 1GB swap skapad och aktiverad"
else
    echo "   -> Swap finns redan"
fi

echo "[2/12] Uppdaterar systemet..."
apt-get update && apt-get upgrade -y

echo "Installerar grundverktyg (neovim, curl)..."
apt-get install -y neovim curl

echo "[3/12] Installerar beroenden (git, build-tools, python)..."
apt-get install -y git meson ninja-build pkg-config gcc g++ systemd python3-pip chrony ufw cmake libsystemd-dev systemd-dev usb-modeswitch usb-modeswitch-data gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly

echo "[4/12] Konfigurerar tidssynkronisering (chrony)..."
systemctl enable chrony
systemctl start chrony
echo "   -> NTP tidssynkronisering aktiverad"

echo "[5/12] Installerar Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
# Aktivera tjänsten
echo "[5/12] Startar Tailscale..."
systemctl enable --now tailscaled

echo "[6/12] Konfigurerar Serieport (UART)..."
# Vi använder raspi-config icke-interaktivt för att:
# 1. Stänga av login shell över serial (så RPi inte pratar med Pixhawk som en terminal)
# 2. Slå PÅ serial hårdvaran
if command -v raspi-config > /dev/null; then
    raspi-config nonint do_serial 1
    echo "   -> Serial port konfigurerad (Shell: NEJ, Hårdvara: JA)"
else
    echo "VARNING: raspi-config hittades inte. Du måste manuellt aktivera Serial Port och stänga av Serial Console i /boot/config.txt och /boot/cmdline.txt"
fi

# Inaktivera Bluetooth på UART (krävs för RPi 3/4/5 för pålitlig serial)
echo "[6/12] Inaktiverar Bluetooth på UART..."
if ! grep -q "dtoverlay=disable-bt" /boot/config.txt; then
    echo "dtoverlay=disable-bt" >> /boot/config.txt
    echo "   -> Bluetooth på UART inaktiverad"
else
    echo "   -> Bluetooth på UART redan inaktiverad"
fi

# Ta bort console från cmdline.txt om den finns
if [ -f /boot/cmdline.txt ]; then
    sed -i 's/console=serial0,[0-9]* //g' /boot/cmdline.txt
    sed -i 's/console=ttyAMA0,[0-9]* //g' /boot/cmdline.txt
    echo "   -> Serial console borttagen från cmdline.txt"
fi

# Stoppa och inaktivera hciuart tjänsten
systemctl disable hciuart 2>/dev/null || true
systemctl stop hciuart 2>/dev/null || true

echo "[7/12] Hämtar och installerar mavlink-router..."
cd /tmp
rm -rf mavlink-router
git clone https://github.com/mavlink-router/mavlink-router.git
cd mavlink-router
git submodule update --init --recursive

# Bygg och installera
meson setup build .
ninja -C build
ninja -C build install

# Skapa katalog för config om den inte finns
mkdir -p /etc/mavlink-router

echo "=================================================="
echo "KONFIGURATION AV MISSION PLANNER"
echo "För att detta ska fungera måste vi veta Tailscale-IP"
echo "på din dator (Ground Control Station)."
echo "=================================================="
read -p "Ange din dators Tailscale IP (t.ex. 100.x.x.x): " GCS_IP

echo "[8/12] Installerar Python MAVLink-bibliotek..."
pip3 install --break-system-packages pymavlink MAVProxy 2>/dev/null || pip3 install pymavlink MAVProxy
echo "   -> pymavlink och MAVProxy installerade"

echo "[9/12] Skapar konfigurationsfil (/etc/mavlink-router/main.conf)..."

cat > /etc/mavlink-router/main.conf <<EOF
[General]
# Lyssnar efter inkommande TCP-anslutningar (bra för felsökning lokalt)
TcpServerPort=5760
ReportStats=false

[UartEndpoint pixhawk]
# /dev/serial0 är standard för GPIO 14/15 på RPi 3/4/Zero
Device = /dev/serial0
# ÄNDRA HÄR OM DIN PIXHAWK HAR ANNAN BAUD RATE (Vanligt är 57600, 115200 eller 921600)
Baud = 57600

[UdpEndpoint mission_planner]
Mode = Normal
Address = $GCS_IP
Port = 14550
EOF

echo "   -> Konfiguration sparad."

echo "[10/12] Konfigurerar brandvägg (UFW)..."
ufw allow 22/tcp comment 'SSH'
ufw allow 5760/tcp comment 'MAVLink TCP'
ufw allow 14550/udp comment 'MAVLink UDP GCS'
ufw allow 14551/udp comment 'MAVLink UDP API'
ufw --force enable
echo "   -> Brandvägg konfigurerad"

echo "[11/12] Konfigurerar watchdog för auto-återställning..."
# Aktivera hardware watchdog
if ! grep -q "dtparam=watchdog=on" /boot/config.txt; then
    echo "dtparam=watchdog=on" >> /boot/config.txt
fi

# Installera watchdog-tjänsten
apt-get install -y watchdog

# Konfigurera watchdog
cat > /etc/watchdog.conf <<WDEOF
watchdog-device = /dev/watchdog
watchdog-timeout = 15
max-load-1 = 24
interval = 10
WDEOF

systemctl enable watchdog
systemctl start watchdog
echo "   -> Hardware watchdog aktiverad (15s timeout)"

# Konfigurera loggrotation för mavlink-router
echo "[11/12] Konfigurerar loggrotation..."
cat > /etc/logrotate.d/mavlink-router <<LREOF
/var/log/mavlink-router/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
LREOF
echo "   -> Loggrotation konfigurerad"

echo "[12/12] Startar tjänster..."
# Ladda om systemd för att hitta mavlink-router servicen
systemctl daemon-reload
systemctl enable mavlink-router
systemctl restart mavlink-router

echo "=================================================="
echo "INSTALLATION KLAR!"
echo "=================================================="
echo "Nästa steg:"
echo "1. STARTA OM RASPBERRY PI för att aktivera UART-ändringar (sudo reboot)"
echo "2. Skriv 'sudo tailscale up' för att logga in på Tailscale."
echo "3. Koppla Pixhawk till GPIO 14 (TX), 15 (RX) och GND."
echo "4. Kontrollera att Pixhawk har Baud Rate 57600 på TELEM-porten."
echo "5. Starta Mission Planner och anslut med UDP på port 14550."
echo ""
echo "Installerade funktioner:"
echo "  - MAVLink router (mavlink-router)"
echo "  - Tailscale VPN för fjärråtkomst"
echo "  - Hardware watchdog (auto-reboot vid hängning)"
echo "  - Brandvägg (UFW) med MAVLink-portar öppna"
echo "  - Python MAVLink-bibliotek (pymavlink, MAVProxy)"
echo "  - Tidssynkronisering (chrony)"
echo "  - Loggrotation (förhindrar full disk)"
echo ""
echo "Användbara kommandon:"
echo "  - sudo systemctl status mavlink-router  # Kolla MAVLink status"
echo "  - mavproxy.py --master=/dev/serial0    # Testa MAVLink direkt"
echo "  - sudo tail -f /var/log/syslog         # Se systemloggar"
echo ""
echo "Om du behöver ändra IP senare, redigera: /etc/mavlink-router/main.conf"
echo ""
echo "VIKTIGT: Starta om nu med 'sudo reboot' för att aktivera alla ändringar!"
