#!/bin/bash
set -e

# =============================================================
# Setup Conferencia - Glorysoft Kiosk
# Ubuntu 24.04 LTS
# =============================================================

USUARIO="${1:-cifal}"
HOME_DIR="/home/$USUARIO"
APP_DIR="$HOME_DIR/impressora-glorysoft"
URL_KIOSK="https://glorysoft.com.br/"
REPO="https://github.com/kaique1901/impressora-glorysoft.git"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[..] $1${NC}"; }
erro() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && erro "Execute como root: sudo bash $0 $USUARIO"

# Solicitar senha do VNC no início
echo ""
while true; do
    read -rsp " Digite a senha do VNC (mínimo 6 caracteres): " VNC_SENHA; echo ""
    read -rsp " Confirme a senha do VNC: " VNC_SENHA2; echo ""
    [ "$VNC_SENHA" = "$VNC_SENHA2" ] && [ ${#VNC_SENHA} -ge 6 ] && break
    echo -e "${RED}Senhas diferentes ou muito curtas. Tente novamente.${NC}"
done
id "$USUARIO" &>/dev/null || erro "Usuário '$USUARIO' não existe. Crie-o primeiro."

echo ""
echo "============================================="
echo " Setup Glorysoft Kiosk"
echo " Usuário : $USUARIO"
echo " Kiosk   : $URL_KIOSK"
echo "============================================="
echo ""

# -------------------------------------------------------------
# 1. Pacotes
# -------------------------------------------------------------
info "Instalando pacotes..."
apt update -qq
apt install -y \
    xorg openbox unclutter xvfb \
    cups cups-client \
    wmctrl xdotool \
    git curl wget \
    x11vnc patchelf \
    libpq5 libpq-dev libldap2 2>&1 | grep -E "^(Get|Inst|Err)" || true

# Google Chrome
if ! which google-chrome &>/dev/null; then
    info "Instalando Google Chrome..."
    wget -q -O /tmp/chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    apt install -y /tmp/chrome.deb
    rm /tmp/chrome.deb
fi
ok "Pacotes instalados"

# -------------------------------------------------------------
# 2. Auto-login no TTY1
# -------------------------------------------------------------
info "Configurando auto-login..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USUARIO --noclear %I \$TERM
EOF
ok "Auto-login configurado"

# -------------------------------------------------------------
# 3. Kiosk — .bash_profile e .xinitrc
# -------------------------------------------------------------
info "Configurando kiosk..."
cat > "$HOME_DIR/.bash_profile" << 'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF

cat > "$HOME_DIR/.xinitrc" << XINITRC
#!/bin/bash
xset -dpms
xset s off
xset s noblank
unclutter -idle 5 &
openbox &
sleep 1
exec google-chrome \\
    --kiosk \\
    --noerrdialogs \\
    --disable-infobars \\
    --no-first-run \\
    --disable-session-crashed-bubble \\
    --disable-restore-session-state \\
    --disable-translate \\
    --disable-features=TranslateUI \\
    "$URL_KIOSK"
XINITRC

chmod +x "$HOME_DIR/.xinitrc"
ok "Kiosk configurado"

# -------------------------------------------------------------
# 4. Clonar app de impressão
# -------------------------------------------------------------
info "Clonando repositório da impressora..."
if [ -d "$APP_DIR/.git" ]; then
    git -C "$APP_DIR" pull
else
    rm -rf "$APP_DIR"
    git clone "$REPO" "$APP_DIR"
fi

chmod +x "$APP_DIR/GlorysoftPrinterFmx"

# Remove libc do repositório (conflita com o sistema)
rm -f "$APP_DIR/lib/libc.so" "$APP_DIR/lib/libc.so.6"

# Substitui libpq do repo pelo do sistema (compatível com Ubuntu 24.04)
cp /usr/lib/x86_64-linux-gnu/libpq.so.5 "$APP_DIR/lib/libpq.so"
cp /usr/lib/x86_64-linux-gnu/libpq.so.5 "$APP_DIR/lib/libpq.so.5"

# Registra pasta lib no ldconfig para resolução de dependências
echo "$APP_DIR/lib" > /etc/ld.so.conf.d/glorysoft.conf
ldconfig

# Pasta libs filtrada para LD_LIBRARY_PATH (sem libc)
mkdir -p "$APP_DIR/libs"
cp "$APP_DIR/lib/libcrypto.so"*  "$APP_DIR/libs/" 2>/dev/null || true
cp "$APP_DIR/lib/libssl.so"*     "$APP_DIR/libs/" 2>/dev/null || true
cp "$APP_DIR/lib/libssl3.so"     "$APP_DIR/libs/" 2>/dev/null || true
cp "$APP_DIR/lib/libpq.so"*      "$APP_DIR/libs/" 2>/dev/null || true
cp "$APP_DIR/lib/libplist"*.so*  "$APP_DIR/libs/" 2>/dev/null || true
ok "Repositório clonado"

# -------------------------------------------------------------
# 5. Script toggle Ctrl+Alt+P
# -------------------------------------------------------------
info "Criando script de toggle..."
cat > "$HOME_DIR/toggle-glorysoft.sh" << 'TOGGLE'
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/USUARIO_PLACEHOLDER/.Xauthority
export LD_LIBRARY_PATH=/home/USUARIO_PLACEHOLDER/impressora-glorysoft/libs
APP_DIR=/home/USUARIO_PLACEHOLDER/impressora-glorysoft
APP=$APP_DIR/GlorysoftPrinterFmx

WID=$(xdotool search --classname "GlorysoftPrinterFmx" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    xdotool windowclose "$WID"
    sleep 1
    cd "$APP_DIR" && DISPLAY=:99 "$APP" &
else
    pkill -f GlorysoftPrinterFmx 2>/dev/null
    sleep 1
    cd "$APP_DIR" && "$APP" &
fi
TOGGLE

sed -i "s/USUARIO_PLACEHOLDER/$USUARIO/g" "$HOME_DIR/toggle-glorysoft.sh"
chmod +x "$HOME_DIR/toggle-glorysoft.sh"
ok "Script toggle criado"

# -------------------------------------------------------------
# 6. Openbox — atalhos de teclado
# -------------------------------------------------------------
info "Configurando atalhos do openbox..."
mkdir -p "$HOME_DIR/.config/openbox"
cat > "$HOME_DIR/.config/openbox/rc.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <keyboard>
    <keybind key="C-A-p">
      <action name="Execute">
        <command>$HOME_DIR/toggle-glorysoft.sh</command>
      </action>
    </keybind>
    <keybind key="C-A-F2">
      <action name="Execute">
        <command>x-terminal-emulator</command>
      </action>
    </keybind>
  </keyboard>
</openbox_config>
EOF
ok "Atalhos configurados"

# -------------------------------------------------------------
# 7. Serviço Xvfb
# -------------------------------------------------------------
info "Criando serviço Xvfb..."
cat > /etc/systemd/system/xvfb-glorysoft.service << 'EOF'
[Unit]
Description=Xvfb virtual display para Glorysoft
After=network.target

[Service]
Type=simple
User=USUARIO_PLACEHOLDER
ExecStartPre=/bin/bash -c 'rm -f /tmp/.X99-lock'
ExecStart=/usr/bin/Xvfb :99 -screen 0 1024x768x24
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sed -i "s/USUARIO_PLACEHOLDER/$USUARIO/g" /etc/systemd/system/xvfb-glorysoft.service
ok "Serviço Xvfb criado"

# -------------------------------------------------------------
# 8. Serviço impressora-glorysoft
# -------------------------------------------------------------
info "Criando serviço impressora-glorysoft..."
cat > /etc/systemd/system/impressora-glorysoft.service << EOF
[Unit]
Description=Glorysoft Printer Service
After=network.target cups.service xvfb-glorysoft.service
Requires=xvfb-glorysoft.service

[Service]
Type=simple
User=$USUARIO
WorkingDirectory=$APP_DIR
Environment=DISPLAY=:99
Environment=LD_LIBRARY_PATH=$APP_DIR/libs
ExecStart=$APP_DIR/GlorysoftPrinterFmx
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
ok "Serviço impressora criado"

# -------------------------------------------------------------
# 9. CUPS
# -------------------------------------------------------------
info "Configurando CUPS..."
systemctl enable cups
systemctl start cups
cupsctl --remote-admin --remote-any --share-printers
usermod -aG lpadmin "$USUARIO"
ok "CUPS configurado"

# -------------------------------------------------------------
# 10. VNC Server
# -------------------------------------------------------------
info "Configurando VNC..."
mkdir -p "$HOME_DIR/.vnc"
x11vnc -storepasswd "$VNC_SENHA" "$HOME_DIR/.vnc/passwd"
chmod 600 "$HOME_DIR/.vnc/passwd"
chown -R "$USUARIO:$USUARIO" "$HOME_DIR/.vnc"

cat > /etc/systemd/system/x11vnc.service << EOF
[Unit]
Description=VNC Server para tela do quiosque
After=graphical.target

[Service]
Type=simple
User=$USUARIO
Environment=DISPLAY=:0
Environment=XAUTHORITY=$HOME_DIR/.Xauthority
ExecStart=/usr/bin/x11vnc -display :0 -auth $HOME_DIR/.Xauthority -forever -rfbauth $HOME_DIR/.vnc/passwd -rfbport 5900
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
ok "VNC configurado"

# -------------------------------------------------------------
# 11. Permissões e serviços
# -------------------------------------------------------------
info "Ajustando permissões..."
chown -R "$USUARIO:$USUARIO" "$HOME_DIR"

info "Ativando serviços..."
systemctl daemon-reload
systemctl enable xvfb-glorysoft impressora-glorysoft x11vnc
systemctl start xvfb-glorysoft impressora-glorysoft x11vnc

# -------------------------------------------------------------
# Resumo
# -------------------------------------------------------------
echo ""
echo "============================================="
echo -e " ${GREEN}Setup concluído com sucesso!${NC}"
echo "============================================="
echo ""
echo " Serviços ativos:"
systemctl is-active xvfb-glorysoft      && echo -e "  ${GREEN}✓${NC} xvfb-glorysoft" || echo -e "  ${RED}✗${NC} xvfb-glorysoft"
systemctl is-active impressora-glorysoft && echo -e "  ${GREEN}✓${NC} impressora-glorysoft" || echo -e "  ${RED}✗${NC} impressora-glorysoft"
systemctl is-active cups                 && echo -e "  ${GREEN}✓${NC} cups" || echo -e "  ${RED}✗${NC} cups"
systemctl is-active x11vnc               && echo -e "  ${GREEN}✓${NC} x11vnc (VNC)" || echo -e "  ${RED}✗${NC} x11vnc (VNC)"
echo ""
echo " Atalhos de teclado:"
echo "   Ctrl+Alt+P  → abre/fecha app Glorysoft na tela"
echo "   Ctrl+Alt+F2 → abre terminal"
echo "   Ctrl+Alt+F2 → outro TTY (texto)"
echo ""
echo " CUPS disponível em: http://$(hostname -I | awk '{print $1}'):631
 VNC disponível em : $(hostname -I | awk '{print $1}'):5900"
echo ""
echo " Reinicie para ativar o kiosk: sudo reboot"
echo ""
