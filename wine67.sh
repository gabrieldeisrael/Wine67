name=wine67.sh
```bash
#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.cache/wine67"
WINE_BIN="$INSTALL_DIR/bin/wine"

# CORES
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'

# FUNÇÕES DE LOG
erro()  { printf "%b\n" "${RED}❌ $1${RESET}" >&2; exit "${2:-1}"; }
ok()    { printf "%b\n" "${GREEN}✔  $1${RESET}"; }
info()  { printf "%b\n" "${CYAN}➜  $1${RESET}"; }
aviso() { printf "%b\n" "${YELLOW}⚠  $1${RESET}"; }

# Cleanup temp files on exit
_tmp_files=()
cleanup() {
    for f in "${_tmp_files[@]:-}"; do
        [[ -e "$f" ]] && rm -f "$f"
    done
}
trap cleanup EXIT INT TERM

# Limpar aspas de strings de entrada
limpar_entrada() {
    local entrada="$1"
    entrada="${entrada//\'/}"
    entrada="${entrada//\"/}"
    entrada="${entrada#"${entrada%%[![:space:]]*}"}"  # ltrim
    entrada="${entrada%"${entrada##*[![:space:]]}"}"  # rtrim
    printf "%s" "$entrada"
}

spinner() {
    local pid=$1 msg="${2:-Carregando...}"
    local spin='/-\|'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}[${spin:$i:1}]${RESET}  %s" "$msg"
        i=$(( (i+1) % ${#spin} ))
        sleep 0.1
    done
    printf "\r  ${GREEN}[✔]${RESET}  %s\n" "$msg"
}

obter_url_wine() {
    # Prefer jq if available
    local api_url="https://api.github.com/repos/Kron4ek/Wine-Builds/releases/latest"
    local url=""

    if command -v curl >/dev/null 2>&1; then
        local json
        json="$(curl -s --max-time 15 "$api_url" 2>/dev/null || true)"
        if command -v jq >/dev/null 2>&1 && [[ -n "$json" ]]; then
            url="$(printf "%s" "$json" | jq -r '.assets[]?.browser_download_url // empty' \
                  | grep -E "wine-.*(amd64|x86_64).*wow64.*\.tar\.xz" | head -n1 || true)"
        else
            # Fallback to grep if jq not available
            url="$(printf "%s" "$json" | grep -o "https://github.com/Kron4ek/Wine-Builds/releases/download/.*/wine-.*-amd64-wow64.tar.xz" | head -n1 || true)"
        fi
    fi

    if [[ -z "$url" ]]; then
        aviso "API do GitHub indisponível ou sem asset esperado — usando versão fallback"
        url="https://github.com/Kron4ek/Wine-Builds/releases/download/11.10/wine-11.10-amd64-wow64.tar.xz"
    fi

    printf "%s" "$url"
}

# Checagens de dependências
command -v curl >/dev/null 2>&1 || erro "Instale o comando 'curl' para continuar."
command -v tar  >/dev/null 2>&1 || erro "'tar' não encontrado."
command -v bash >/dev/null 2>&1 || erro "'bash' não encontrado."

# Verifica versão do bash (mapfile requer bash >= 4.0)
(( BASH_VERSINFO[0] >= 4 )) || erro "Bash 4.0 ou superior necessário (versão atual: $BASH_VERSION)"

mkdir -p "$INSTALL_DIR"

# EXIBIR BANNER
{
    printf "%b\n" "${MAGENTA}${BOLD}"
    printf "  ██╗    ██╗██╗███╗   ██╗███████╗ ██████╗ ███████╗\n"
    printf "  ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚════██║\n"
    printf "  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝\n"
    printf "  ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ \n"
    printf "  ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  \n"
    printf "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  \n"
    printf "%b\n" "${RESET}"
    printf "  ${DIM}Wine-Kron4ek wow64 Portable Launcher — sem sudo${RESET}\n"
    printf "  ${DIM}Base: %s${RESET}\n\n" "$INSTALL_DIR"
}

# VERIFICAR ESPAÇO EM DISCO ANTES DE BAIXAR
verificar_espaco() {
    local destino="$1"
    local minimo_mb="${2:-1500}"
    local disponivel_mb

    if disponivel_mb=$(df -m "$destino" 2>/dev/null | awk 'NR==2 {print $4}'); then
        if [[ -n "$disponivel_mb" && "$disponivel_mb" -lt "$minimo_mb" ]]; then
            erro "Espaço insuficiente em disco: ${disponivel_mb}MB disponíveis, mínimo ${minimo_mb}MB necessários."
        fi
    else
        aviso "Não foi possível determinar espaço livre em $destino — pulando verificação."
    fi
}

baixar() {
    local url="$1" dest="$2" nome="$3"

    verificar_espaco "$(dirname "$dest")"

    info "Baixando $nome..."
    # Use curl with retry and max time; write to temp first
    local tmp
    tmp="$(mktemp "${dest}.XXXXXX")"
    _tmp_files+=("$tmp")

    if ! curl -L --retry 3 --retry-delay 2 --max-time 600 -# -o "$tmp" "$url"; then
        rm -f "$tmp"
        erro "Falha ao baixar $nome. Verifique sua conexão."
    fi

    # Checa se o servidor não retornou uma pagina de erro HTML
    if command -v file &>/dev/null && file "$tmp" 2>/dev/null | grep -qi "HTML\|ASCII text"; then
        rm -f "$tmp"
        erro "Servidor retornou erro ao baixar $nome (resposta não é um arquivo válido)."
    fi

    mv "$tmp" "$dest"
    _tmp_files=("${_tmp_files[@]/$tmp}")  # remove from tracked tmp list
    ok "Download concluído: $(du -h "$dest" | cut -f1)"
}

# BUSCAR .TAR LOCAL (pendrive, pasta do script, etc)
buscar_tar() {
    local padroes=("wine-*-amd64-wow64.tar.xz" "wine-*.tar.xz" "wine-*.tar.gz" "wine-*.tar")
    local resultado

    for padrao in "${padroes[@]}"; do
        if resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" -type f -print -quit 2>/dev/null); then
            [[ -n "$resultado" ]] && printf "%s" "$resultado" && return 0
        fi

        if resultado=$(find /media /run/media /mnt -maxdepth 3 -name "$padrao" -type f -print -quit 2>/dev/null); then
            [[ -n "$resultado" ]] && printf "%s" "$resultado" && return 0
        fi
    done
    return 1
}

instalar_wine() {
    info "Instalando Wine Kron4ek wow64..."
    local GE_TAR
    if GE_TAR="$(buscar_tar)"; then
        ok "Arquivo local encontrado: $GE_TAR"
    else
        GE_TAR="$INSTALL_DIR/wine-kron4ek.tar.xz"
        local WINE_URL
        WINE_URL="$(obter_url_wine)"
        baixar "$WINE_URL" "$GE_TAR" "Wine-Kron4ek wow64"
    fi

    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
        *.tar)    TAR_FLAG="-xf";  TEST_FLAG="-tf"   ;;
        *)        TAR_FLAG="-xf";  TEST_FLAG="-tf"   ;;
    esac

    info "Verificando integridade do arquivo..."
    if ! tar "$TEST_FLAG" "$GE_TAR" &>/dev/null; then
        rm -f "$GE_TAR"
        erro "Arquivo corrompido ou incompleto. Delete '$INSTALL_DIR' e tente novamente."
    fi
    ok "Arquivo íntegro."

    # Extração em background com spinner
    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR" --strip-components=1 &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo Wine (pode demorar)..."
    wait "$tar_pid" || { rm -f "$GE_TAR"; erro "Falha ao extrair. Delete '$INSTALL_DIR' e tente novamente."; }

    find "$INSTALL_DIR/bin" -type f -print0 2>/dev/null | xargs -0 chmod +x 2>/dev/null || true

    if [[ ! -f "$WINE_BIN" ]]; then
        local found
        found=$(find "$INSTALL_DIR" -name "wine" -type f -print -quit 2>/dev/null || true)
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
    local exe="$1"
    local exe_dir
    exe_dir="$(dirname "$exe")"

    [[ -f "$exe_dir/UnityPlayer.dll" ]] && return 0
    find "$exe_dir" -maxdepth 1 -type d -name "*_Data" -print -quit 2>/dev/null | grep -q . && return 0

    return 1
}

# CLI support: basic
NONINTERACTIVE=0
MANUAL_PATH=""
while [[ ${#} -gt 0 ]]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
Uso: wine67.sh [--exe /caminho/para/jogo.exe] [--prefix nome] [--non-interactive]
Opções:
  --exe PATH            Caminho para o .exe a executar (não mostra prompt)
  --prefix NAME         Nome do prefix (por padrão: basename do exe)
  --non-interactive     Não perguntar — falhar em caso de ambiguidade
  -h, --help            Mostrar esta ajuda
EOF
            exit 0
            ;;
        --exe)
            shift
            MANUAL_PATH="${1:-}"
            shift
            ;;
        --prefix)
            shift
            GAME_PREFIX_OVERRIDE="${1:-}"
            shift
            ;;
        --non-interactive)
            NONINTERACTIVE=1
            shift
            ;;
        *)
            # Unknown: treat as path maybe
            if [[ -z "${MANUAL_PATH:-}" && -f "$1" ]]; then
                MANUAL_PATH="$1"
                shift
            else
                erro "Opção desconhecida: $1"
            fi
            ;;
    esac
done

# INSTALAR WINE se necessário
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
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || "${XDG_SESSION_TYPE:-}" == "Wayland" ]]; then
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

# BUSCAR JOGOS (.EXE)
info "Procurando jogos em $SCRIPT_DIR ..."
declare -a EXES
mapfile -t EXES < <(find "$SCRIPT_DIR" -name "*.exe" -not -path "*/.cache/wine67/*" -type f 2>/dev/null | sort)

SELECTED=""

if [[ -n "${MANUAL_PATH:-}" ]]; then
    SELECTED="$(limpar_entrada "$MANUAL_PATH")"
    if [[ ! -f "$SELECTED" ]]; then
        erro "Arquivo não encontrado: '$SELECTED'"
    fi
elif (( ${#EXES[@]} == 0 )); then
    if (( NONINTERACTIVE )); then
        erro "Nenhum .exe encontrado e modo não interativo ativado."
    fi
    printf "  %bNenhum .exe encontrado. Digite o caminho: %b" "$YELLOW" "$RESET"
    read -r SELECTED
    SELECTED=$(limpar_entrada "$SELECTED")
    [[ -f "$SELECTED" ]] || erro "Arquivo não encontrado: '$SELECTED'"
else
    echo ""
    printf "  %bJogos encontrados:%b\n\n" "$BOLD" "$RESET"
    for i in "${!EXES[@]}"; do
        printf "  %b[%d]%b  %b%s%b\n" "$YELLOW" "$((i+1))" "$RESET" "$BOLD" "$(basename "${EXES[$i]}")" "$RESET"
        printf "        %b%s%b\n" "$DIM" "${EXES[$i]}" "$RESET"
    done
    echo ""
    printf "  %b[0]%b  Digitar caminho manualmente\n\n" "$CYAN" "$RESET"
    if (( NONINTERACTIVE )); then
        erro "Múltiplos .exe encontrados e modo não interativo ativado."
    fi
    printf "  %bEscolha: %b" "$CYAN" "$RESET"
    read -r CHOICE
    if [[ "$CHOICE" == "0" ]]; then
        printf "  Caminho: "
        read -r SELECTED
        SELECTED=$(limpar_entrada "$SELECTED")
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#EXES[@]} )); then
        SELECTED="${EXES[$((CHOICE-1))]}"
    else
        erro "Opção inválida: '$CHOICE'"
    fi
fi

[[ -z "$SELECTED" ]] && erro "Nenhum arquivo selecionado."
[[ ! -f "$SELECTED" ]] && erro "Arquivo não encontrado: '$SELECTED'"

# PREFIX ISOLADO POR JOGO
GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
if [[ -n "${GAME_PREFIX_OVERRIDE:-}" ]]; then
    GAME_NAME="$GAME_PREFIX_OVERRIDE"
fi
export WINEPREFIX="$INSTALL_DIR/prefixes/$GAME_NAME"

if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
    mkdir -p "$WINEPREFIX"
    info "Inicializando ambiente do jogo pela primeira vez..."
    WINEARCH=win64 "$WINE_BIN" wineboot -i &>/dev/null || true
fi

# DETECTAR UNITY E MONTAR COMANDO
EXTRA_FLAGS=""
if detectar_unity "$SELECTED"; then
    aviso "Jogo Unity detectado — aplicando flags de compatibilidade D3D11"
    EXTRA_FLAGS="-force-d3d11 -nolog"
fi

# Configura áudio via PipeWire/PulseAudio
if command -v pactl >/dev/null 2>&1; then
    PULSE_SOCKET=$(pactl info 2>/dev/null | awk -F': ' '/Server String/ {print $2}' || true)
    if [[ -n "$PULSE_SOCKET" ]]; then
        export PULSE_SERVER="unix:$PULSE_SOCKET"
    fi
fi

echo ""
printf "  ${GREEN}╔══════════════════════════════════════════════════╗${RESET}\n"
printf "  ${GREEN}║  🎮  %s${RESET}\n" "$(basename "$SELECTED")"
if [[ -n "$EXTRA_FLAGS" ]]; then
    printf "  ${GREEN}║  🔧  Flags: %s${RESET}\n" "$EXTRA_FLAGS"
fi
printf "  ${GREEN}║  📁  Prefix: %s${RESET}\n" "$GAME_NAME"
printf "  ${GREEN}╚══════════════════════════════════════════════════╝${RESET}\n\n"

# Safely split EXTRA_FLAGS into array
declare -a wine_args=("$SELECTED")
if [[ -n "$EXTRA_FLAGS" ]]; then
    # shellcheck disable=SC2206
    read -r -a extra_array <<< "$EXTRA_FLAGS"
    wine_args+=("${extra_array[@]}")
fi

WINEARCH=win64 "$WINE_BIN" "${wine_args[@]}"

EXIT=$?
echo ""
(( EXIT == 0 )) && ok "Encerrado normalmente." || aviso "Código de saída: $EXIT"
