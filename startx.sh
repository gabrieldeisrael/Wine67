#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detecta desktop em português ou inglês
if [ -d "$HOME/Área de Trabalho" ]; then
    DESKTOP="$HOME/Área de Trabalho"
elif [ -d "$HOME/Desktop" ]; then
    DESKTOP="$HOME/Desktop"
else
    mkdir -p "$HOME/Desktop"
    DESKTOP="$HOME/Desktop"
fi

# Criar pasta Wine67 no Desktop
WINE67_DIR="$DESKTOP/Wine67"
mkdir -p "$WINE67_DIR"

INSTALL_DIR="$WINE67_DIR/wine"
PROTON_DIR="$INSTALL_DIR"
WINE_BIN="$INSTALL_DIR/bin/wine64"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'

# Detectar ambiente desktop
DESKTOP_SESSION="${DESKTOP_SESSION:-xfce}"
XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"

DEBUG_MODE=0
COMPAT_LEVEL="high"
USE_DXVK=1
WINE_ARCH="win64"
MAX_RETRIES=3
RETRY_DELAY=5

# ============================================================================
# SELEÇÃO DE VERSÃO (Wine-GE vs Proton-GE)
# ============================================================================
WINE_TYPE="" # "wine-ge" ou "proton-ge"

erro()  { echo -e "${RED}❌ $1${RESET}"; exit 1; }
ok()    { echo -e "${GREEN}✔  $1${RESET}"; }
info()  { echo -e "${CYAN}➜  $1${RESET}"; }
aviso() { echo -e "${YELLOW}⚠  $1${RESET}"; }

spinner() {
    local pid=$1
    local msg="${2:-Carregando...}"
    local spin='/-\|'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local c="${spin:$i:1}"
        echo -ne "\r  ${CYAN}[${c}]${RESET}  ${msg}"
        i=$(( (i+1) % ${#spin} ))
        sleep 0.1
    done
    echo -ne "\r  ${GREEN}[✔]${RESET}  ${msg}\n"
}

exibir_logo() {
    command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'
    echo -e "${MAGENTA}${BOLD}"
    echo "  ██╗    ██╗██╗███╗   ██╗███████╗ ██████╗ ███████╗"
    echo "  ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚═══╚██║"
    echo "  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝"
    echo "  ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ "
    echo "  ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
    echo "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
    echo -e "${RESET}"
    echo -e "  ${DIM}Portable Game Launcher — SEM SUDO${RESET}"
    echo -e "  ${DIM}Base: $WINE67_DIR${RESET}"
    echo -e "  ${DIM}Desktop: $DESKTOP_SESSION | Sessão: $XDG_SESSION_TYPE${RESET}"
    echo ""
}

# Selecionar tipo de Wine
selecionar_wine_type() {
    echo ""
    echo -e "${CYAN}=== Selecione a versão ===${RESET}"
    echo ""
    echo -e "  ${YELLOW}[1]${RESET} Wine-GE (Wine com melhorias de games) - Wine-GE-Proton8-26"
    echo -e "  ${YELLOW}[2]${RESET} Proton-GE (Proton com melhorias de games) - GE-Proton10-34"
    echo ""
    echo -ne "${CYAN}Escolha (1 ou 2): ${RESET}"
    read -r WINE_CHOICE
    
    case "$WINE_CHOICE" in
        1)
            WINE_TYPE="wine-ge"
            ok "Selecionado: Wine-GE-Proton8-26"
            ;;
        2)
            WINE_TYPE="proton-ge"
            ok "Selecionado: GE-Proton10-34"
            ;;
        *)
            erro "Opção inválida"
            ;;
    esac
}

# Validações de dependências - SEM SUDO!
if ! command -v curl >/dev/null 2>&1; then
    erro "curl não está instalado!\n\nPeça ao administrador para instalar:\n  Ubuntu/Debian: apt install curl\n  Fedora: dnf install curl"
fi

if ! command -v tar >/dev/null 2>&1; then
    erro "tar não está instalado!"
fi

mkdir -p "$INSTALL_DIR"

# Função para obter a versão mais recente
obter_wine_url() {
    local tipo="$1"
    info "Detectando versão mais recente de $tipo..."
    
    local repo_url
    if [ "$tipo" = "wine-ge" ]; then
        repo_url="GloriousEggroll/wine-ge-custom"
    else
        repo_url="GloriousEggroll/proton-ge-custom"
    fi
    
    # Usar jq se disponível para parse melhor, senão usar grep
    if command -v jq >/dev/null 2>&1; then
        local download_url=$(curl -s "https://api.github.com/repos/${repo_url}/releases/latest" | jq -r '.assets[] | select(.name | endswith(".tar.xz") or endswith(".tar.gz")) | .browser_download_url' | head -1)
    else
        # Fallback sem jq: tentar .tar.xz primeiro, depois .tar.gz
        local download_url=$(curl -s "https://api.github.com/repos/${repo_url}/releases/latest" | grep -oP '"browser_download_url": "\K[^"]*\.tar\.xz' | head -1)
        
        if [ -z "$download_url" ]; then
            download_url=$(curl -s "https://api.github.com/repos/${repo_url}/releases/latest" | grep -oP '"browser_download_url": "\K[^"]*\.tar\.gz' | head -1)
        fi
    fi
    
    if [ -n "$download_url" ]; then
        echo "$download_url"
        return 0
    else
        erro "Não foi possível obter URL de download. Verifique sua conexão ou use um arquivo local."
    fi
}

baixar() {
    local url="$1"
    local dest="$2"
    local nome="$3"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        info "Baixando $nome (tentativa $attempt/$MAX_RETRIES)..."
        
        rm -f "$dest"
        
        # curl com timeout e redirect automático
        if curl -L --max-time 600 --connect-timeout 30 -# -o "$dest" "$url" 2>&1; then
            if [ -f "$dest" ] && [ -s "$dest" ]; then
                ok "Download completo! ($(du -h "$dest" | cut -f1))"
                return 0
            fi
        fi
        
        rm -f "$dest"
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            aviso "Falha na tentativa $attempt. Aguardando ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
        
        attempt=$((attempt + 1))
    done
    
    erro "Falha ao baixar $nome após $MAX_RETRIES tentativas"
}

buscar_tar() {
    local resultado=""
    for padrao in "GE-Proton*.tar.gz" "GE-Proton*.tar.xz" "Proton-*.tar.gz" "proton-*.tar.xz" "Wine-*.tar.gz" "Wine-*.tar.xz" "wine-*.tar.gz" "wine-*.tar.xz"; do
        resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" 2>/dev/null | head -1)
        [ -n "$resultado" ] && echo "$resultado" && return 0
        resultado=$(find /media /run/media /mnt -maxdepth 5 -name "$padrao" 2>/dev/null | head -1 2>/dev/null)
        [ -n "$resultado" ] && echo "$resultado" && return 0
    done
    return 1
}

validar_wine_instalacao() {
    if [ ! -f "$INSTALL_DIR/bin/wine64" ] && [ ! -f "$INSTALL_DIR/bin/wine" ] && [ ! -f "$INSTALL_DIR/proton" ]; then
        return 1
    fi
    
    if [ ! -d "$INSTALL_DIR/lib" ] && [ ! -d "$INSTALL_DIR/lib64" ]; then
        return 1
    fi
    
    return 0
}

diagnosticar_estrutura() {
    info "Diagnosticando estrutura..."
    echo ""
    echo "  📁 Conteúdo de $INSTALL_DIR:"
    ls -1 "$INSTALL_DIR" 2>/dev/null | head -20 | sed 's/^/    /' || echo "    [vazio]"
    echo ""
    
    echo "  📦 Tamanho:"
    du -sh "$INSTALL_DIR" 2>/dev/null | sed 's/^/    /'
}

instalar_wine() {
    local tipo="$1"
    local tipo_display=$([ "$tipo" = "wine-ge" ] && echo "Wine-GE-Proton8-26" || echo "GE-Proton10-34")
    
    info "Instalando $tipo_display..."
    
    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR")" ]; then
        aviso "Removendo instalação anterior..."
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi
    
    local GE_TAR
    if GE_TAR=$(buscar_tar); then
        ok "Arquivo encontrado: $GE_TAR"
    else
        local WINE_URL=$(obter_wine_url "$tipo")
        GE_TAR="$INSTALL_DIR/wine.tar.gz"
        info "Baixando $tipo_display (~800MB)..."
        baixar "$WINE_URL" "$GE_TAR" "$tipo_display"
    fi

    # Determinar flags de tar
    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
        *) TAR_FLAG="-xf"; TEST_FLAG="-tf" ;;
    esac

    info "Verificando integridade..."
    if ! tar "$TEST_FLAG" "$GE_TAR" >/dev/null 2>&1; then
        rm -f "$GE_TAR"
        erro "Arquivo corrompido."
    fi
    ok "Arquivo verificado."

    info "Extraindo $tipo_display..."
    
    rm -rf "$INSTALL_DIR/temp_extract"
    mkdir -p "$INSTALL_DIR/temp_extract"
    
    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR/temp_extract" &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo..."
    wait "$tar_pid" || true
    
    info "Reorganizando..."
    
    local top_dir=$(find "$INSTALL_DIR/temp_extract" -maxdepth 1 -mindepth 1 -type d | head -1)
    
    if [ -n "$top_dir" ]; then
        mv "$top_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
        mv "$top_dir"/.[!.]* "$INSTALL_DIR/" 2>/dev/null || true
    fi
    
    rm -rf "$INSTALL_DIR/temp_extract"
    
    info "Configurando permissões..."
    find "$INSTALL_DIR" -type f \( -name "wine*" -o -name "proton" \) -exec chmod +x {} \; 2>/dev/null || true

    if ! validar_wine_instalacao; then
        diagnosticar_estrutura
        erro "FALHA: $tipo_display não foi instalado corretamente."
    fi

    ok "$tipo_display instalado com sucesso!"
}

# ============================================================================
# DETECTAR ARQUITETURA
# ============================================================================
detectar_arquitetura_exe() {
    local exe="$1"
    
    if command -v file >/dev/null 2>&1; then
        local file_info=$(file "$exe" 2>/dev/null)
        
        if echo "$file_info" | grep -qi "x86-64\|x86_64\|64-bit"; then
            echo "win64"
            return 0
        elif echo "$file_info" | grep -qi "Intel 80386\|32-bit\|PE32\s"; then
            echo "win32"
            return 0
        fi
    fi
    
    echo "win64"
}

# ============================================================================
# INÍCIO DO SCRIPT
# ============================================================================
exibir_logo

# Selecionar tipo de wine
selecionar_wine_type

if ! validar_wine_instalacao; then
    instalar_wine "$WINE_TYPE"
fi

# Detectar estrutura Wine/Proton
PROTON_BINARY=""
if [ -f "$INSTALL_DIR/proton" ]; then
    PROTON_BINARY="$INSTALL_DIR/proton"
    WINE_BIN="$INSTALL_DIR/bin/wine64"
elif [ -f "$INSTALL_DIR/bin/wine64" ]; then
    WINE_BIN="$INSTALL_DIR/bin/wine64"
    PROTON_BINARY=""
elif [ -f "$INSTALL_DIR/bin/wine" ]; then
    WINE_BIN="$INSTALL_DIR/bin/wine"
    PROTON_BINARY=""
else
    erro "Wine/Proton binary não encontrado!"
fi

chmod +x "$WINE_BIN" 2>/dev/null || true
[ -n "$PROTON_BINARY" ] && chmod +x "$PROTON_BINARY" 2>/dev/null || true

ok "Wine: $WINE_BIN"
ok "Proton: ${PROTON_BINARY:-[não usado]}"

# ============================================================================
# VARIÁVEIS DE AMBIENTE
# ============================================================================

export LD_LIBRARY_PATH="$INSTALL_DIR/lib64:$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
export PATH="$INSTALL_DIR/bin:$PATH"
export WINELOADER="$WINE_BIN"
export WINESERVER="$INSTALL_DIR/bin/wineserver"
export DXVK_HUD=off
export STAGING_SHARED_MEMORY=1
export WINEDLLOVERRIDES="winemenubuilder=d;rpcss=n;midimap=n"
export PROTON_NO_ESYNC=0
export PROTON_USE_WINED3D=0

if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    aviso "Detectado Wayland - pode ter incompatibilidades"
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

tipo_display=$([ "$WINE_TYPE" = "wine-ge" ] && echo "Wine-GE-Proton8-26" || echo "GE-Proton10-34")
info "Modo: $tipo_display com DXVK"
info "LD_LIBRARY_PATH: $INSTALL_DIR/lib64:lib"

# Áudio
if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    ok "Audio: PulseAudio"
elif [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ] 2>/dev/null; then
    ok "Audio: PipeWire"
fi

echo ""
echo "Procurando jogos..."

info "Escaneando..."

declare -a EXES
declare -a SEARCH_PATHS=(
    "$WINE67_DIR"
    "$HOME/Downloads"
    "$HOME/Descargas"
    "$HOME/Transferências"
    "/media"
    "/mnt"
    "$SCRIPT_DIR"
)

for search_path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$search_path" ]; then
        while IFS= read -r exe_file; do
            EXES+=("$exe_file")
        done < <(find "$search_path" -maxdepth 10 -type f -name "*.exe" 2>/dev/null)
    fi
done

declare -a UNIQUE_EXES
declare -A SEEN_EXES
for exe in "${EXES[@]}"; do
    if [ -z "${SEEN_EXES[$exe]}" ]; then
        UNIQUE_EXES+=("$exe")
        SEEN_EXES[$exe]=1
    fi
done

IFS=$'\n' UNIQUE_EXES=($(sort <<<"${UNIQUE_EXES[*]}"))

if [ ${#UNIQUE_EXES[@]} -eq 0 ]; then
    echo ""
    echo -ne "  Caminho do .exe: "
    read -r SELECTED
    SELECTED="${SELECTED//\'/}"; SELECTED="${SELECTED//\"/}"
    SELECTED="${SELECTED# }";   SELECTED="${SELECTED% }"
    [ -f "$SELECTED" ] || erro "Não encontrado: '$SELECTED'"
else
    echo ""
    echo "Jogos encontrados:"
    echo ""
    for i in "${!UNIQUE_EXES[@]}"; do
        echo -e "  ${YELLOW}[$((i+1))]${RESET} $(basename "${UNIQUE_EXES[$i]}")"
    done
    echo ""
    echo -ne "${CYAN}Escolha o número: ${RESET}"
    read -r CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#UNIQUE_EXES[@]}" ]; then
        SELECTED="${UNIQUE_EXES[$((CHOICE-1))]}"
    else
        erro "Opção inválida"
    fi
fi

[ ! -f "$SELECTED" ] && erro "Não encontrado: '$SELECTED'"

DETECTED_ARCH=$(detectar_arquitetura_exe "$SELECTED")
WINE_ARCH="$DETECTED_ARCH"

info "Arquitetura: $WINE_ARCH"

GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$WINE67_DIR/prefixes/$GAME_NAME"
mkdir -p "$WINEPREFIX"

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    info "Inicializando prefix ($WINE_ARCH)..."
    
    WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" "$WINE_BIN" wineboot -i 2>&1 | tail -2 &
    local boot_pid=$!
    spinner "$boot_pid" "Criando Windows ($WINE_ARCH)..."
    wait "$boot_pid" || true
    
    ok "Prefix pronto"
fi

echo ""
echo -e "${GREEN}╔═════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║ 🎮 $(basename "$SELECTED")${RESET}"
echo -e "${GREEN}║ 🔧 $WINE_ARCH | 🚀 $tipo_display + DXVK${RESET}"
echo -e "${GREEN}║ 📁 $GAME_NAME${RESET}"
echo -e "${GREEN}╚═════════════════════════════════════════════╝${RESET}"
echo ""

# EXECUTAR
WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" LD_LIBRARY_PATH="$INSTALL_DIR/lib64:$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}" "$WINE_BIN" "$SELECTED"

EXIT=$?
echo ""
if [ $EXIT -eq 0 ]; then
    ok "Jogo encerrado"
else
    echo -e "${YELLOW}⚠  Saída: $EXIT${RESET}"
fi
