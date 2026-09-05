#!/bin/bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.cache/wine67"
WINE_BIN="$INSTALL_DIR/bin/wine"

# PARSING DE FLAGS
DISABLE_MONO=0
DISABLE_GECKO=0
RUN_WINETRICKS=0
EXE_ARG=""
UNPREDICTABLE=0
RUN_SHELL=0
RUN_WINECFG=0

mostrar_ajuda() {
        cat <<'EOF'
Wine67 — inicializador do Wine

Uso:
    wine67.sh [opções] [programa.exe]

Opções:
    --dontdotnet       Desativa o Wine Mono.
    --dontgecko        Desativa o Wine Gecko.
    --help, -?         Mostra esta ajuda e sai.
    --why              Não ouse.
    --lol              HAHAHAHAHAHAAHAHA.
    --chaos            Ativa o modo caos e sai.
    --beer             Oferece uma lição de moral sobre bebidas alcoólicas.
    --unpredictable    Ativa comportamento aleatório (para testes) (mentira).
    --panic            Remove o Wine e sai (modo destrutivo).
    --igotsudo         Verifica se você tem privilégios de sudo.
    --winetricks       Abre o winetricks (se instalado).
    --debug            Ativa o modo de depuração (set -x).
    --saymyname        Mostra seu nome de usuário (ou Heisenberg).
    --todaysword       Mostra uma palavra aleatória do dicionário, com certeza útil.
    --nevernude        Você é Tobias Fünke? Se sim, use esta flag.
    --make-me-a-sandwich    Se você é root, faz um sanduíche. Se não, manda você se virar.
    --imadeahugemistake     Se você é Gob Bluth, então sim, você fez uma grande besteira.

O Wine é instalado em:
    ~/.cache/wine67
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dontdotnet) DISABLE_MONO=1 ;;
        --debug) set -x ;;
        --panic) rm -rf "$INSTALL_DIR" && echo "Pânico! Wine removido." && exit 0 ;;
        --igotsudo) 
            if sudo -n true 2>/dev/null; then
                echo "Você tem privilégios de sudo."
            else
                echo "Você não tem privilégios de sudo."
            fi
            exit 0
            ;;
        --winetricks)
            RUN_WINETRICKS=1
            ;;
        --unpredictable)
            UNPREDICTABLE=1
            set +e
            ;;
        --dontgecko)  DISABLE_GECKO=1 ;;
        --test)        echo "Isso é um teste." ;;
        --lol)        
             for i in {1..50}; do
                echo "HAHAHAHAHAHAAHAHA"
            done
            exit 42
            ;;
        --why) 
            echo "Por que você está executando este script? É apenas um inicializador do Wine. Se quiser jogar, fique à vontade. Se quiser modificá-lo, fique à vontade. Mas, se está apenas curioso, então por quê?"
            sleep 10
            echo "Apenas saia daqui e nunca mais use --why."
            sleep 10
            echo "O que você está esperando? Saia daqui! Pressione Ctrl+C para sair ou simplesmente feche o terminal. Eu não me importo."
            sleep 10
            echo "Ultimato: se você não sair agora, vai ganhar uma ferrovia grande, 20 trens. E você não quer isso. Você tem 15 segundos."
            sleep 15
            echo "Está bem, você pediu por isso"
            for i in {1..20}; do
                sl &
            done
            exit 42
            ;;
        --chaos) 
            echo "Você ativou o modo caos. Boa sorte."
            sleep 5
            echo -e "\a"
            for i in {1..200}; do
                sl &
            done
            exit 666
            ;;
        --help|-?)
            mostrar_ajuda
            exit 0
            ;;
        --beer)
            echo "Isso é Wine, que é vinho, mas não é cerveja. Se você quer cerveja, se vire."
            exit 0
            ;;
        --winecfg)
            RUN_WINECFG=1
            ;;
        --shell)
            RUN_SHELL=1
            ;;
        --saymyname)
            echo "Seu nome é $(whoami). Ou Heisenberg. Depende de como você se enxerga."
            exit 0
            ;;
        --todaysword)
            echo "A palavra do dia é: $(shuf -n1 /usr/share/dict/words 2>/dev/null || echo 'Dona')"
            sleep 10
            ;; 
        --nevernude)
            echo "Por acaso você é Tobias Fünke?"
            sleep 5 
            echo "Acho que você merece esse script, vai lá jogar."
            sleep 2
            ;;
        --make-me-a-sandwich)
            if [ "$EUID" -ne 0 ]; then
                echo "O quê? Faça você mesmo."
            else
                echo "Ok, saindo um sanduíche!"
            fi
            exit 0
            ;;
        --imadeahugemistake)
            echo "Você explodiu um iate de novo, Gob?"
            sleep 5
            echo "Você é um idiota, Gob."
            sleep 5
            exit 1
            ;;
        *)            EXE_ARG="$arg" ;;
        
    esac
done

if (( UNPREDICTABLE )); then
    for variable in DISABLE_MONO DISABLE_GECKO RUN_WINETRICKS RUN_SHELL RUN_WINECFG; do
        if (( RANDOM % 4 == 0 )); then
            printf -v "$variable" '%d' "$((1 - ${!variable}))"
        fi
    done
fi 

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
    echo "  ██╗    ██╗██╗███╗   ██╗███████╗ ██████╗ ███████╗"
    echo "  ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚════██║"
    echo "  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝"
    echo "  ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ "
    echo "  ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
    echo "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
    echo -e "${RESET}"
    echo -e "  ${DIM}Wine-Kron4ek wow64 Portable Launcher — sem sudo${RESET}"
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

WINEDLLOVERRIDES_BASE="uiautomationcore=d;oleacc=d;tabtip.exe=d;winemenubuilder=d;rpcss=n;midimap=n;steam_api=b,n"
(( DISABLE_MONO == 1 ))  && WINEDLLOVERRIDES_BASE+=";mscoree=d"
(( DISABLE_GECKO == 1 )) && WINEDLLOVERRIDES_BASE+=";mshtml=d"
export WINEDLLOVERRIDES="$WINEDLLOVERRIDES_BASE"
export NO_AT_BRIDGE=1
export QT_ACCESSIBILITY=0
#RUN_WINECFG e RUN_SHELL para abrir winecfg ou shell do prefixo.
if (( RUN_SHELL == 1 )); then
    info "Abrindo shell do prefixo Wine..."
    exec "$WINE_BIN" cmd
fi
if (( RUN_WINECFG == 1 )); then
    info "Abrindo winecfg..."
    exec "$WINE_BIN" winecfg
fi


# ABRIR WINETRICKS
if (( RUN_WINETRICKS == 1 )); then
    command -v winetricks &>/dev/null || erro "Instale o 'winetricks' para continuar."
    export WINEPREFIX="$INSTALL_DIR/prefixes/winetricks"
    mkdir -p "$WINEPREFIX"
    exec winetricks --gui
fi


# BUSCAR JOGOS (.EXE)
echo ""

declare -a EXES
SELECTED=""

# MODO DIRETO: se um caminho de .exe foi passado como argumento, pula a busca/prompt
if [[ -n "$EXE_ARG" ]]; then
    SELECTED="$(limpar_entrada "$EXE_ARG")"
    [[ -f "$SELECTED" ]] || erro "Arquivo não encontrado: '$SELECTED'"
    ok "Modo direto: $(basename "$SELECTED")"
else
    info "Procurando jogos em $SCRIPT_DIR ..."
    mapfile -t EXES < <(find "$SCRIPT_DIR" -name "*.exe" -not -path "*/.cache/wine67/*" -type f 2>/dev/null | sort)

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
fi

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