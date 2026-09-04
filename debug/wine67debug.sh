#!/bin/bash
#
# wine67-debug.sh — versão de DEBUG do launcher Wine67
#
#   - log() / debug() com timestamp, gravados em tela E em arquivo (LOG_FILE)
#   - nada é jogado em /dev/null: toda saída de comandos fica visível/logada
#   - trap em ERR e EXIT mostra linha, comando e código de saída de falhas
#   - `set -x` opcional (ative com DEBUG_TRACE=1) grava o trace num arquivo separado
#   - resumo de ambiente (variáveis WINE*, PATH, etc) impresso antes de rodar o jogo
#   - flag --dry-run: faz tudo (baixa, extrai, prepara prefix) mas NÃO executa o .exe
#
#   ./wine67-debug.sh                # debug normal
#   DEBUG_TRACE=1 ./wine67-debug.sh  # + bash -x completo
#   ./wine67-debug.sh --dry-run      # não executa o jogo no final

set -o pipefail
set -E   # trap ERR é herdado por funções/subshells

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.cache/wine67"
WINE_BIN="$INSTALL_DIR/bin/wine"

LOG_DIR="$SCRIPT_DIR/wine67-debug-logs"
mkdir -p "$LOG_DIR"
TS="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/debug-$TS.log"
TRACE_FILE="$LOG_DIR/trace-$TS.log"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
    esac
done


if [[ "${DEBUG_TRACE:-0}" == "1" ]]; then
    exec 9>"$TRACE_FILE"
    export BASH_XTRACEFD=9
    PS4='+ [\D{%H:%M:%S}] ${BASH_SOURCE##*/}:${LINENO}: '
    set -x
fi

# CORES
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'; BLUE='\033[0;34m'

_ts() { date '+%H:%M:%S'; }


log() {
    echo -e "$1" | tee -a "$LOG_FILE" >&2
}

debug() { log "  ${DIM}[$(_ts)] [DEBUG] $1${RESET}"; }
erro()  { log "${RED}[$(_ts)] ❌ ERRO: $1${RESET}"; exit 1; }
ok()    { log "${GREEN}[$(_ts)] ✔  $1${RESET}"; }
info()  { log "${CYAN}[$(_ts)] ➜  $1${RESET}"; }
aviso() { log "${YELLOW}[$(_ts)] ⚠  $1${RESET}"; }

# TRAP DE ERRO — mostra exatamente onde quebrou
trap 'ultimo_status=$?; if [[ $ultimo_status -ne 0 ]]; then
    log "${RED}${BOLD}[$(_ts)] ✖ FALHA${RESET}"
    log "${RED}  comando : ${BASH_COMMAND}${RESET}"
    log "${RED}  arquivo : ${BASH_SOURCE[0]}:${LINENO}${RESET}"
    log "${RED}  função  : ${FUNCNAME[*]:-<main>}${RESET}"
    log "${RED}  status  : ${ultimo_status}${RESET}"
fi' ERR

trap 'log "${DIM}[$(_ts)] log completo salvo em: $LOG_FILE${RESET}"; \
      [[ "${DEBUG_TRACE:-0}" == "1" ]] && log "${DIM}trace (set -x) salvo em: $TRACE_FILE${RESET}"' EXIT

log "${DIM}=== sessão de debug iniciada em $(_ts), log em $LOG_FILE ===${RESET}"
debug "argumentos recebidos: $*"
debug "DRY_RUN=$DRY_RUN  DEBUG_TRACE=${DEBUG_TRACE:-0}"

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
    debug "consultando API do GitHub por última release do Wine-Builds..."
    url=$(curl -sS --max-time 15 "https://api.github.com/repos/Kron4ek/Wine-Builds/releases/latest" 2>>"$LOG_FILE" | \
          grep -o "https://github.com/Kron4ek/Wine-Builds/releases/download/.*/wine-.*-amd64-wow64.tar.xz" | head -n1)

    if [ -z "$url" ]; then
        aviso "API do GitHub indisponível — usando versão fallback"
        url="https://github.com/Kron4ek/Wine-Builds/releases/download/11.10/wine-11.10-amd64-wow64.tar.xz"
    fi
    debug "URL escolhida: $url"
    echo "$url"
}

# Checagens de dependências (cada uma logada individualmente)
for cmd in curl tar bash; do
    if command -v "$cmd" &>/dev/null; then
        debug "dependência ok: $cmd -> $(command -v "$cmd")"
    else
        erro "Instale o comando '$cmd' para continuar."
    fi
done

(( BASH_VERSINFO[0] >= 4 )) || erro "Bash 4.0 ou superior necessário (versão atual: $BASH_VERSION)"
debug "bash versão: $BASH_VERSION"

mkdir -p "$INSTALL_DIR"
debug "INSTALL_DIR=$INSTALL_DIR"
debug "SCRIPT_DIR=$SCRIPT_DIR"

{
    echo -e "${MAGENTA}${BOLD}"
    echo "  ██╗    ██╗██╗███╗   ██╗███████╗ ██████╗ ███████╗   [DEBUG BUILD]"
    echo "  ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚════██║"
    echo "  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝"
    echo "  ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ "
    echo "  ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
    echo "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
    echo -e "${RESET}"
    echo -e "  ${DIM}Wine-Kron4ek wow64 Portable Launcher — sem sudo — modo DEBUG${RESET}"
    echo -e "  ${DIM}Base: $INSTALL_DIR${RESET}"
    echo -e "  ${DIM}Log:  $LOG_FILE${RESET}"
    echo ""
} | tee -a "$LOG_FILE"

verificar_espaco() {
    local destino="$1"
    local minimo_mb="${2:-1500}"
    local disponivel_mb
    disponivel_mb=$(df -m "$destino" 2>/dev/null | awk 'NR==2 {print $4}')
    debug "espaço disponível em '$destino': ${disponivel_mb:-desconhecido}MB (mínimo: ${minimo_mb}MB)"
    if [ -n "$disponivel_mb" ] && [ "$disponivel_mb" -lt "$minimo_mb" ]; then
        erro "Espaço insuficiente em disco: ${disponivel_mb}MB disponíveis, mínimo ${minimo_mb}MB necessários."
    fi
}

baixar() {
    local url="$1" dest="$2" nome="$3"

    verificar_espaco "$(dirname "$dest")"

    info "Baixando $nome..."
    debug "URL: $url"
    debug "destino: $dest"

    if ! curl -L --max-time 600 -v -o "$dest" "$url" 2>>"$LOG_FILE"; then
        rm -f "$dest"
        erro "Falha ao baixar $nome. Verifique sua conexão. Veja detalhes em $LOG_FILE"
    fi

    if command -v file &>/dev/null; then
        local tipo
        tipo=$(file "$dest" 2>/dev/null)
        debug "tipo de arquivo detectado: $tipo"
        if echo "$tipo" | grep -qi "HTML\|ASCII text"; then
            rm -f "$dest"
            erro "Servidor retornou erro ao baixar $nome (resposta não é um arquivo válido)."
        fi
    fi

    ok "Download concluído: $(du -h "$dest" | cut -f1)"
}

buscar_tar() {
    local padroes=("wine-*-amd64-wow64.tar.xz" "wine-*.tar.xz" "wine-*.tar.gz" "wine-*.tar")
    local resultado

    for padrao in "${padroes[@]}"; do
        debug "procurando padrão '$padrao' em $SCRIPT_DIR (profundidade 3)"
        resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" -type f -print -quit 2>/dev/null)
        [[ -n "$resultado" ]] && echo "$resultado" && return 0

        debug "procurando padrão '$padrao' em /media /run/media /mnt"
        resultado=$(find /media /run/media /mnt -maxdepth 3 -name "$padrao" -type f -print -quit 2>/dev/null)
        [[ -n "$resultado" ]] && echo "$resultado" && return 0
    done
    return 1
}

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
    debug "flags de tar escolhidas: extrair=$TAR_FLAG testar=$TEST_FLAG"

    info "Verificando integridade do arquivo..."
    if ! tar "$TEST_FLAG" "$GE_TAR" 2>>"$LOG_FILE"; then
        rm -f "$GE_TAR"
        erro "Arquivo corrompido ou incompleto. Delete '$INSTALL_DIR' e tente novamente."
    fi
    ok "Arquivo íntegro."

    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR" --strip-components=1 -v >>"$LOG_FILE" 2>&1 &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo Wine (pode demorar)..."
    wait "$tar_pid" || erro "Falha ao extrair. Delete '$INSTALL_DIR' e tente novamente. Veja $LOG_FILE"

    find "$INSTALL_DIR/bin" -type f -print0 2>/dev/null | xargs -0 chmod +x 2>>"$LOG_FILE"
    debug "conteúdo de $INSTALL_DIR/bin:"
    ls -la "$INSTALL_DIR/bin" 2>>"$LOG_FILE" | tee -a "$LOG_FILE" >/dev/null

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

    if [[ -f "$exe_dir/UnityPlayer.dll" ]]; then
        debug "UnityPlayer.dll encontrado em $exe_dir"
        return 0
    fi

    if find "$exe_dir" -maxdepth 1 -type d -name "*_Data" -print -quit 2>/dev/null | grep -q .; then
        debug "pasta *_Data encontrada em $exe_dir"
        return 0
    fi

    debug "nenhum indício de Unity encontrado em $exe_dir"
    return 1
}

# INSTALAÇÃO
if [[ ! -f "$WINE_BIN" ]]; then
    debug "$WINE_BIN não existe, instalando..."
    instalar_wine
else
    debug "$WINE_BIN já existe, pulando instalação"
fi

[[ ! -x "$WINE_BIN" ]] && chmod +x "$WINE_BIN"

ok "Wine: $WINE_BIN"
ok "Versão: $("$WINE_BIN" --version 2>>"$LOG_FILE" || echo 'desconhecida')"

# VARIÁVEIS DE AMBIENTE
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64:${LD_LIBRARY_PATH:-}"
export PATH="$INSTALL_DIR/bin:$PATH"
export WINELOADER="$WINE_BIN"
export WINESERVER="$INSTALL_DIR/bin/wineserver"

if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    debug "sessão wayland detectada, forçando backend x11"
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

[ -z "${DISPLAY:-}" ] && export DISPLAY=:0
debug "DISPLAY=$DISPLAY  XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-desconhecido}"

if grep -qw "futex_waitv" /proc/kallsyms 2>/dev/null || [ -e /dev/futex-waitv ]; then
    export WINEESYNC=1
    export WINEFSYNC=1
    debug "futex_waitv suportado -> WINEESYNC=1 WINEFSYNC=1"
else
    export WINE_DISABLE_FAST_SYNC=1
    debug "futex_waitv NÃO suportado -> WINE_DISABLE_FAST_SYNC=1"
fi

export WINEDLLOVERRIDES="uiautomationcore=d;oleacc=d;tabtip.exe=d;winemenubuilder=d;rpcss=n;midimap=n;steam_api=b,n"
export NO_AT_BRIDGE=1
export QT_ACCESSIBILITY=0

# RESUMO DE AMBIENTE — só existe na versão debug
{
    echo -e "${BLUE}${BOLD}--- resumo de ambiente (debug) ---${RESET}"
    for var in WINEPREFIX WINEARCH WINELOADER WINESERVER WINEDLLOVERRIDES \
               WINEESYNC WINEFSYNC WINE_DISABLE_FAST_SYNC LD_LIBRARY_PATH \
               DISPLAY XDG_SESSION_TYPE PULSE_SERVER; do
        printf "  %-22s = %s\n" "$var" "${!var:-<não definida>}"
    done
    echo -e "${BLUE}${BOLD}-----------------------------------${RESET}"
} | tee -a "$LOG_FILE"

# BUSCAR JOGOS (.EXE)
echo ""
info "Procurando jogos em $SCRIPT_DIR ..."

declare -a EXES
mapfile -t EXES < <(find "$SCRIPT_DIR" -name "*.exe" -not -path "*/.cache/wine67/*" -type f 2>>"$LOG_FILE" | sort)
debug "encontrados ${#EXES[@]} arquivo(s) .exe"

SELECTED=""

if (( ${#EXES[@]} == 0 )); then
    echo ""
    echo -ne "  ${YELLOW}Nenhum .exe encontrado. Digite o caminho: ${RESET}"
    read -r SELECTED
    SELECTED=$(limpar_entrada "$SELECTED")
    [[ -f "$SELECTED" ]] || erro "Arquivo não encontrado: '$SELECTED'"
else
    echo ""
    echo -e "  ${BOLD}Jogos encontrados:${RESET}"
    echo ""
    for i in "${!EXES[@]}"; do
        echo -e "  ${YELLOW}[$((i+1))]${RESET}  ${BOLD}$(basename "${EXES[$i]}")${RESET}"
        echo -e "        ${DIM}${EXES[$i]}${RESET}"
    done
    echo ""
    echo -e "  ${CYAN}[0]${RESET}  Digitar caminho manualmente"
    echo ""
    echo -ne "  ${CYAN}Escolha: ${RESET}"
    read -r CHOICE
    debug "escolha do usuário: '$CHOICE'"

    if [[ "$CHOICE" == "0" ]]; then
        echo -ne "  Caminho: "
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
debug "SELECTED=$SELECTED"

# PREFIX ISOLADO POR JOGO
GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$INSTALL_DIR/prefixes/$GAME_NAME"
debug "GAME_NAME=$GAME_NAME  WINEPREFIX=$WINEPREFIX"

if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
    mkdir -p "$WINEPREFIX"
    info "Inicializando ambiente do jogo pela primeira vez..."
    WINEARCH=win64 "$WINE_BIN" wineboot -i >>"$LOG_FILE" 2>&1 &
    boot_pid=$!
    spinner "$boot_pid" "Configurando ambiente Wine..."
    wait "$boot_pid" || aviso "wineboot terminou com código não-zero, veja $LOG_FILE"
else
    debug "prefix já inicializado ($WINEPREFIX/system.reg existe)"
fi

# DETECTAR UNITY E MONTAR COMANDO
EXTRA_FLAGS=""
if detectar_unity "$SELECTED"; then
    aviso "Jogo Unity detectado — aplicando flags de compatibilidade D3D11"
    EXTRA_FLAGS="-force-d3d11 -nolog"
fi

PULSE_SOCKET=$(pactl info 2>>"$LOG_FILE" | grep 'Server String' | awk '{print $3}')
if [[ -n "$PULSE_SOCKET" ]]; then
    export PULSE_SERVER="unix:$PULSE_SOCKET"
    debug "PULSE_SERVER=$PULSE_SERVER"
else
    debug "não foi possível detectar socket do PulseAudio/PipeWire"
fi

echo ""
{
    echo -e "  ${GREEN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${GREEN}║  🎮  $(basename "$SELECTED")${RESET}"
    [[ -n "$EXTRA_FLAGS" ]] && echo -e "  ${GREEN}║  🔧  Flags: $EXTRA_FLAGS${RESET}"
    echo -e "  ${GREEN}║  📁  Prefix: $GAME_NAME${RESET}"
    echo -e "  ${GREEN}╚══════════════════════════════════════════════════╝${RESET}"
} | tee -a "$LOG_FILE"
echo ""

declare -a wine_args=("$SELECTED")
[[ -n "$EXTRA_FLAGS" ]] && wine_args+=($EXTRA_FLAGS)
debug "comando final: WINEARCH=win64 $WINE_BIN ${wine_args[*]}"

if (( DRY_RUN == 1 )); then
    aviso "--dry-run ativo: tudo foi preparado, mas o jogo NÃO será executado."
    exit 0
fi

WINEARCH=win64 "$WINE_BIN" "${wine_args[@]}" 2>>"$LOG_FILE"

EXIT=$?
echo ""
(( EXIT == 0 )) && ok "Encerrado normalmente." || aviso "Código de saída: $EXIT (detalhes em $LOG_FILE)"