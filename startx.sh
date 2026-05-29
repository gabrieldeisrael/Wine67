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
WINE_BIN="$INSTALL_DIR/bin/wine64"
# Proton 9.0 - Última versão estável com suporte completo
WINE_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/9.0-GE-1/Proton-9.0-GE-1.tar.gz"

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
    echo "  ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚════██║"
    echo "  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝"
    echo "  ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ "
    echo "  ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
    echo "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
    echo -e "${RESET}"
    echo -e "  ${DIM}Proton-GE Portable Game Launcher — sem sudo${RESET}"
    echo -e "  ${DIM}Base: $WINE67_DIR${RESET}"
    echo -e "  ${DIM}Desktop: $DESKTOP_SESSION | Sessão: $XDG_SESSION_TYPE${RESET}"
    echo ""
}

# Validações de dependências
command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || erro "Instale wget ou curl"
command -v tar >/dev/null 2>&1 || erro "tar não encontrado"

mkdir -p "$INSTALL_DIR"

baixar() {
    local url="$1"
    local dest="$2"
    local nome="$3"
    
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url" &
    else
        curl -L -s -o "$dest" "$url" &
    fi
    
    local dl_pid=$!
    spinner "$dl_pid" "Baixando $nome..."
    wait "$dl_pid" || erro "Falha ao baixar $nome"
    
    if command -v file >/dev/null 2>&1; then
        if file "$dest" 2>/dev/null | grep -qi "HTML\|ASCII text"; then
            rm -f "$dest"
            erro "Servidor retornou erro ao baixar $nome"
        fi
    fi
}

buscar_tar() {
    local resultado=""
    for padrao in "Proton-*.tar.gz" "proton-*.tar.xz" "wine-*.tar.xz" "wine-*.tar.gz" "wine-*.tar"; do
        resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" 2>/dev/null | head -1)
        [ -n "$resultado" ] && echo "$resultado" && return 0
        resultado=$(find /media /run/media /mnt -maxdepth 5 -name "$padrao" 2>/dev/null | head -1 2>/dev/null)
        [ -n "$resultado" ] && echo "$resultado" && return 0
    done
    return 1
}

validar_wine_instalacao() {
    # Verificar se Wine/Proton está instalado
    if [ ! -f "$INSTALL_DIR/bin/wine64" ] && [ ! -f "$INSTALL_DIR/bin/wine" ]; then
        return 1
    fi
    
    # CRÍTICO: Verificar que DLLs nativas existem
    local has_libs=0
    if find "$INSTALL_DIR" \( -name "kernel32.dll.so" -o -name "ntdll.dll.so" \) 2>/dev/null | grep -q .; then
        has_libs=1
    fi
    
    # Para Proton, também aceita se tem arquivos de runtime
    if [ ! -d "$INSTALL_DIR/lib64/wine" ] && [ ! -d "$INSTALL_DIR/lib/wine" ] && [ $has_libs -eq 0 ]; then
        if [ ! -d "$INSTALL_DIR/compatlib" ]; then
            return 1
        fi
    fi
    
    return 0
}

diagnosticar_estrutura() {
    info "Diagnosticando estrutura extraída..."
    echo ""
    echo "  📁 Conteúdo de $INSTALL_DIR (top-level):"
    ls -1 "$INSTALL_DIR" 2>/dev/null | sed 's/^/    /' || echo "    [vazio]"
    echo ""
    
    echo "  🔍 Procurando componentes Wine/Proton:"
    find "$INSTALL_DIR" -maxdepth 3 -type d \( -name "wine" -o -name "lib64" -o -name "lib32" -o -name "compatlib" \) 2>/dev/null | sed 's/^/    /'
    echo ""
    
    echo "  🔧 Binários Wine:"
    ls -lah "$INSTALL_DIR"/bin/wine* 2>/dev/null | sed 's/^/    /' || echo "    ❌ Não encontrados"
    echo ""
    
    echo "  📦 Tamanho da instalação:"
    du -sh "$INSTALL_DIR" 2>/dev/null | sed 's/^/    /'
    echo ""
}

instalar_wine() {
    info "Instalando Proton-GE 9.0 (Wine + Proton + DXVK integrado)..."
    
    if [ -d "$INSTALL_DIR" ]; then
        aviso "Removendo instalação anterior..."
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi
    
    local GE_TAR
    if GE_TAR=$(buscar_tar); then
        ok "Arquivo encontrado: $GE_TAR"
    else
        GE_TAR="$INSTALL_DIR/proton-ge.tar.gz"
        info "Baixando Proton-GE 9.0 (~800MB, pode demorar)..."
        baixar "$WINE_URL" "$GE_TAR" "Proton-GE 9.0"
    fi

    # Verificar tamanho
    local TAR_SIZE=$(stat -f%z "$GE_TAR" 2>/dev/null || stat -c%s "$GE_TAR" 2>/dev/null)
    if [ "$TAR_SIZE" -lt 500000000 ]; then
        aviso "⚠️  Arquivo Proton parece pequeno demais ($TAR_SIZE bytes)"
        aviso "Download pode estar incompleto"
    fi

    # Determinar flags de tar
    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
        *) TAR_FLAG="-xf"; TEST_FLAG="-tf" ;;
    esac

    info "Verificando integridade do arquivo..."
    if ! tar "$TEST_FLAG" "$GE_TAR" >/dev/null 2>&1; then
        rm -f "$GE_TAR"
        erro "Arquivo corrompido. Download será refeito."
    fi
    ok "Arquivo verificado."

    info "Extraindo Proton (pode demorar alguns minutos)..."
    
    rm -rf "$INSTALL_DIR/temp_extract"
    mkdir -p "$INSTALL_DIR/temp_extract"
    
    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR/temp_extract" 2>/dev/null &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo Proton..."
    wait "$tar_pid" || true
    
    info "Reorganizando estrutura..."
    
    # Proton-GE vem em diretório específico (Proton-9.0-GE-1/)
    local top_dir=$(find "$INSTALL_DIR/temp_extract" -maxdepth 1 -mindepth 1 -type d | head -1)
    
    if [ -n "$top_dir" ]; then
        mv "$top_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
        mv "$top_dir"/. "$INSTALL_DIR/" 2>/dev/null || true
    fi
    
    rm -rf "$INSTALL_DIR/temp_extract"
    
    # Proton precisa de permissões especiais
    info "Configurando permissões..."
    find "$INSTALL_DIR" -type f -name "*.so*" -exec chmod +x {} \; 2>/dev/null || true
    find "$INSTALL_DIR/bin" -type f -exec chmod +x {} \; 2>/dev/null || true
    chmod +x "$INSTALL_DIR/proton" 2>/dev/null || true

    if ! validar_wine_instalacao; then
        diagnosticar_estrutura
        erro "FALHA: Proton não foi instalado corretamente."
    fi

    ok "Proton-GE 9.0 instalado com sucesso!"
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

if ! validar_wine_instalacao; then
    instalar_wine
fi

# Buscar wine64 ou wine
if [ -f "$INSTALL_DIR/bin/wine64" ]; then
    WINE_BIN="$INSTALL_DIR/bin/wine64"
elif [ -f "$INSTALL_DIR/bin/wine" ]; then
    WINE_BIN="$INSTALL_DIR/bin/wine"
else
    # Tentar encontrar em proton (Proton é um wrapper)
    if [ -f "$INSTALL_DIR/proton" ]; then
        info "Usando Proton (wrapper)"
        WINE_BIN="$INSTALL_DIR/proton"
    else
        erro "Wine/Proton binary não encontrado!"
    fi
fi

chmod +x "$WINE_BIN" 2>/dev/null || true

ok "Wine/Proton: $WINE_BIN"
if [ -x "$WINE_BIN" ]; then
    WINE_VERSION=$("$WINE_BIN" --version 2>/dev/null || echo "Proton (versão desconhecida)")
else
    WINE_VERSION="Proton (versão desconhecida)"
fi
ok "Versão: $WINE_VERSION"

# ============================================================================
# VARIÁVEIS DE AMBIENTE
# ============================================================================

export LD_LIBRARY_PATH="$INSTALL_DIR/lib64:$INSTALL_DIR/lib32:$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
export PATH="$INSTALL_DIR/bin:$PATH"

export WINELOADER="$WINE_BIN"
export WINESERVER="$INSTALL_DIR/bin/wineserver"
export PROTON_USE_WINED3D=1

# DXVK está integrado no Proton
export DXVK_HUD=off
export STAGING_SHARED_MEMORY=1
export WINEDLLOVERRIDES="winemenubuilder=d;rpcss=n;midimap=n"

if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    aviso "Detectado Wayland - pode ter incompatibilidades"
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

info "Modo: ALTO DESEMPENHO (Proton + DXVK integrado)"

# Áudio
if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    ok "Audio: PulseAudio detectado"
elif [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ] 2>/dev/null; then
    ok "Audio: PipeWire detectado"
else
    aviso "Audio: Usando configuração padrão"
fi

echo ""
echo "Procurando jogos em múltiplos locais..."

info "Escaneando diretórios..."

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
    echo -ne "  Nenhum .exe encontrado. Digite o caminho: "
    read -r SELECTED
    SELECTED="${SELECTED//\'/}"; SELECTED="${SELECTED//\"/}"
    SELECTED="${SELECTED# }";   SELECTED="${SELECTED% }"
    [ -f "$SELECTED" ] || erro "Arquivo não encontrado: '$SELECTED'"
else
    echo ""
    echo "Jogos encontrados:"
    echo ""
    for i in "${!UNIQUE_EXES[@]}"; do
        echo -e "  ${YELLOW}[$((i+1))]${RESET} $(basename "${UNIQUE_EXES[$i]}") ${DIM}($(dirname "${UNIQUE_EXES[$i]}"))"${RESET}
    done
    echo ""
    echo -e "  ${CYAN}[0]${RESET} Digitar caminho manualmente"
    echo ""
    echo -ne "${CYAN}Escolha: ${RESET}"
    read -r CHOICE

    if [ "$CHOICE" = "0" ]; then
        echo -ne "  Caminho: "
        read -r SELECTED
        SELECTED="${SELECTED//\'/}"; SELECTED="${SELECTED//\"/}"
        SELECTED="${SELECTED# }";   SELECTED="${SELECTED% }"
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#UNIQUE_EXES[@]}" ]; then
        SELECTED="${UNIQUE_EXES[$((CHOICE-1))]}"
    else
        erro "Opção inválida"
    fi
fi

[ -z "$SELECTED" ] && erro "Nenhum arquivo selecionado."
[ ! -f "$SELECTED" ] && erro "Arquivo não encontrado: '$SELECTED'"

DETECTED_ARCH=$(detectar_arquitetura_exe "$SELECTED")
WINE_ARCH="$DETECTED_ARCH"

info "Arquitetura detectada: $WINE_ARCH"

GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$WINE67_DIR/prefixes/$GAME_NAME"
mkdir -p "$WINEPREFIX"

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    info "Inicializando Wine prefix ($WINE_ARCH) para $GAME_NAME..."
    
    WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" "$WINE_BIN" wineboot -i 2>&1 | tail -3 &
    local boot_pid=$!
    spinner "$boot_pid" "Criando estrutura Windows ($WINE_ARCH)..."
    wait "$boot_pid" || true
    
    if [ ! -f "$WINEPREFIX/system.reg" ]; then
        aviso "Tentando método alternativo..."
        WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" "$WINE_BIN" wineboot -u 2>&1 | tail -3
    fi
    
    ok "Prefix inicializado ($WINE_ARCH)."
fi

echo ""
echo -e "${GREEN}╔═════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║ 🎮 Jogo: $(basename "$SELECTED")${RESET}"
echo -e "${GREEN}║ 🔧 Arquitetura: ${BOLD}$WINE_ARCH${RESET}${GREEN}${RESET}"
echo -e "${GREEN}║ 📊 Compatibilidade: $COMPAT_LEVEL${RESET}"
echo -e "${GREEN}║ 🚀 Motor: Proton-GE 9.0 (DXVK integrado)${RESET}"
echo -e "${GREEN}║ 📁 Prefix: $GAME_NAME${RESET}"
echo -e "${GREEN}╚═════════════════════════════════════════════╝${RESET}"
echo ""

WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$SELECTED"

EXIT=$?
echo ""
if [ $EXIT -eq 0 ]; then
    ok "Jogo encerrado normalmente."
else
    echo -e "${YELLOW}⚠  Código de saída: $EXIT${RESET}"
fi
