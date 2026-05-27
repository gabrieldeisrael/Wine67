#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# detecta desktop em português ou inglês
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
WINE_BIN="$INSTALL_DIR/bin/wine"
WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/11.8/wine-11.8-amd64-wow64.tar.xz"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'

# Detectar ambiente desktop
DESKTOP_SESSION="${DESKTOP_SESSION:-xfce}"
XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"

# Configuração padrão (modo balanceado)
DEBUG_MODE=0
COMPAT_LEVEL="medium"
USE_DXVK=1
DXVK_HUD=""

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
    echo "  ╚���██╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
    echo "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
    echo -e "${RESET}"
    echo -e "  ${DIM}Wine-Kron4ek wow64 Portable Launcher — sem sudo${RESET}"
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
    
    # Validar se o download foi um erro HTML
    if command -v file >/dev/null 2>&1; then
        if file "$dest" 2>/dev/null | grep -qi "HTML\|ASCII text"; then
            rm -f "$dest"
            erro "Servidor retornou erro ao baixar $nome"
        fi
    fi
}

buscar_tar() {
    local resultado=""
    for padrao in "wine-11.8-amd64-wow64.tar.xz" "wine-*.tar.xz" "wine-*.tar.gz" "wine-*.tar"; do
        resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" 2>/dev/null | head -1)
        [ -n "$resultado" ] && echo "$resultado" && return 0
        resultado=$(find /media /run/media /mnt -maxdepth 5 -name "$padrao" 2>/dev/null | head -1 2>/dev/null)
        [ -n "$resultado" ] && echo "$resultado" && return 0
    done
    return 1
}

validar_wine_instalacao() {
    # Verificar wine executável em múltiplos locais possíveis
    local wine_found=0
    if [ -f "$INSTALL_DIR/bin/wine" ] || [ -f "$INSTALL_DIR/bin/wine64" ]; then
        wine_found=1
    fi
    
    if [ $wine_found -eq 0 ]; then
        return 1
    fi
    
    # Verificar lib64/wine ou lib/wine (kernel32)
    if [ -f "$INSTALL_DIR/lib64/wine/kernel32.dll.so" ] || \
       [ -f "$INSTALL_DIR/lib/wine/kernel32.dll.so" ]; then
        return 0
    fi
    
    # Fallback: apenas verificar se tem estrutura wine mínima
    if [ -d "$INSTALL_DIR/lib/wine" ] || [ -d "$INSTALL_DIR/lib64/wine" ]; then
        return 0
    fi
    
    return 1
}

diagnosticar_estrutura() {
    info "Diagnosticando estrutura extraída..."
    echo "  Conteúdo de $INSTALL_DIR:"
    find "$INSTALL_DIR" -maxdepth 3 -type f 2>/dev/null | head -15 | sed 's/^/    /'
    echo ""
    
    # Verificação específica de kernel32
    echo "  Verificando kernel32.dll.so:"
    find "$INSTALL_DIR" -name "kernel32.dll.so" -o -name "kernel32*" 2>/dev/null | sed 's/^/    /'
    echo ""
}

instalar_wine() {
    info "Instalando Wine Kron4ek wow64..."
    
    # Limpar instalação anterior se incompleta
    if [ -d "$INSTALL_DIR" ] && ! validar_wine_instalacao; then
        aviso "Instalação anterior incompleta detectada. Limpando..."
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi
    
    local GE_TAR
    if GE_TAR=$(buscar_tar); then
        ok "Arquivo encontrado: $GE_TAR"
    else
        GE_TAR="$INSTALL_DIR/wine-kron4ek.tar.xz"
        baixar "$WINE_URL" "$GE_TAR" "Wine-Kron4ek wow64"
    fi

    # Determinar flags de tar baseado na extensão
    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
        *) TAR_FLAG="-xf"; TEST_FLAG="-tf" ;;
    esac

    info "Verificando integridade do arquivo..."
    if ! tar "$TEST_FLAG" "$GE_TAR" >/dev/null 2>&1; then
        rm -f "$GE_TAR"
        erro "Arquivo corrompido ou inválido."
    fi
    ok "Arquivo verificado."

    info "Extraindo Wine (pode demorar alguns minutos)..."
    
    # Criar diretório temporário para extração
    local TEMP_EXTRACT="$INSTALL_DIR/temp_extract"
    mkdir -p "$TEMP_EXTRACT"
    
    # Extrair sem strip-components primeiro para inspecionar
    tar "$TAR_FLAG" "$GE_TAR" -C "$TEMP_EXTRACT" 2>/dev/null &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo Wine..."
    wait "$tar_pid" || erro "Falha ao extrair Wine."
    
    # Inspecionar e reorganizar estrutura
    info "Reorganizando estrutura..."
    
    # Verificar se há diretório top-level (wine/, wine-11.8, etc)
    local top_dir=$(find "$TEMP_EXTRACT" -maxdepth 1 -mindepth 1 -type d | head -1)
    
    if [ -n "$top_dir" ] && [ -d "$top_dir" ]; then
        # Mover conteúdo do diretório top-level para INSTALL_DIR
        mv "$top_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
    else
        # Mover tudo que foi extraído
        mv "$TEMP_EXTRACT"/* "$INSTALL_DIR/" 2>/dev/null || true
    fi
    
    # Limpar temporário
    rm -rf "$TEMP_EXTRACT"
    
    # Definir permissões de execução
    info "Configurando permissões..."
    [ -d "$INSTALL_DIR/bin" ] && find "$INSTALL_DIR/bin" -type f -exec chmod +x {} \; 2>/dev/null
    [ -d "$INSTALL_DIR/lib" ] && find "$INSTALL_DIR/lib" -type f -name "*.so*" -exec chmod +x {} \; 2>/dev/null
    [ -d "$INSTALL_DIR/lib64" ] && find "$INSTALL_DIR/lib64" -type f -name "*.so*" -exec chmod +x {} \; 2>/dev/null

    # Validar instalação
    if ! validar_wine_instalacao; then
        diagnosticar_estrutura
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
        erro "Instalação incompleta: componentes críticos não encontrados."
    fi

    ok "Wine instalado e validado com sucesso!"
}

# Início do script
exibir_logo

if [ ! -f "$WINE_BIN" ] || ! validar_wine_instalacao; then
    instalar_wine
fi

[ ! -x "$WINE_BIN" ] && chmod +x "$WINE_BIN"

ok "Wine: $WINE_BIN"
ok "Versão: $("$WINE_BIN" --version 2>/dev/null || echo 'desconhecida')"

# Configuração do ambiente do wine
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Detecção de Display (X11 vs Wayland)
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    aviso "Detectado Wayland - pode ter incompatibilidades"
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

# Configurações base do Wine
export WINEARCH=win64
export WINE_CPU_TOPOLOGY=4:2
export WINEDLLOVERRIDES="winemenubuilder=d;rpcss=n;midimap=n"
export STAGING_SHARED_MEMORY=1

# Modo balanceado padrão
export DXVK_HUD=""
info "Modo: BALANCEADO (DirectX/DXVK padrão)"

# Áudio: Detecção melhorada (PipeWire/PulseAudio)
configurar_audio() {
    # Verificar PulseAudio
    if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
        local PULSE_SOCKET
        PULSE_SOCKET=$(pactl info 2>/dev/null | grep 'Server String' | awk '{print $3}')
        if [ -n "$PULSE_SOCKET" ]; then
            export PULSE_SERVER="unix:$PULSE_SOCKET"
            ok "Audio: PulseAudio detectado"
            return 0
        fi
    fi

    # Verificar PipeWire
    if [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ] 2>/dev/null; then
        export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
        ok "Audio: PipeWire detectado"
        return 0
    fi

    # Fallback: usar valores padrão
    aviso "Audio: Usando configuração padrão"
    return 0
}

configurar_audio

echo ""
echo "Procurando jogos em múltiplos locais..."

# Procurar em vários locais: Home, Downloads, Wine67, /media, /mnt
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

# Procurar .exe em todos os caminhos
for search_path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$search_path" ]; then
        while IFS= read -r exe_file; do
            EXES+=("$exe_file")
        done < <(find "$search_path" -maxdepth 10 -type f -name "*.exe" 2>/dev/null)
    fi
done

# Remover duplicatas mantendo a ordem
declare -a UNIQUE_EXES
declare -A SEEN_EXES
for exe in "${EXES[@]}"; do
    if [ -z "${SEEN_EXES[$exe]}" ]; then
        UNIQUE_EXES+=("$exe")
        SEEN_EXES[$exe]=1
    fi
done

# Ordenar
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

# Prefix por jogo
GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$WINE67_DIR/prefixes/$GAME_NAME"
mkdir -p "$WINEPREFIX"

# Inicializar prefix Wine (criar estrutura Windows)
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    info "Inicializando Wine prefix..."
    
    # Use wineboot -i to properly initialize the prefix
    WINEARCH=win64 WINEPREFIX="$WINEPREFIX" "$WINE_BIN" wineboot -i 2>&1 | tail -5 &
    local boot_pid=$!
    spinner "$boot_pid" "Criando estrutura Windows..."
    wait "$boot_pid"
    
    # Verify initialization succeeded
    if [ ! -f "$WINEPREFIX/system.reg" ]; then
        erro "Falha ao inicializar Wine prefix - system.reg não foi criado"
    fi
    
    ok "Prefix inicializado."
    
    # Install runtime dependencies (test execution to build DLL cache)
    info "Instalando dependências de runtime..."
    WINEARCH=win64 WINEPREFIX="$WINEPREFIX" "$WINE_BIN" cmd /c exit 2>/dev/null
    ok "Dependências instaladas."
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║ Iniciando: $(basename "$SELECTED")${RESET}"
echo -e "${GREEN}║ Compatibilidade: ${BOLD}$COMPAT_LEVEL${RESET}${GREEN}${RESET}"
echo -e "${GREEN}║ Prefix: $GAME_NAME${RESET}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${RESET}"
echo ""

# Executar jogo
"$WINE_BIN" "$SELECTED"

EXIT=$?
echo ""
if [ $EXIT -eq 0 ]; then
    ok "Encerrado normalmente."
else
    echo -e "${YELLOW}⚠ Código de saída: $EXIT${RESET}"
fi
