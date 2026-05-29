#!/bin/bash

set -e  # Parar em qualquer erro

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
WINE_BIN_64="$INSTALL_DIR/bin/wine64"
WINE_BIN_32="$INSTALL_DIR/bin/wine"
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
WINE_ARCH="win64"  # Pode ser "win32" ou "win64"

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
    echo -e "  ${DIM}Wine-Kron4ek wow64 Portable Launcher — sem sudo${RESET}"
    echo -e "  ${DIM}Suporte: 64-bit (win64) e 32-bit (win32)${RESET}"
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
    # Verificar se Wine64 e Wine32 estão instalados (wow64 = ambos)
    if [ ! -f "$WINE_BIN_64" ] && [ ! -f "$WINE_BIN_32" ]; then
        return 1
    fi
    
    # CRÍTICO: Verificar DLLs nativas - procurar em qualquer lugar
    local has_kernel32=0
    if find "$INSTALL_DIR" -name "kernel32.dll.so" 2>/dev/null | grep -q .; then
        has_kernel32=1
    fi
    
    if [ $has_kernel32 -eq 0 ]; then
        return 1
    fi
    
    return 0
}

diagnosticar_estrutura() {
    info "Diagnosticando estrutura extraída..."
    echo ""
    echo "  📁 Conteúdo de $INSTALL_DIR (top-level):"
    ls -1 "$INSTALL_DIR" 2>/dev/null | sed 's/^/    /' || echo "    [vazio]"
    echo ""
    
    echo "  🔍 Procurando kernel32.dll.so em qualquer lugar:"
    local found=$(find "$INSTALL_DIR" -name "kernel32.dll.so" -type f 2>/dev/null | head -3)
    if [ -n "$found" ]; then
        echo "$found" | sed 's/^/    /'
    else
        echo "    ❌ NÃO ENCONTRADO! Wine pode estar corrompido."
    fi
    echo ""
    
    echo "  📚 Todos os diretórios lib:"
    find "$INSTALL_DIR" -maxdepth 2 -type d -name "lib*" 2>/dev/null | sed 's/^/    /'
    echo ""
    
    echo "  🔧 Binários Wine:"
    ls -lah "$INSTALL_DIR"/bin/wine* 2>/dev/null | sed 's/^/    /' || echo "    ❌ Não encontrados"
    echo ""
    
    echo "  📦 Conteúdo de lib (se existir):"
    find "$INSTALL_DIR/lib" -maxdepth 2 -type d 2>/dev/null | head -10 | sed 's/^/    /'
    echo ""
}

instalar_wine() {
    info "Instalando Wine Kron4ek wow64 (64-bit + 32-bit)..."
    
    # Limpar instalação anterior COMPLETAMENTE
    if [ -d "$INSTALL_DIR" ]; then
        aviso "Removendo instalação anterior..."
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi
    
    local GE_TAR
    if GE_TAR=$(buscar_tar); then
        ok "Arquivo encontrado: $GE_TAR"
    else
        GE_TAR="$INSTALL_DIR/wine-kron4ek.tar.xz"
        info "Baixando Wine (este é um arquivo grande, pode demorar)..."
        baixar "$WINE_URL" "$GE_TAR" "Wine-Kron4ek wow64"
    fi

    # Verificar tamanho do arquivo
    local TAR_SIZE=$(stat -f%z "$GE_TAR" 2>/dev/null || stat -c%s "$GE_TAR" 2>/dev/null)
    if [ "$TAR_SIZE" -lt 50000000 ]; then
        aviso "⚠️  Arquivo Wine parece pequeno demais ($TAR_SIZE bytes)"
        aviso "Pode estar incompleto. Tentando de qualquer forma..."
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
        erro "Arquivo corrompido ou inválido. Download será refeito na próxima execução."
    fi
    ok "Arquivo verificado."

    info "Extraindo Wine (pode demorar alguns minutos)..."
    
    # Limpar temporário se existir
    rm -rf "$INSTALL_DIR/temp_extract"
    mkdir -p "$INSTALL_DIR/temp_extract"
    
    # Extrair arquivo SEM redirecionamento de erro
    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR/temp_extract" &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo Wine (verifique espaço em disco)..."
    wait "$tar_pid" || {
        aviso "Extração completada (pode estar parcial)"
    }
    
    # Reorganizar estrutura
    info "Reorganizando estrutura..."
    
    # Verificar o que foi extraído
    local top_dir=$(find "$INSTALL_DIR/temp_extract" -maxdepth 1 -mindepth 1 -type d | head -1)
    
    if [ -n "$top_dir" ] && [ "$(ls "$top_dir" 2>/dev/null | wc -l)" -gt 0 ]; then
        # Mover conteúdo do diretório top-level
        info "Movendo conteúdo de $(basename "$top_dir")..."
        mv "$top_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
    else
        # Mover arquivos soltos
        info "Movendo arquivos soltos..."
        mv "$INSTALL_DIR/temp_extract"/* "$INSTALL_DIR/" 2>/dev/null || true
    fi
    
    # Limpar temporário
    rm -rf "$INSTALL_DIR/temp_extract"
    
    # Definir permissões
    info "Configurando permissões..."
    find "$INSTALL_DIR" -type f \( -executable -o -name "*.so*" \) 2>/dev/null | while read f; do 
        chmod +x "$f" 2>/dev/null || true
    done

    # Validação CRÍTICA
    if ! validar_wine_instalacao; then
        diagnosticar_estrutura
        
        # Oferecer alternativas
        echo ""
        aviso "FALHA na instalação: kernel32.dll.so não encontrado!"
        echo ""
        echo "Possíveis causas:"
        echo "  1. Download incompleto (arquivo muito pequeno)"
        echo "  2. Sem espaço em disco"
        echo "  3. Arquivo Wine corrompido no servidor"
        echo ""
        echo "Soluções:"
        echo "  - Tente novamente (será refeito o download)"
        echo "  - Verifique espaço em disco: df -h"
        echo "  - Tente outro source do Wine"
        echo ""
        
        exit 1
    fi

    ok "Wine wow64 (64+32 bits) instalado com sucesso!"
}

# ============================================================================
# DETECTAR ARQUITETURA DO EXECUTÁVEL
# ============================================================================
detectar_arquitetura_exe() {
    local exe="$1"
    
    # Usar 'file' para detectar se é 32 ou 64 bits
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
    
    # Fallback: tentar executar com win64, se falhar tenta win32
    echo "win64"
}

# ============================================================================
# INÍCIO DO SCRIPT
# ============================================================================
exibir_logo

# Forçar reinstalação se houver erro anterior
if ! validar_wine_instalacao; then
    instalar_wine
fi

# Definir Wine binary (preferir wine64, fallback para wine)
if [ -f "$WINE_BIN_64" ]; then
    WINE_BIN="$WINE_BIN_64"
    WINE_ARCH_DEFAULT="win64"
elif [ -f "$WINE_BIN_32" ]; then
    WINE_BIN="$WINE_BIN_32"
    WINE_ARCH_DEFAULT="win32"
else
    erro "Wine binary não encontrado!"
fi

chmod +x "$WINE_BIN" 2>/dev/null || true

ok "Wine 64-bit: $([ -f "$WINE_BIN_64" ] && echo "$WINE_BIN_64 ✓" || echo "não encontrado")"
ok "Wine 32-bit: $([ -f "$WINE_BIN_32" ] && echo "$WINE_BIN_32 ✓" || echo "não encontrado")"
ok "Versão: $("$WINE_BIN" --version 2>/dev/null || echo 'desconhecida')"

# ============================================================================
# VARIÁVEIS DE AMBIENTE - Suporte wow64 (ambas arquiteturas)
# ============================================================================

# Ordem CORRETA: lib64 ANTES de lib (lib64 para 64-bit, lib para 32-bit)
export LD_LIBRARY_PATH="$INSTALL_DIR/lib64:$INSTALL_DIR/lib32:$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
export PATH="$INSTALL_DIR/bin:$PATH"

# Garante que Wine use seus próprios binários
export WINELOADER="$WINE_BIN"
export WINESERVER="$INSTALL_DIR/bin/wineserver"

# DirectX / Gráficos
export DXVK_HUD=off
export STAGING_SHARED_MEMORY=1

# Sobrescrita de DLLs - usar nativas para máxima compatibilidade
export WINEDLLOVERRIDES="winemenubuilder=d;rpcss=n;midimap=n"

# Detecção de Display (X11 vs Wayland)
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    aviso "Detectado Wayland - pode ter incompatibilidades"
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

info "Modo: BALANCEADO (DirectX/DXVK padrão)"
info "LD_LIBRARY_PATH: lib64:lib32:lib"

# Áudio
configurar_audio() {
    if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
        ok "Audio: PulseAudio detectado"
        return 0
    fi

    if [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ] 2>/dev/null; then
        ok "Audio: PipeWire detectado"
        return 0
    fi

    aviso "Audio: Usando configuração padrão"
    return 0
}

configurar_audio

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

# Remover duplicatas
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

# Detectar arquitetura do executável
DETECTED_ARCH=$(detectar_arquitetura_exe "$SELECTED")
WINE_ARCH="$DETECTED_ARCH"

info "Arquitetura detectada: $WINE_ARCH"

# Prefix por jogo
GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$WINE67_DIR/prefixes/$GAME_NAME"
mkdir -p "$WINEPREFIX"

# Inicializar prefix Wine com arquitetura correta
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    info "Inicializando Wine prefix ($WINE_ARCH) para $GAME_NAME..."
    
    # Inicializar com wineboot na arquitetura correta
    WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" "$WINE_BIN" wineboot -i 2>&1 | tail -3 &
    local boot_pid=$!
    spinner "$boot_pid" "Criando estrutura Windows ($WINE_ARCH)..."
    wait "$boot_pid"
    
    # Verificar sucesso
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
echo -e "${GREEN}║ 📁 Prefix: $GAME_NAME${RESET}"
echo -e "${GREEN}║ 📚 Libs: 64+32-bit (lib64:lib32:lib)${RESET}"
echo -e "${GREEN}╚═════════════════════════════════════════════╝${RESET}"
echo ""

# EXECUTAR JOGO com arquitetura detectada
WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$SELECTED"

EXIT=$?
echo ""
if [ $EXIT -eq 0 ]; then
    ok "Jogo encerrado normalmente."
else
    echo -e "${YELLOW}⚠  Código de saída: $EXIT${RESET}"
    if [ $EXIT -eq 53 ]; then
        echo -e "${YELLOW}   (Erro C0000135 = kernel32.dll não carregada)${RESET}"
        echo -e "${YELLOW}   Execute: rm -rf ~/Desktop/Wine67/wine${RESET}"
        echo -e "${YELLOW}   E execute o script novamente${RESET}"
    fi
fi
