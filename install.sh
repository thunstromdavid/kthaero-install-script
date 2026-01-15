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

echo "[1/7] Uppdaterar systemet..."
apt-get update && apt-get upgrade -y

echo "[2/7] Installerar beroenden (git, build-tools, python)..."
apt-get install -y git meson ninja-build pkg-config gcc g++ systemd python3-pip

echo "[3/7] Installerar Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
# Aktivera tjänsten
echo "[3/7] Startar Tailscale..."
systemctl enable --now tailscaled

echo "[4/7] Konfigurerar Serieport (UART)..."
# Vi använder raspi-config icke-interaktivt för att:
# 1. Stänga av login shell över serial (så RPi inte pratar med Pixhawk som en terminal)
# 2. Slå PÅ serial hårdvaran
if command -v raspi-config > /dev/null; then
    raspi-config nonint do_serial 1
    echo "   -> Serial port konfigurerad (Shell: NEJ, Hårdvara: JA)"
else
    echo "VARNING: raspi-config hittades inte. Du måste manuellt aktivera Serial Port och stänga av Serial Console i /boot/config.txt och /boot/cmdline.txt"
fi

echo "[5/7] Hämtar och installerar mavlink-router..."
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

echo "[6/7] Skapar konfigurationsfil (/etc/mavlink-router/main.conf)..."

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

echo "[7/7] Startar tjänster..."
# Ladda om systemd för att hitta mavlink-router servicen
systemctl daemon-reload
systemctl enable mavlink-router
systemctl restart mavlink-router

echo "=================================================="
echo "INSTALLATION KLAR!"
echo "=================================================="
echo "Nästa steg:"
echo "1. Skriv 'sudo tailscale up' för att logga in på Tailscale (om du inte redan gjort det)."
echo "2. Koppla Pixhawk till GPIO 14 (TX), 15 (RX) och GND."
echo "3. Kontrollera att Pixhawk har Baud Rate 57600 på TELEM-porten."
echo "4. Starta Mission Planner och anslut med UDP på port 14550."
echo ""
echo "Om du behöver ändra IP senare, redigera: /etc/mavlink-router/main.conf"
