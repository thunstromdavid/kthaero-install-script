# Drone Companion Installer

**Styr din drönare via 4G/LTE med Raspberry Pi som länk mellan Pixhawk och din dator.**

Detta installationsscript sätter upp en Raspberry Pi som en "Companion Computer" för att vidarebefordra MAVLink-telemetri från en Pixhawk flight controller till din Ground Control Station (GCS) över internet via Tailscale VPN.

---

## 📋 Innehåll

- [Översikt](#översikt)
- [Hårdvarukrav](#hårdvarukrav)
- [Kopplingsschema](#kopplingsschema)
- [Installation](#installation)
- [Konfiguration på datorn (GCS)](#konfiguration-på-datorn-gcs)
- [Felsökning](#felsökning)
- [Dataflöde](#dataflöde)

---

## Översikt

```
┌─────────────┐    UART/Serial    ┌───────────────┐    4G/Tailscale    ┌─────────────────┐
│   Pixhawk   │◄─────────────────►│ Raspberry Pi  │◄──────────────────►│ Din Dator (GCS) │
│  (Drönare)  │   GPIO 14/15      │ mavlink-router│      UDP 14550     │ Mission Planner │
└─────────────┘                   └───────────────┘                    └─────────────────┘
```

**Vad scriptet installerar:**
- ✅ MAVLink Router - vidarebefordrar telemetri
- ✅ Tailscale VPN - säker tunnel över internet
- ✅ Hardware Watchdog - automatisk omstart vid hängning
- ✅ Brandvägg (UFW) - säkerhet med rätt portar öppna
- ✅ Python MAVLink-bibliotek - för framtida scripting
- ✅ Tidssynkronisering - korrekta loggtidsstämplar
- ✅ UART-konfiguration - inaktiverar Bluetooth på serial

---

## Hårdvarukrav

| Komponent | Beskrivning |
|-----------|-------------|
| **Raspberry Pi** | Model 3B+, 4, eller 5 (med WiFi/4G-kapacitet) |
| **Pixhawk** | Valfri version (Pixhawk 4, Cube, etc.) |
| **4G-modem** | USB-dongel eller HAT (t.ex. Huawei E3372, Waveshare SIM7600) |
| **MicroSD-kort** | Minst 16GB, Class 10 eller snabbare |
| **Strömförsörjning** | Stabil 5V 3A till RPi (separat från Pixhawk) |
| **Kablar** | Dupont-kablar för GPIO-anslutning |

---

## Kopplingsschema

### Pixhawk ↔ Raspberry Pi (UART)

Använd **TELEM 2**-porten på Pixhawk:

```
Pixhawk TELEM 2          Raspberry Pi GPIO
─────────────────        ─────────────────
     TX  ──────────────►  GPIO 15 (RX)
     RX  ◄──────────────  GPIO 14 (TX)
    GND  ◄─────────────►  GND
    
⚠️  Koppla INTE 5V/VCC mellan enheterna!
```

### GPIO Pinout (Raspberry Pi)

```
                    ┌─────────────────────┐
                    │     Raspberry Pi    │
                    │      GPIO Header    │
                    ├─────────────────────┤
           3.3V  [1]│●                   ●│[2]  5V
          GPIO2  [3]│●                   ●│[4]  5V
          GPIO3  [5]│●                   ●│[6]  GND ◄── Pixhawk GND
            ...     │                     │
   Pixhawk RX ► [8] │●  GPIO14 (TX)      ●│[9]  
   Pixhawk TX ► [10]│●  GPIO15 (RX)      ●│[11]
                    └─────────────────────┘
```

### Baud Rate

Kontrollera att Pixhawk TELEM 2-porten är inställd på samma baud rate som i konfigurationen (standard: **57600**).

I Mission Planner/QGroundControl:
- Parameter: `SERIAL2_BAUD` = 57 (för 57600)
- Eller: `SERIAL2_BAUD` = 921 (för 921600, snabbare men kräver ändring i config)

---

## Installation

### 1. Förbered Raspberry Pi

```bash
# Ladda ner Raspberry Pi OS Lite (64-bit) och flasha till SD-kort
# Använd Raspberry Pi Imager: https://www.raspberrypi.com/software/

# Aktivera SSH vid första boot:
# Skapa en tom fil "ssh" på boot-partitionen
```

### 2. Kör installationsscriptet

```bash
# Logga in på din Raspberry Pi via SSH
ssh pi@<raspberry-pi-ip>

# Klona repot
git clone https://github.com/thunstromdavid/kthaero-install-script.git
cd kthaero-install-script

# Kör installationen (tar ca 10-15 minuter)
sudo bash install.sh
```

### 3. Under installationen

Scriptet kommer fråga efter din dators **Tailscale IP-adress**. 
Du hittar den i Tailscale-appen på din dator (ser ut som `100.x.x.x`).

### 4. Efter installationen

```bash
# VIKTIGT: Starta om för att aktivera UART-ändringar
sudo reboot

# Efter omstart - logga in på Tailscale
sudo tailscale up
```

Följ länken som visas för att autentisera enheten i ditt Tailscale-nätverk.

---

## Konfiguration på datorn (GCS)

### Steg 1: Installera Tailscale

Ladda ner och installera Tailscale på din dator:
- **Windows/Mac/Linux**: https://tailscale.com/download

Logga in med samma konto som du använde på Raspberry Pi.

### Steg 2: Välj Ground Control Station

#### Alternativ A: Mission Planner (Windows) - Rekommenderas för avancerade användare
- Ladda ner: https://ardupilot.org/planner/docs/mission-planner-installation.html

#### Alternativ B: QGroundControl (Windows/Mac/Linux) - Enklare gränssnitt
- Ladda ner: https://docs.qgroundcontrol.com/master/en/getting_started/download_and_install.html

### Steg 3: Anslut till drönaren

#### Mission Planner (UDP - Automatisk)
1. Starta Mission Planner
2. Välj **UDP** i connection dropdown (överst till höger)
3. Klicka **Connect**
4. Ange port: `14550`
5. Telemetrin ska börja strömma in automatiskt

#### QGroundControl (UDP - Automatisk)
1. Starta QGroundControl
2. Drönaren bör dyka upp automatiskt (lyssnar på port 14550 som standard)
3. Om inte: Gå till **Application Settings** → **Comm Links** → **Add**
   - Type: UDP
   - Port: 14550

#### Alternativ: TCP-anslutning
Om UDP inte fungerar (vissa nätverk blockerar), använd TCP istället:

1. I GCS, skapa ny anslutning:
   - Type: **TCP**
   - Host: `<Raspberry Pi Tailscale IP>` (t.ex. 100.x.x.x)
   - Port: `5760`

---

## Felsökning

### Kontrollera MAVLink Router status

```bash
# Se om tjänsten körs
sudo systemctl status mavlink-router

# Se loggar
sudo journalctl -u mavlink-router -f

# Testa serieporten manuellt
mavproxy.py --master=/dev/serial0 --baudrate=57600
```

### Kontrollera Tailscale

```bash
# Se Tailscale status
tailscale status

# Se din Tailscale IP
tailscale ip -4

# Pinga din dator
ping <din-dators-tailscale-ip>
```

### Vanliga problem

| Problem | Lösning |
|---------|---------|
| Ingen telemetri | Kontrollera kablar och baud rate |
| "Permission denied" på /dev/serial0 | Kör `sudo usermod -a -G dialout $USER` och logga ut/in |
| Tailscale når inte datorn | Kontrollera att båda är i samma Tailscale-nätverk |
| MAVLink Router startar inte | Kolla `sudo journalctl -u mavlink-router` för fel |
| Hög latency | Kontrollera 4G-signalstyrka, överväg extern antenn |

### Ändra konfiguration

```bash
# Redigera MAVLink Router config
sudo nano /etc/mavlink-router/main.conf

# Starta om efter ändringar
sudo systemctl restart mavlink-router
```

### Ändra baud rate

Om din Pixhawk använder en annan baud rate (t.ex. 115200 eller 921600):

```bash
sudo nano /etc/mavlink-router/main.conf
# Ändra "Baud = 57600" till din baud rate
sudo systemctl restart mavlink-router
```

---

## Dataflöde

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              DATAFLÖDE                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   DRÖNARE                         INTERNET                      DIN DATOR   │
│   ────────                        ────────                      ──────────  │
│                                                                              │
│   ┌─────────┐     Serial      ┌─────────────┐    Tailscale    ┌──────────┐ │
│   │ Pixhawk │◄───(57600)─────►│ Raspberry Pi│◄───(4G/LTE)────►│   GCS    │ │
│   │  FC     │   /dev/serial0  │  mavlink-   │   UDP:14550     │ Mission  │ │
│   │         │                 │  router     │                 │ Planner  │ │
│   └─────────┘                 └─────────────┘                 └──────────┘ │
│       │                             │                              │        │
│       │ Sensorer                    │ Watchdog                     │ Karta  │
│       │ GPS                         │ Firewall                     │ Video  │
│       │ Motorer                     │ Logging                      │ Param  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Säkerhet

⚠️ **Viktigt för flygning över 4G:**

1. **Testa alltid på marken först** - verifiera full kontroll innan flygning
2. **Ha en RC-sändare som backup** - 4G kan tappa signal
3. **Ställ in failsafe** - Return-to-Launch (RTL) vid signalförlust
4. **Följ lokala drönarlagar** - BVLOS-flygning kräver ofta tillstånd
5. **Övervaka latency** - över 500ms kan göra manuell styrning svår

---

## Användbara kommandon

```bash
# MAVLink Router
sudo systemctl status mavlink-router    # Status
sudo systemctl restart mavlink-router   # Starta om
sudo journalctl -u mavlink-router -f    # Loggar i realtid

# Tailscale
tailscale status                        # Anslutningsstatus
tailscale ip -4                         # Visa IP
sudo tailscale down                     # Koppla från
sudo tailscale up                       # Anslut igen

# System
htop                                    # Resursanvändning
dmesg | tail                            # Kernel-loggar
vcgencmd measure_temp                   # CPU-temperatur

# MAVProxy (manuell test)
mavproxy.py --master=/dev/serial0 --baudrate=57600
```

---

## Licens

MIT License - Använd fritt för hobbyändamål.

---

## Bidra

Pull requests välkomnas! Skapa en issue om du hittar buggar eller har förslag.

---

**Skapad av [thunstromdavid](https://github.com/thunstromdavid)** | KTHAero Project
