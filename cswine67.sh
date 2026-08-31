#!/bin/bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.cache/wine67"
WINE_BIN="$INSTALL_DIR/bin/wine"

APP_URL="https://baixesoft.com/servidor_download/Counter-Strike_1.6_Portable.exe"
APP_NAME="Counter-Strike_1.6_Portable.exe"

APP_DIR="$SCRIPT_DIR/apps"
APP_PATH="$APP_DIR/$APP_NAME"

# CORES
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'

# FUNÇÕES DE LOG
erro()  { echo -e "${RED}❌ $1${RESET}" >&2; exit 1; }
ok()    { echo -e "${GREEN}✔  $1${RESET}"; }
info()  { echo -e "${CYAN}➜  $1${RESET}"; }
aviso() { echo -e "${YELLOW}⚠  $1${RESET}"; }

# Limpar aspas de strings de entrada
limpar_entrada() {
    local entrada="$1"
    entrada="${entrada//\'/}"
    entrada="${entrada//\"/}"
    entrada="${entrada# }"
    entrada="${entrada% }"
    echo "$entrada"
}

spinner() {
    local pid=$1 msg="${2:-Carregando...}"
    local spin='/-\|'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r  ${CYAN}[${spin:$i:1}]${RESET}  ${msg}"
        i=$(( (i+1) % ${#spin} ))
        sleep 0.1
    done
    echo -ne "\r  ${GREEN}[✔]${RESET}  ${msg}\n"
}

obter_url_wine() {
    local url
    url=$(curl -s --max-time 15 "https://api.github.com/repos/Kron4ek/Wine-Builds/releases/latest" 2>/dev/null | \
          grep -o "https://github.com/Kron4ek/Wine-Builds/releases/download/.*/wine-.*-amd64-wow64.tar.xz" | head -n1)

    if [ -z "$url" ]; then
        aviso "API do GitHub indisponível — usando versão fallback"
        url="https://github.com/Kron4ek/Wine-Builds/releases/download/11.10/wine-11.10-amd64-wow64.tar.xz"
    fi
    echo "$url"
}


# Checagens de dependências
command -v curl &>/dev/null || erro "Instale o comando 'curl' para continuar."
command -v tar  &>/dev/null || erro "'tar' não encontrado."
command -v bash &>/dev/null || erro "'bash' não encontrado."

# Verifica versão do bash (mapfile requer bash >= 4.0)
(( BASH_VERSINFO[0] >= 4 )) || erro "Bash 4.0 ou superior necessário (versão atual: $BASH_VERSION)"

mkdir -p "$INSTALL_DIR"

# EXIBIR BANNER
{
    echo -e "${MAGENTA}${BOLD}"
    echo "   ██████╗███████╗    ██╗    ██╗██╗███╗   ██╗███████╗ ██████╗ ███████╗"
    echo "  ██╔════╝██╔════╝    ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚════██║"
    echo "  ██║     ███████╗    ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝"
    echo "  ██║     ╚════██║    ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ "
    echo "  ╚██████╗███████║    ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
    echo "   ╚═════╝╚══════╝     ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
    echo -e "${RESET}"
    echo -e "  ${DIM}Counter-Strike 1.6 Portable — sem sudo${RESET}"
    echo -e "  ${DIM}Base: $INSTALL_DIR${RESET}"
    echo ""
}


# VERIFICAR ESPAÇO EM DISCO ANTES DE BAIXAR
verificar_espaco() {
    local destino="$1"
    local minimo_mb="${2:-1500}"  # Proton/Wine pode passar de 1 GB
    local disponivel_mb
    disponivel_mb=$(df -m "$destino" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$disponivel_mb" ] && [ "$disponivel_mb" -lt "$minimo_mb" ]; then
        erro "Espaço insuficiente em disco: ${disponivel_mb}MB disponíveis, mínimo ${minimo_mb}MB necessários."
    fi
}

baixar() {
    local url="$1" dest="$2" nome="$3"

    verificar_espaco "$(dirname "$dest")"

    info "Baixando $nome..."
    # -# mostra barra de progresso no terminal
    if ! curl -L --max-time 600 -# -o "$dest" "$url"; then
        rm -f "$dest"
        erro "Falha ao baixar $nome. Verifique sua conexão."
    fi

    # Checa se o servidor não retornou uma pagina de erro HTML
    if command -v file &>/dev/null && file "$dest" 2>/dev/null | grep -qi "HTML\|ASCII text"; then
        rm -f "$dest"
        erro "Servidor retornou erro ao baixar $nome (resposta não é um arquivo válido)."
    fi

    ok "Download concluído: $(du -h "$dest" | cut -f1)"
}

# BUSCAR .TAR LOCAL (pendrive, pasta do script, etc)
buscar_tar() {
    local padroes=("wine-*-amd64-wow64.tar.xz" "wine-*.tar.xz" "wine-*.tar.gz" "wine-*.tar")
    local resultado
    
    for padrao in "${padroes[@]}"; do
        resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" -type f -print -quit 2>/dev/null)
        [[ -n "$resultado" ]] && echo "$resultado" && return 0
        
        # Busca em drives/mídia com menor profundidade
        resultado=$(find /media /run/media /mnt -maxdepth 3 -name "$padrao" -type f -print -quit 2>/dev/null)
        [[ -n "$resultado" ]] && echo "$resultado" && return 0
    done
    return 1
}

# INSTALAR WINE
instalar_wine() {
    info "Instalando Wine Kron4ek wow64..."
    local GE_TAR
    GE_TAR=$(buscar_tar)

    if [ -n "$GE_TAR" ]; then
        ok "Arquivo local encontrado: $GE_TAR"
    else
        GE_TAR="$INSTALL_DIR/wine-kron4ek.tar.xz"
        local WINE_URL
        WINE_URL=$(obter_url_wine)
        baixar "$WINE_URL" "$GE_TAR" "Wine-Kron4ek wow64"
    fi

    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
        *)        TAR_FLAG="-xf";  TEST_FLAG="-tf"   ;;
    esac

    info "Verificando integridade do arquivo..."
    tar "$TEST_FLAG" "$GE_TAR" &>/dev/null || {
        rm -f "$GE_TAR"
        erro "Arquivo corrompido ou incompleto. Delete '$INSTALL_DIR' e tente novamente."
    }
    ok "Arquivo íntegro."

    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR" --strip-components=1 &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo Wine (pode demorar)..."
    wait "$tar_pid" || erro "Falha ao extrair. Delete '$INSTALL_DIR' e tente novamente."

    # Otimização: usar find com -print0 e xargs para chmod eficiente
    find "$INSTALL_DIR/bin" -type f -print0 2>/dev/null | xargs -0 chmod +x 2>/dev/null
    
    if [[ ! -f "$WINE_BIN" ]]; then
        local found
        found=$(find "$INSTALL_DIR" -name "wine" -type f -print -quit 2>/dev/null)
        if [[ -n "$found" ]]; then
            aviso "Binário encontrado em local inesperado: $found"
            WINE_BIN="$found"
        else
            erro "Wine não encontrado após extração. Estrutura de pastas inesperada em $INSTALL_DIR"
        fi
    fi

    ok "Wine instalado com sucesso!"
}

detectar_unity() {
    local exe_dir
    exe_dir="$(dirname "$1")"
    
    # Primeiro tenta encontrar UnityPlayer.dll diretamente
    [[ -f "$exe_dir/UnityPlayer.dll" ]] && return 0
    
    # Depois verifica por pastas _Data típicas do Unity
    find "$exe_dir" -maxdepth 1 -type d -name "*_Data" -print -quit 2>/dev/null | grep -q . && return 0
    
    return 1
}

# INSTALAÇÃO
if [[ ! -f "$WINE_BIN" ]]; then
    instalar_wine
fi

[[ ! -x "$WINE_BIN" ]] && chmod +x "$WINE_BIN"

ok "Wine: $WINE_BIN"
ok "Versão: $("$WINE_BIN" --version 2>/dev/null || echo 'desconhecida')"

# VARIÁVEIS DE AMBIENTE
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64:${LD_LIBRARY_PATH:-}"
export PATH="$INSTALL_DIR/bin:$PATH"
export WINELOADER="$WINE_BIN"
export WINESERVER="$INSTALL_DIR/bin/wineserver"

# Compatibilidade com wayland
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

[ -z "${DISPLAY:-}" ] && export DISPLAY=:0

# Esync/Fsync se o kernel suportar
if grep -qw "futex_waitv" /proc/kallsyms 2>/dev/null || [ -e /dev/futex-waitv ]; then
    export WINEESYNC=1
    export WINEFSYNC=1
else
    export WINE_DISABLE_FAST_SYNC=1
fi

export WINEDLLOVERRIDES="uiautomationcore=d;oleacc=d;tabtip.exe=d;winemenubuilder=d;rpcss=n;midimap=n;steam_api=b,n"
export NO_AT_BRIDGE=1
export QT_ACCESSIBILITY=0


# ============================================================
#  BAIXAR O APP ESPECIALIZADO (substitui a busca de .exe)
# ============================================================
echo ""
mkdir -p "$APP_DIR"

if [[ ! -f "$APP_PATH" ]]; then
    info "Primeira execução — baixando $APP_NAME..."
    baixar "$APP_URL" "$APP_PATH" "$APP_NAME"
else
    ok "App já presente: $APP_NAME"
fi

SELECTED="$APP_PATH"

[[ -z "$SELECTED" ]] && erro "Nenhum arquivo selecionado."
[[ ! -f "$SELECTED" ]] && erro "Arquivo não encontrado: '$SELECTED'"

# PREFIX ISOLADO POR JOGO
GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$INSTALL_DIR/prefixes/$GAME_NAME"

if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
    mkdir -p "$WINEPREFIX"
    info "Inicializando ambiente do jogo pela primeira vez..."
    WINEARCH=win64 "$WINE_BIN" wineboot -i &>/dev/null &
    boot_pid=$!
    spinner "$boot_pid" "Configurando ambiente Wine..."
    wait "$boot_pid" || true
fi

# DETECTAR UNITY E MONTAR COMANDO
EXTRA_FLAGS=""
if detectar_unity "$SELECTED"; then
    aviso "Jogo Unity detectado — aplicando flags de compatibilidade D3D11"
    EXTRA_FLAGS="-force-d3d11 -nolog"
fi

# Configura áudio via PipeWire/PulseAudio
PULSE_SOCKET=$(pactl info 2>/dev/null | grep 'Server String' | awk '{print $3}')
if [[ -n "$PULSE_SOCKET" ]]; then
    export PULSE_SERVER="unix:$PULSE_SOCKET"
fi

echo ""
{
    echo -e "  ${GREEN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${GREEN}║  🎮  $(basename "$SELECTED")${RESET}"
    [[ -n "$EXTRA_FLAGS" ]] && echo -e "  ${GREEN}║  🔧  Flags: $EXTRA_FLAGS${RESET}"
    echo -e "  ${GREEN}║  📁  Prefix: $GAME_NAME${RESET}"
    echo -e "  ${GREEN}╚══════════════════════════════════════════════════╝${RESET}"
}
echo ""

# EXECUTAR - Usar array para argumentos seguros
declare -a wine_args=("$SELECTED")
[[ -n "$EXTRA_FLAGS" ]] && wine_args+=($EXTRA_FLAGS)

WINEARCH=win64 "$WINE_BIN" "${wine_args[@]}"

EXIT=$?
echo ""
(( EXIT == 0 )) && ok "Encerrado normalmente." || aviso "Código de saída: $EXIT"
