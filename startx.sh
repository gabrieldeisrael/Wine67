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

WINE67_DIR="$DESKTOP/Wine67"
mkdir -p "$WINE67_DIR"

INSTALL_DIR="$WINE67_DIR/wine"
WINE_BIN="$INSTALL_DIR/bin/wine64"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'; BLUE='\033[0;34m'; WHITE='\033[1;37m'

DESKTOP_SESSION="${DESKTOP_SESSION:-xfce}"
XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
WINE_ARCH="win64"
WINE_ARCH_SUPPORT="wow64"  # Default: wow64 (64-bit + 32-bit), "win64", "win32"
MAX_RETRIES=3
RETRY_DELAY=5
WINE_TYPE=""

erro()  { echo -e "${RED}❌  $1${RESET}"; exit 1; }
ok()    { echo -e "${GREEN}✔   $1${RESET}"; }
info()  { echo -e "${CYAN}➜   $1${RESET}"; }
aviso() { echo -e "${YELLOW}⚠   $1${RESET}"; }

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

# ============================================================================
# LOGO COM ANIMAÇÃO HORIZONTAL (scroll marquee) — v3
# ============================================================================
exibir_logo() {
    command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'

    local L0="  ██╗    ██╗██╗███╗   ██╗███████╗  ██████╗  ███████╗  "
    local L1="  ██║    ██║██║████╗  ██║██╔════╝ ██╔════╝  ╚════██║  "
    local L2="  ██║ █╗ ██║██║██╔██╗ ██║█████╗   ███████╗      ██╔╝  "
    local L3="  ██║███╗██║██║██║╚██╗██║██╔══╝   ██╔═══██╗    ██╔╝   "
    local L4="  ╚███╔███╔╝██║██║ ╚████║███████╗ ╚██████╔╝    ██║    "
    local L5="   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝  ╚═════╝     ╚═╝   "

    # Largura visual da logo: cada bloco/box char ocupa 1 coluna (mas tem 3 bytes UTF-8).
    # wc -m conta chars Unicode, que corresponde a colunas para esses símbolos.
    local LOGO_W
    LOGO_W=$(printf '%s' "$L0" | wc -m 2>/dev/null)
    # wc -m pode incluir o newline implícito; garantir valor mínimo sensato
    [ "${LOGO_W:-0}" -lt 10 ] && LOGO_W=54

    local TERM_W
    TERM_W=$(tput cols 2>/dev/null || echo 80)

    local CENTER_POS=$(( (TERM_W - LOGO_W) / 2 ))
    [ $CENTER_POS -lt 0 ] && CENTER_POS=0

    # Função auxiliar: imprime uma linha do logo na coluna X, sem ultrapassar TERM_W.
    # Usa ESC[<row>;<col>H para posicionamento absoluto — sem depender de "subir N linhas".
    # O autowrap é DESLIGADO (ESC[?7l) para que texto além da borda seja cortado, não quebrado.
    _logo_frame() {
        local col=$1  # coluna de início (1-based para tput cup)
        local row
        local line
        local col1=$(( col + 1 ))   # tput cup usa 0-based; printf \033[r;cH usa 1-based
        for row in 1 2 3 4 5 6; do
            case $row in
                1) line="$L0" ;; 2) line="$L1" ;; 3) line="$L2" ;;
                4) line="$L3" ;; 5) line="$L4" ;; 6) line="$L5" ;;
            esac
            # Posiciona cursor na linha (2+row-1) coluna col (ambos 1-based)
            printf '\033[%d;%dH' "$(( row + 1 ))" "$col1"
            # Apaga até o fim da linha, depois imprime — evita fantasmas de frames anteriores
            printf '\033[K'
            printf '%b' "${MAGENTA}${BOLD}${line}${RESET}"
        done
    }

    # Desliga autowrap para que linhas longas sejam cortadas em vez de quebradas
    printf '\033[?7l'
    # Oculta cursor
    tput civis 2>/dev/null || true
    # Trap: sempre restaura terminal ao sair (Ctrl+C, erro, etc.)
    trap 'printf "\033[?7h"; tput cnorm 2>/dev/null || true; printf "%b" "${RESET}"; trap - EXIT INT TERM' EXIT INT TERM

    # Limpa as 7 primeiras linhas (1 vazia + 6 da logo) com posicionamento absoluto
    local r
    for r in 1 2 3 4 5 6 7; do
        printf '\033[%d;1H\033[K' "$r"
    done

    # Animação: logo entra pela direita (col = TERM_W) e para em CENTER_POS
    local step
    for (( step=TERM_W; step>CENTER_POS; step-=2 )); do
        _logo_frame "$step"
        sleep 0.02
    done

    # Frame final: posição central exata
    _logo_frame "$CENTER_POS"

    # Restaura autowrap e cursor; posiciona cursor logo abaixo da logo
    printf '\033[?7h'
    tput cnorm 2>/dev/null || true
    trap - EXIT INT TERM

    # Move cursor para linha 9 (abaixo das 6 linhas de logo + margem)
    printf '\033[9;1H'

    echo ""
    echo -e "  ${WHITE}${BOLD}Portable Game Launcher — SEM SUDO${RESET}"
    echo -e "  ${DIM}Base: $WINE67_DIR${RESET}"
    echo -e "  ${DIM}Desktop: $DESKTOP_SESSION  |  Sessão: $XDG_SESSION_TYPE${RESET}"
    echo ""
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ============================================================================
# MENU DE SELEÇÃO DE MODO
# ============================================================================
selecionar_modo() {
    echo -e "  ${CYAN}${BOLD}Selecione o modo de execução:${RESET}"
    echo ""
    echo -e "  ${YELLOW}[1]${RESET}  ${BOLD}Proton-GE${RESET}  ${DIM}— melhor compatibilidade, jogos Steam${RESET}"
    echo -e "  ${YELLOW}[2]${RESET}  ${BOLD}Wine-GE${RESET}    ${DIM}— leve, direto, jogos nativos Windows${RESET}"
    echo ""
    echo -ne "  ${CYAN}Escolha (1 ou 2): ${RESET}"
    read -r WINE_CHOICE

    case "$WINE_CHOICE" in
        1) WINE_TYPE="proton-ge"; ok "Modo: Proton-GE" ;;
        2) WINE_TYPE="wine-ge";   ok "Modo: Wine-GE"   ;;
        *) erro "Opção inválida: '$WINE_CHOICE'" ;;
    esac
    echo ""
}

# ============================================================================
# MENU DE SELEÇÃO DE ARQUITETURA
# ============================================================================
selecionar_arquitetura() {
    echo -e "  ${CYAN}${BOLD}Selecione suporte de arquitetura:${RESET}"
    echo ""
    echo -e "  ${YELLOW}[1]${RESET}  ${BOLD}WoW64${RESET} (64-bit + 32-bit) ${DIM}— melhor compatibilidade universal${RESET}"
    echo -e "  ${YELLOW}[2]${RESET}  ${BOLD}64-bit puro${RESET}           ${DIM}— apenas aplicativos 64-bit${RESET}"
    echo -e "  ${YELLOW}[3]${RESET}  ${BOLD}32-bit puro${RESET}           ${DIM}— apenas aplicativos 32-bit${RESET}"
    echo ""
    echo -ne "  ${CYAN}Escolha (1, 2 ou 3): ${RESET}"
    read -r ARCH_CHOICE

    case "$ARCH_CHOICE" in
        1) WINE_ARCH_SUPPORT="wow64"; ok "Modo: WoW64 (64-bit + 32-bit)" ;;
        2) WINE_ARCH_SUPPORT="win64"; ok "Modo: 64-bit puro" ;;
        3) WINE_ARCH_SUPPORT="win32"; ok "Modo: 32-bit puro" ;;
        *) erro "Opção inválida: '$ARCH_CHOICE'" ;;
    esac
    echo ""
}

# ============================================================================
# VALIDAÇÕES DE DEPENDÊNCIAS
# ============================================================================
if ! command -v curl >/dev/null 2>&1; then
    erro "curl não instalado!\n  Ubuntu/Debian: apt install curl\n  Fedora: dnf install curl"
fi
if ! command -v tar >/dev/null 2>&1; then
    erro "tar não instalado!"
fi

mkdir -p "$INSTALL_DIR"

# ============================================================================
# DETECTAR URLs (stdout limpo — info/aviso vão para stderr)
# ============================================================================
obter_url() {
    local tipo="$1"

    if [ "$tipo" = "proton-ge" ]; then
        local repo="GloriousEggroll/proton-ge-custom"
        local fallback_tag="GE-Proton10-34"
        local fallback_file="GE-Proton10-34.tar.gz"
    else
        local repo="GloriousEggroll/wine-ge-custom"
        local fallback_tag="GE-Proton8-26"
        local fallback_file="wine-lutris-GE-Proton8-26-x86_64.tar.xz"
    fi

    info "Detectando versão mais recente de $tipo..." >&2

    local tag
    tag=$(curl -s --max-time 15 "https://api.github.com/repos/${repo}/releases/latest" \
          | grep '"tag_name"' | head -1 | cut -d'"' -f4)

    if [ -n "$tag" ]; then
        info "Versão detectada: $tag" >&2
        if [ "$tipo" = "proton-ge" ]; then
            echo "https://github.com/${repo}/releases/download/${tag}/${tag}.tar.gz"
        else
            echo "https://github.com/${repo}/releases/download/${tag}/wine-lutris-${tag}-x86_64.tar.xz"
        fi
        return 0
    fi

    aviso "API indisponível — usando fallback: $fallback_tag" >&2
    echo "https://github.com/${repo}/releases/download/${fallback_tag}/${fallback_file}"
}

# ============================================================================
# DOWNLOAD COM RETRY
# ============================================================================
baixar() {
    local url="$1"
    local dest="$2"
    local nome="$3"
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        info "Baixando $nome (tentativa $attempt/$MAX_RETRIES)..."
        rm -f "$dest"

        if curl -L --max-time 600 -# -o "$dest" "$url" 2>&1; then
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

# ============================================================================
# BUSCAR .TAR LOCAL (pendrive, pasta, etc)
# ============================================================================
buscar_tar() {
    local tipo="$1"
    local resultado=""

    if [ "$tipo" = "proton-ge" ]; then
        local padroes=("GE-Proton*.tar.gz" "Proton-*.tar.gz" "proton-*.tar.xz")
    else
        local padroes=("wine-lutris-*.tar.xz" "wine-lutris-*.tar.gz" "Wine-*.tar.gz" "wine-ge-*.tar.xz")
    fi

    for padrao in "${padroes[@]}"; do
        resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" 2>/dev/null | head -1)
        [ -n "$resultado" ] && echo "$resultado" && return 0
        resultado=$(find /media /run/media /mnt -maxdepth 5 -name "$padrao" 2>/dev/null | head -1 2>/dev/null)
        [ -n "$resultado" ] && echo "$resultado" && return 0
    done
    return 1
}

# ============================================================================
# VALIDAR INSTALAÇÃO
# ============================================================================
validar_instalacao() {
    if [ ! -f "$INSTALL_DIR/bin/wine64" ] && \
       [ ! -f "$INSTALL_DIR/bin/wine"   ] && \
       [ ! -f "$INSTALL_DIR/proton"     ]; then
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

# ============================================================================
# INSTALAR
# ============================================================================
instalar() {
    local tipo="$1"
    local nome_display
    nome_display=$([ "$tipo" = "proton-ge" ] && echo "Proton-GE" || echo "Wine-GE")

    info "Instalando $nome_display..."

    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        aviso "Removendo instalação anterior..."
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi

    local GE_TAR
    if GE_TAR=$(buscar_tar "$tipo"); then
        ok "Arquivo local encontrado: $GE_TAR"
    else
        local DL_URL
        DL_URL=$(obter_url "$tipo")
        local ext=".tar.gz"
        [[ "$DL_URL" == *.tar.xz ]] && ext=".tar.xz"
        GE_TAR="$INSTALL_DIR/wine_download${ext}"
        baixar "$DL_URL" "$GE_TAR" "$nome_display"
    fi

    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
        *)        TAR_FLAG="-xf";  TEST_FLAG="-tf"   ;;
    esac

    info "Verificando integridade do arquivo..."
    if ! tar "$TEST_FLAG" "$GE_TAR" >/dev/null 2>&1; then
        rm -f "$GE_TAR"
        erro "Arquivo corrompido ou incompleto."
    fi
    ok "Arquivo verificado."

    info "Extraindo $nome_display..."
    rm -rf "$INSTALL_DIR/temp_extract"
    mkdir -p "$INSTALL_DIR/temp_extract"

    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR/temp_extract" &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo $nome_display..."
    wait "$tar_pid" || true

    info "Reorganizando estrutura..."
    local top_dir
    top_dir=$(find "$INSTALL_DIR/temp_extract" -maxdepth 1 -mindepth 1 -type d | head -1)

    if [ -n "$top_dir" ]; then
        mv "$top_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
        mv "$top_dir"/.[!.]* "$INSTALL_DIR/" 2>/dev/null || true
    fi

    rm -rf "$INSTALL_DIR/temp_extract"
    rm -f "$GE_TAR"

    info "Configurando permissões..."
    find "$INSTALL_DIR" -type f \( -name "wine*" -o -name "proton" \) \
        -exec chmod +x {} \; 2>/dev/null || true

    if ! validar_instalacao; then
        diagnosticar_estrutura
        erro "FALHA: $nome_display não foi instalado corretamente."
    fi

    ok "$nome_display instalado com sucesso!"
}

# ============================================================================
# DETECTAR ARQUITETURA DO .EXE (MELHORADO)
# ============================================================================
detectar_arquitetura_exe() {
    local exe="$1"
    local arch=""

    # Método 1: comando 'file'
    if command -v file >/dev/null 2>&1; then
        local file_info
        file_info=$(file "$exe" 2>/dev/null)
        
        if echo "$file_info" | grep -qi "x86-64\|x86_64\|64-bit\|x64"; then
            echo "win64"; return 0
        elif echo "$file_info" | grep -qi "Intel 80386\|32-bit\|PE32 \|i386"; then
            echo "win32"; return 0
        fi
    fi

    # Método 2: análise de headers PE (Portable Executable)
    if command -v od >/dev/null 2>&1; then
        # Verifica assinatura PE em offset 0x3C
        local pe_offset
        pe_offset=$(od -An -tx4 -N64 "$exe" 2>/dev/null | head -1 | awk '{print $10}')
        
        if [ -n "$pe_offset" ]; then
            # Lê machine type no offset PE+4
            local machine_type
            machine_type=$(od -An -tx2 -j $((0x${pe_offset:0:2}04 + 4)) -N2 "$exe" 2>/dev/null | tr -d ' ')
            
            case "$machine_type" in
                8664) echo "win64"; return 0 ;;  # x86-64
                014c) echo "win32"; return 0 ;;  # i386
                aa64) echo "win64"; return 0 ;;  # ARM64
            esac
        fi
    fi

    # Padrão seguro: win64
    echo "win64"
}

# ============================================================================
# DETECTAR SUPORTE A MULTILIB (lib32 + lib64)
# ============================================================================
detectar_multilib() {
    # Verifica se o Wine foi compilado com suporte a 32-bit
    if [ -d "$INSTALL_DIR/lib" ] && [ -d "$INSTALL_DIR/lib64" ]; then
        return 0  # Ambas presentes = suporte completo
    fi
    if [ -d "$INSTALL_DIR/lib32" ] && [ -d "$INSTALL_DIR/lib64" ]; then
        return 0  # lib32 + lib64
    fi
    return 1  # Sem suporte a 32-bit
}

# ============================================================================
# CONFIGURAR VARIÁVEIS PARA WoW64 (32-bit em 64-bit)
# ============================================================================
configurar_wow64() {
    # WoW64: 64-bit prefix com suporte a 32-bit via /drive_c/windows/syswow64
    if ! detectar_multilib; then
        aviso "Instalação Wine sem suporte a 32-bit (lib32) — usando 64-bit puro"
        WINE_ARCH_SUPPORT="win64"
        return 1
    fi

    info "Configurando WoW64 (64-bit + 32-bit)..."

    # Usa wine64 como principal
    WINE_BIN="$INSTALL_DIR/bin/wine64"
    
    # Configura paths para 32-bit libs
    if [ -d "$INSTALL_DIR/lib32" ]; then
        export LD_LIBRARY_PATH="$INSTALL_DIR/lib32:$INSTALL_DIR/lib64:$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
    else
        export LD_LIBRARY_PATH="$INSTALL_DIR/lib64:$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
    fi

    return 0
}

# ============================================================================
# INÍCIO
# ============================================================================
exibir_logo
selecionar_modo
selecionar_arquitetura

# Instala se necessário
if ! validar_instalacao; then
    instalar "$WINE_TYPE"
fi

# ============================================================================
# DETECTAR BINÁRIOS
# ============================================================================
PROTON_BINARY=""
if [ -f "$INSTALL_DIR/proton" ]; then
    PROTON_BINARY="$INSTALL_DIR/proton"
    WINE_BIN="$INSTALL_DIR/bin/wine64"
elif [ -f "$INSTALL_DIR/bin/wine64" ]; then
    WINE_BIN="$INSTALL_DIR/bin/wine64"
elif [ -f "$INSTALL_DIR/bin/wine" ]; then
    WINE_BIN="$INSTALL_DIR/bin/wine"
else
    erro "Nenhum binário Wine/Proton encontrado em $INSTALL_DIR"
fi

chmod +x "$WINE_BIN" 2>/dev/null || true
[ -n "$PROTON_BINARY" ] && chmod +x "$PROTON_BINARY" 2>/dev/null || true

ok "Wine bin: $WINE_BIN"
[ -n "$PROTON_BINARY" ] && ok "Proton:   $PROTON_BINARY"

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

if [ "$WINE_TYPE" = "proton-ge" ]; then
    export PROTON_USE_WINED3D=0

    # --- Fix 1: wineserver server-side synchronization ---
    # Verifica suporte a futex_waitv (esync/fsync nativo).
    # Também checa /dev/futex-waitv (algumas distros expõem assim).
    _has_futex2() {
        grep -qw "futex_waitv" /proc/kallsyms 2>/dev/null && return 0
        [ -e /dev/futex-waitv ] && return 0
        return 1
    }
    if _has_futex2; then
        export PROTON_NO_ESYNC=0
        export PROTON_NO_FSYNC=0
        export WINEESYNC=1
        export WINEFSYNC=1
    else
        export PROTON_NO_ESYNC=1
        export PROTON_NO_FSYNC=1
        export WINEESYNC=0
        export WINEFSYNC=0
        export WINE_DISABLE_FAST_SYNC=1
        aviso "Kernel sem futex_waitv — esync/fsync desativados (evita server-side sync)"
    fi
else
    # Wine-GE: mesma lógica
    _has_futex2() {
        grep -qw "futex_waitv" /proc/kallsyms 2>/dev/null && return 0
        [ -e /dev/futex-waitv ] && return 0
        return 1
    }
    if _has_futex2; then
        export WINEESYNC=1
        export WINEFSYNC=1
    else
        export WINEESYNC=0
        export WINEFSYNC=0
        export WINE_DISABLE_FAST_SYNC=1
        aviso "Kernel sem futex_waitv — esync/fsync desativados"
    fi
fi

# --- Fix 2: RLIMIT_NICE <=20, unable to use safe priority ---
# Wine precisa de nice negativo para prioridade de processo.
# ulimit -e 40 eleva o limite sem precisar de sudo (40 = nice -20).
# Também suprime o aviso via WINE_DO_NOT_SET_NICE se não for possível elevar.
if ulimit -e 40 2>/dev/null; then
    : # elevou com sucesso
else
    export WINE_DO_NOT_SET_NICE=1
fi
# Desabilita real-time priority do Wine para evitar erros de permissão relacionados
export STAGING_WRITECOPY=1

if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    aviso "Detectado Wayland — aplicando compatibilidade X11"
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

[ -z "${DISPLAY:-}" ] && export DISPLAY=:0

MODO_LABEL=$([ "$WINE_TYPE" = "proton-ge" ] && echo "Proton-GE 🚀" || echo "Wine-GE 🍷")
info "Modo ativo: $MODO_LABEL + DXVK"

if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    ok "Áudio: PulseAudio"
elif [ -S "${XDG_RUNTIME_DIR:-/run/user/1000}/pipewire-0" ] 2>/dev/null; then
    ok "Áudio: PipeWire"
fi

# ============================================================================
# BUSCAR JOGOS (.EXE)
# ============================================================================
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
info "Escaneando diretórios em busca de jogos..."

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
for exe in "${EXES[@]+"${EXES[@]}"}"; do
    if [ -z "${SEEN_EXES[$exe]:-}" ]; then
        UNIQUE_EXES+=("$exe")
        SEEN_EXES[$exe]=1
    fi
done

IFS=$'\n' UNIQUE_EXES=($(sort <<<"${UNIQUE_EXES[*]+"${UNIQUE_EXES[*]}"}"))

SELECTED=""
if [ ${#UNIQUE_EXES[@]} -eq 0 ]; then
    echo ""
    aviso "Nenhum .exe encontrado automaticamente."
    echo -ne "  ${CYAN}Informe o caminho do .exe: ${RESET}"
    read -r SELECTED
    SELECTED="${SELECTED//\'/}"; SELECTED="${SELECTED//\"/}"
    SELECTED="${SELECTED# }";    SELECTED="${SELECTED% }"
    [ -f "$SELECTED" ] || erro "Arquivo não encontrado: '$SELECTED'"
else
    echo ""
    echo -e "  ${BOLD}${WHITE}Jogos encontrados:${RESET}"
    echo ""
    for i in "${!UNIQUE_EXES[@]}"; do
        echo -e "  ${YELLOW}[$((i+1))]${RESET}  ${BOLD}$(basename "${UNIQUE_EXES[$i]}")${RESET}"
        echo -e "        ${DIM}${UNIQUE_EXES[$i]}${RESET}"
    done
    echo ""
    echo -ne "  ${CYAN}Escolha o número: ${RESET}"
    read -r CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && \
       [ "$CHOICE" -ge 1 ] && \
       [ "$CHOICE" -le "${#UNIQUE_EXES[@]}" ]; then
        SELECTED="${UNIQUE_EXES[$((CHOICE-1))]}"
    else
        erro "Opção inválida: '$CHOICE'"
    fi
fi

[ ! -f "$SELECTED" ] && erro "Arquivo não encontrado: '$SELECTED'"

DETECTED_ARCH=$(detectar_arquitetura_exe "$SELECTED")
info "Arquitetura do exe detectada: $DETECTED_ARCH"

# ============================================================================
# DETERMINAR ARQUITETURA FINAL DO PREFIX
# ============================================================================
case "$WINE_ARCH_SUPPORT" in
    wow64)
        # WoW64: sempre usar win64 (que suporta 32-bit via syswow64)
        WINE_ARCH="win64"
        info "Modo WoW64: usando prefix 64-bit com suporte a 32-bit"
        configurar_wow64
        ;;
    win64)
        WINE_ARCH="win64"
        info "Modo 64-bit puro: apenas suporte a aplicativos 64-bit"
        ;;
    win32)
        WINE_ARCH="win32"
        info "Modo 32-bit puro: apenas suporte a aplicativos 32-bit"
        # Usa wine ao invés de wine64
        WINE_BIN="$INSTALL_DIR/bin/wine"
        [ ! -f "$WINE_BIN" ] && WINE_BIN="$INSTALL_DIR/bin/wine64"
        ;;
esac

GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$WINE67_DIR/prefixes/$GAME_NAME"
mkdir -p "$WINEPREFIX"

# --- Fix 3: prefix 32/64bit mismatch ---
# Lê a arquitetura do prefix de forma robusta:
# system.reg pode ter '#arch=win32' ou '"#arch"="win32"' dependendo da versão do Wine.
# Também verifica via pasta drive_c/windows/syswow64 (só existe em win64).
_prefix_arch() {
    local reg="$WINEPREFIX/system.reg"
    local arch=""

    if [ -f "$reg" ]; then
        # Tenta formato: #arch=win32 ou #arch=win64
        arch=$(grep -m1 '#arch=' "$reg" 2>/dev/null \
               | sed 's/.*#arch=\([a-z0-9]*\).*/\1/' | tr -d '\r\n ')
    fi

    # Fallback: presença de syswow64 indica prefix win64
    if [ -z "$arch" ]; then
        if [ -d "$WINEPREFIX/drive_c/windows/syswow64" ]; then
            arch="win64"
        elif [ -d "$WINEPREFIX/drive_c/windows" ]; then
            arch="win32"
        fi
    fi

    echo "$arch"
}

if [ -f "$WINEPREFIX/system.reg" ]; then
    existing_arch=$(_prefix_arch)
    if [ -z "$existing_arch" ]; then
        aviso "Não foi possível detectar arquitetura do prefix existente — recriando com $WINE_ARCH..."
        rm -rf "$WINEPREFIX"
        mkdir -p "$WINEPREFIX"
    elif [ "$existing_arch" != "$WINE_ARCH" ]; then
        aviso "Prefix existente é '$existing_arch' mas você escolheu '$WINE_ARCH'."
        aviso "Recriando prefix com arquitetura correta ($WINE_ARCH)..."
        rm -rf "$WINEPREFIX"
        mkdir -p "$WINEPREFIX"
    fi
fi

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    info "Criando prefix Windows ($WINE_ARCH)..."
    WINEARCH="$WINE_ARCH" WINEPREFIX="$WINEPREFIX" \
        "$WINE_BIN" wineboot -i 2>/dev/null &
    boot_pid=$!
    spinner "$boot_pid" "Inicializando ambiente Windows ($WINE_ARCH)..."
    wait "$boot_pid" || true
    ok "Prefix pronto ($WINE_ARCH)"
fi

echo ""
echo -e "  ${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "  ${GREEN}║  🎮  $(basename "$SELECTED")${RESET}"
echo -e "  ${GREEN}║  🔧  Arch: $WINE_ARCH (modo: $WINE_ARCH_SUPPORT)${RESET}"
echo -e "  ${GREEN}║  🚀  $MODO_LABEL + DXVK${RESET}"
echo -e "  ${GREEN}║  📁  Prefix: $GAME_NAME${RESET}"
echo -e "  ${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# ============================================================================
# EXECUTAR
# ============================================================================
WINEARCH="$WINE_ARCH" \
WINEPREFIX="$WINEPREFIX" \
LD_LIBRARY_PATH="$INSTALL_DIR/lib64:$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}" \
"$WINE_BIN" "$SELECTED"

EXIT=$?
echo ""
if [ $EXIT -eq 0 ]; then
    ok "Jogo encerrado normalmente."
else
    aviso "Jogo encerrado com código de saída: $EXIT"
fi
