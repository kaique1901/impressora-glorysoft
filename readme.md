# Manual Operacional — Glorysoft Kiosk
**Ubuntu 24.04 LTS | Máquina de Conferência**

---

## Visão Geral

| Componente | Função |
|---|---|
| Chrome (kiosk) | Abre `glorysoft.com.br` em tela cheia no boot |
| impressora-glorysoft | App de impressão Delphi FMX (display virtual :99) |
| CUPS | Gerenciador de impressoras (porta 631) |
| x11vnc | Acesso remoto à tela (porta 5900) |
| xvfb-glorysoft | Display virtual para o app de impressão |

---

## Deploy em Nova Máquina

```bash
# 1. Baixar o script direto do repositório
curl -O https://raw.githubusercontent.com/kaique1901/impressora-glorysoft/main/setup-conferencia.sh

# 2. Torna o arquivo executável
chmod +x setup-conferencia.sh

# 3. Executar (pede senha do VNC durante a instalação)
sudo bash setup-conferencia.sh cifal

# 4. Reiniciar
sudo reboot
```

> O script instala todos os pacotes, configura o kiosk, clona o repositório e sobe os serviços automaticamente.

---

## Serviços — Comandos Essenciais

### Impressora Glorysoft
```bash
sudo systemctl restart impressora-glorysoft   # reiniciar
sudo systemctl stop impressora-glorysoft      # parar
sudo systemctl start impressora-glorysoft     # iniciar
sudo systemctl status impressora-glorysoft    # verificar status
journalctl -u impressora-glorysoft -f         # logs em tempo real
```

### CUPS
```bash
sudo systemctl restart cups
sudo systemctl status cups
# Interface web: http://IP_DA_MAQUINA:631
```

### VNC
```bash
sudo systemctl restart x11vnc
sudo systemctl status x11vnc
```

---

## Abrir App de Impressão na Tela

**Via teclado (na máquina física):**
```
Ctrl+Alt+P  → abre/fecha o app por cima do Chrome
Ctrl+Alt+P  → pressionar novamente volta para o Chrome
```

**Via SSH:**
```bash
DISPLAY=:0 XAUTHORITY=/home/cifal/.Xauthority /home/cifal/toggle-glorysoft.sh
```

---

## Alternar entre Interface Gráfica e Terminal

```
Ctrl+Alt+F2   → vai para terminal de texto (TTY2)
Ctrl+Alt+F1   → volta para interface gráfica (Chrome)
```

No terminal, faça login com usuário e senha normalmente.

---

## Acesso Remoto via VNC

De qualquer máquina na mesma rede, conecte com um cliente VNC:
```
IP: 192.168.0.22
Porta: 5900
```

Clientes recomendados: RealVNC Viewer, TigerVNC.

**Para enviar atalho de teclado via SSH em vez do VNC:**
```bash
DISPLAY=:0 XAUTHORITY=/home/cifal/.Xauthority xdotool key ctrl+alt+p
```

---

## Conexão Wi-Fi via Terminal

```bash
# Listar redes disponíveis
nmcli device wifi list

# Conectar em uma rede
nmcli device wifi connect "NOME_DA_REDE" password "SENHA_DA_REDE"

# Verificar conexão ativa
nmcli connection show --active

# Ver IP atual
hostname -I
```

---

## Atualizar App de Impressão

```bash
cd ~/impressora-glorysoft
git pull
chmod +x GlorysoftPrinterFmx

# Remove libc conflitante (pode voltar após git pull)
rm -f lib/libc.so lib/libc.so.6

# Usa libpq do sistema (compatível com Ubuntu 24.04)
cp /usr/lib/x86_64-linux-gnu/libpq.so.5 lib/libpq.so
cp /usr/lib/x86_64-linux-gnu/libpq.so.5 lib/libpq.so.5

# Atualiza pasta libs
cp lib/libcrypto.so* lib/libssl.so* lib/libssl3.so lib/libplist*.so* libs/
cp lib/libpq.so* libs/

sudo systemctl restart impressora-glorysoft
sudo systemctl status impressora-glorysoft
```

> **Atenção:** Nunca use o `libpq.so` que vem no repositório — ele foi compilado para Ubuntu 22.04 e é incompatível com o Ubuntu 24.04. Sempre substitua pelo do sistema após o `git pull`.

---

## Diagnóstico Rápido

```bash
# Ver todos os serviços de uma vez
systemctl status impressora-glorysoft xvfb-glorysoft cups x11vnc

# Verificar porta VNC aberta
ss -tlnp | grep 5900

# Verificar display virtual ativo
ls /tmp/.X99-lock && echo "Xvfb ativo" || echo "Xvfb inativo"

# Testar conectividade
ping -c 3 glorysoft.com.br
```

---

## Reinicialização e Desligamento

```bash
sudo reboot       # reinicia a máquina
sudo poweroff     # desliga a máquina
```

---

*Repositório do app: https://github.com/kaique1901/impressora-glorysoft*
