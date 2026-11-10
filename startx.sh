#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  StartX — jogos Windows no Linux (Wine + DXVK + VKD3D-Proton), tudo portátil.
#  Compatível com jogos Source (Source 1, Source 2, GoldSrc) e Unity.
#  Rode  ./startx.sh --ajuda  para ver todas as opções.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ───────────────────────────── Argumentos globais ────────────────────────────
# Flags do StartX podem aparecer em qualquer posição e são removidas da lista,
# para não atrapalhar o resto do parsing.
DEBUG_MODE=0
ASSUME_YES=0
CLEAN_PREFIX=0
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --debug)        DEBUG_MODE=1 ;;
        --sim|--yes)    ASSUME_YES=1 ;;
        --limpo|--clean) CLEAN_PREFIX=1 ;;
        *)              ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if [ "$DEBUG_MODE" -eq 1 ]; then
    set +eu            # desativa -e e -u
    set +o pipefail    # desativa pipefail
    set -x             # modo de depuração
fi

# ───────────────────────────────── Cores ─────────────────────────────────────
C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
USE_256=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
    case "${COLORTERM:-}${TERM:-}" in *truecolor*|*24bit*|*256color*) USE_256=1 ;; esac
fi

cleanup() {
    jobs -p | xargs -r kill 2>/dev/null || true
    printf '%s' "$C_RESET"
}
trap cleanup EXIT INT TERM

# ─────────────────────────── Caminhos e configuração ─────────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BASE_DIR="$SCRIPT_DIR/portable-wine"
WINE_DIR="$BASE_DIR/wine"
PREFIX_DIR="$BASE_DIR/prefix"
DOWNLOAD_DIR="$BASE_DIR/download"
DXVK_DIR="$BASE_DIR/dxvk"
VKD3D_DIR="$BASE_DIR/vkd3d"
CACHE_DIR="$BASE_DIR/cache"

WINE_VARIANT="${WINE_VARIANT:-staging}"     # staging | vanilla
WINE_VERSION="${WINE_VERSION:-latest}"      # ex.: 11.20
DXVK_VERSION="${DXVK_VERSION:-latest}"      # ex.: 3.1.1
VKD3D_VERSION="${VKD3D_VERSION:-latest}"    # ex.: 3.0.1
ENABLE_DXVK="${ENABLE_DXVK:-1}"
ENABLE_VKD3D="${ENABLE_VKD3D:-1}"

WINE_REPO="Kron4ek/Wine-Builds"
DXVK_REPO="doitsujin/dxvk"
VKD3D_REPO="HansKristian-Work/vkd3d-proton"

# Usadas só se não for possível descobrir a versão mais recente (sem internet
# para o github.com, por exemplo).
FALLBACK_WINE="11.20"
FALLBACK_DXVK="3.1.1"
FALLBACK_VKD3D="3.0.1"
# Última versão do DXVK que roda em GPUs com Vulkan 1.1/1.2 (a série 2.x/3.x exige 1.3).
LEGACY_DXVK="1.10.3"

declare -a WENV=()          # ambiente usado para rodar o Wine
declare -a GAME_PATHS=()
declare -a GAME_TAGS=()

# ───────────────────────────────── Mensagens ─────────────────────────────────
log()  { printf '\n%s==>%s %s\n' "$C_BOLD$C_CYAN" "$C_RESET" "$1" >&2; }
ok()   { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1" >&2; }
err()  { printf '%sErro:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
warn() { printf '%s⚠ Aviso:%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

pause() {
    printf '\n  %sPressione Enter para continuar...%s' "$C_DIM" "$C_RESET"
    read -r _ || true
}

# Pergunta sim/não. $1 = texto, $2 = padrão (n ou s).
confirm() {
    local text="$1" def="${2:-n}" ans hint="[s/N]"
    [ "$def" = "s" ] && hint="[S/n]"
    if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
    if [ ! -t 0 ]; then
        err "Preciso de confirmação. Rode em um terminal ou adicione --sim."
        return 1
    fi
    printf '\n  %s %s ' "$text" "$hint" >&2
    read -r ans || return 1
    ans="${ans,,}"
    if [ -z "$ans" ]; then ans="$def"; fi
    case "$ans" in s|sim|y|yes) return 0 ;; *) return 1 ;; esac
}

# ─────────────────────────────── Rede / downloads ────────────────────────────
fetch() {
    local url="$1" dest="$2"
    if have curl; then
        curl -fL --retry 3 --connect-timeout 20 --progress-bar -o "$dest.part" "$url" \
            || { rm -f "$dest.part"; return 1; }
    elif have wget; then
        wget -q --show-progress -O "$dest.part" "$url" \
            || { rm -f "$dest.part"; return 1; }
    else
        err "Preciso de 'curl' ou 'wget' para baixar, e não achei nenhum dos dois."
        return 1
    fi
    mv -f "$dest.part" "$dest"
}

# Descobre a última versão de um repositório pelo redirect de /releases/latest.
# (Não usa a API do GitHub, que limita a 60 requisições por hora sem login.)
latest_tag() {
    local repo="$1" loc="" tag
    if have curl; then
        loc="$(curl -sSI -o /dev/null -w '%{redirect_url}' --connect-timeout 15 \
            "https://github.com/${repo}/releases/latest" 2>/dev/null || true)"
    elif have wget; then
        loc="$(wget -q --spider --max-redirect=0 -S "https://github.com/${repo}/releases/latest" 2>&1 \
            | sed -n 's/^ *[Ll]ocation: *//p' | head -n1 | tr -d '\r' || true)"
    fi
    tag="${loc##*/}"
    if [[ "$tag" =~ ^v?[0-9]+(\.[0-9]+)*$ ]]; then printf '%s' "$tag"; fi
    return 0
}

# resolve_version <repo> <pedida|latest> <fallback>  →  imprime a versão sem "v"
resolve_version() {
    local repo="$1" want="$2" fb="$3" tag
    if [ "$want" != "latest" ]; then
        printf '%s' "${want#v}"
        return 0
    fi
    tag="$(latest_tag "$repo")"
    if [ -z "$tag" ]; then
        warn "Não consegui checar a versão mais recente de $repo; usando $fb."
        tag="$fb"
    fi
    printf '%s' "${tag#v}"
}

# version_ge A B → verdadeiro se A >= B
version_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }

# ─────────────────────────────── Estado / checagens ──────────────────────────
wine_installed()  { [ -x "$WINE_DIR/bin/wine" ]; }
dxvk_installed()  { [ -f "$DXVK_DIR/x64/d3d11.dll" ]; }
vkd3d_installed() { [ -f "$VKD3D_DIR/x64/d3d12.dll" ]; }
prefix_ready()    { [ -f "$PREFIX_DIR/system.reg" ]; }

is_ready() {
    wine_installed || return 1
    prefix_ready || return 1
    if [ "$ENABLE_DXVK" = "1" ]; then dxvk_installed || return 1; fi
    return 0
}

comp_version() {
    if [ -f "$1/VERSION" ]; then cat "$1/VERSION"; fi
    return 0
}

check_arch() {
    local m
    m="$(uname -m)"
    if [ "$m" != "x86_64" ]; then
        err "Este script foi feito para máquinas x86_64 (encontrei: $m)."
        exit 1
    fi
}

# Versão mais alta de Vulkan suportada pelas GPUs (ex.: "1.3"). Vazio se não der para saber.
vulkan_api() {
    have vulkaninfo || return 0
    vulkaninfo --summary 2>/dev/null | grep -i 'apiVersion' | grep -oE '[0-9]+\.[0-9]+' | sort -V | tail -n1 || true
    return 0
}

check_vulkan() {
    if have vulkaninfo; then return 0; fi
    if have ldconfig && ldconfig -p 2>/dev/null | grep -q 'libvulkan\.so\.1'; then return 0; fi
    warn "Vulkan não encontrado! O DXVK/VKD3D precisam de drivers Vulkan:"
    warn "  Intel/AMD: sudo apt install vulkan-tools libvulkan1 mesa-vulkan-drivers"
    warn "  NVIDIA:    sudo apt install vulkan-tools libvulkan1 (+ driver proprietário)"
    return 1
}

# Avisa sobre bibliotecas do sistema que o Wine precisa e não estão instaladas.
check_wine_libs() {
    have ldd || return 0
    local so missing=""
    for so in "$WINE_DIR"/lib/wine/x86_64-unix/{ntdll,winex11,winepulse,winealsa}.so; do
        [ -f "$so" ] || continue
        missing+="$(ldd "$so" 2>/dev/null | awk '/not found/ {print $1}')"$'\n'
    done
    # Os módulos do próprio Wine (ntdll.so, win32u.so...) aparecem como "not found" no ldd,
    # mas o Wine os resolve sozinho: só interessam as bibliotecas do sistema.
    local name real=""
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if [ -e "$WINE_DIR/lib/wine/x86_64-unix/$name" ]; then continue; fi
        real+="$name "
    done < <(printf '%s' "$missing" | sort -u)
    missing="$real"
    if [ -n "$missing" ]; then
        warn "Bibliotecas do sistema ausentes: $missing"
        warn "Debian/Ubuntu: sudo apt install libvulkan1 libx11-6 libfreetype6 libpulse0 libasound2t64"
    fi
    return 0
}

# ───────────────────────────────── Instalação ────────────────────────────────
install_wine() {
    check_arch
    if wine_installed; then return 0; fi

    mkdir -p "$BASE_DIR" "$DOWNLOAD_DIR" "$PREFIX_DIR"
    local ver suffix url dest
    if [ "$WINE_VARIANT" = "staging" ]; then suffix="staging-amd64-wow64.tar.xz"; else suffix="amd64-wow64.tar.xz"; fi
    ver="$(resolve_version "$WINE_REPO" "$WINE_VERSION" "$FALLBACK_WINE")"
    url="https://github.com/${WINE_REPO}/releases/download/${ver}/wine-${ver}-${suffix}"
    dest="$DOWNLOAD_DIR/wine-${ver}-${suffix}"

    log "Baixando Wine $ver ($WINE_VARIANT)..."
    fetch "$url" "$dest" || { err "Falha ao baixar o Wine ($url)"; return 1; }

    log "Extraindo Wine..."
    rm -rf "$WINE_DIR"; mkdir -p "$WINE_DIR"
    tar -xf "$dest" -C "$WINE_DIR" --strip-components=1 || { err "Falha ao extrair o Wine"; return 1; }
    rm -f "$dest"

    wine_installed || { err "Wine não foi instalado corretamente"; return 1; }
    ok "Wine instalado: $("$WINE_DIR/bin/wine" --version 2>/dev/null || echo "$ver")"
}

install_dxvk() {
    if [ "$ENABLE_DXVK" != "1" ]; then log "DXVK desativado"; return 0; fi
    if dxvk_installed; then return 0; fi

    check_vulkan || true
    mkdir -p "$DOWNLOAD_DIR"
    local ver api tmp src
    ver="$DXVK_VERSION"
    if [ "$ver" = "latest" ]; then
        api="$(vulkan_api)"
        if [ -n "$api" ] && ! version_ge "$api" "1.3"; then
            warn "Sua GPU expõe Vulkan $api (< 1.3). Usando DXVK $LEGACY_DXVK, compatível com Vulkan 1.1+."
            ver="$LEGACY_DXVK"
        fi
    fi
    ver="$(resolve_version "$DXVK_REPO" "$ver" "$FALLBACK_DXVK")"

    log "Baixando DXVK $ver (Direct3D 8/9/10/11 → Vulkan)..."
    tmp="$(mktemp -d "$DOWNLOAD_DIR/dxvk.XXXXXX")"
    fetch "https://github.com/${DXVK_REPO}/releases/download/v${ver}/dxvk-${ver}.tar.gz" "$tmp/dxvk.tar.gz" \
        || { err "Falha ao baixar o DXVK"; rm -rf "$tmp"; return 1; }
    tar -xzf "$tmp/dxvk.tar.gz" -C "$tmp" || { err "Falha ao extrair o DXVK"; rm -rf "$tmp"; return 1; }
    src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    if [ -z "$src" ] || [ ! -d "$src/x64" ]; then
        err "Pacote do DXVK em formato inesperado"; rm -rf "$tmp"; return 1
    fi

    rm -rf "$DXVK_DIR"; mkdir -p "$DXVK_DIR/x64" "$DXVK_DIR/x32"
    cp -f "$src"/x64/*.dll "$DXVK_DIR/x64/"
    if [ -d "$src/x32" ]; then cp -f "$src"/x32/*.dll "$DXVK_DIR/x32/"; fi
    printf '%s\n' "$ver" > "$DXVK_DIR/VERSION"
    rm -rf "$tmp"
    ok "DXVK $ver instalado"
}

install_vkd3d() {
    if [ "$ENABLE_VKD3D" != "1" ]; then log "VKD3D desativado"; return 0; fi
    if vkd3d_installed; then return 0; fi

    local api
    api="$(vulkan_api)"
    if [ -n "$api" ] && ! version_ge "$api" "1.3"; then
        warn "Direct3D 12 (VKD3D-Proton) exige Vulkan 1.3; sua GPU expõe $api. Pulando."
        return 0
    fi
    if ! have zstd; then
        warn "Para o suporte a Direct3D 12 instale o 'zstd' (ex.: sudo apt install zstd) e use Reinstalar."
        return 0
    fi

    mkdir -p "$DOWNLOAD_DIR"
    local ver tmp src
    ver="$(resolve_version "$VKD3D_REPO" "$VKD3D_VERSION" "$FALLBACK_VKD3D")"
    log "Baixando VKD3D-Proton $ver (Direct3D 12 → Vulkan)..."
    tmp="$(mktemp -d "$DOWNLOAD_DIR/vkd3d.XXXXXX")"
    fetch "https://github.com/${VKD3D_REPO}/releases/download/v${ver}/vkd3d-proton-${ver}.tar.zst" "$tmp/vkd3d.tar.zst" \
        || { err "Falha ao baixar o VKD3D-Proton"; rm -rf "$tmp"; return 1; }
    zstd -dc "$tmp/vkd3d.tar.zst" | tar -xf - -C "$tmp" \
        || { err "Falha ao extrair o VKD3D-Proton"; rm -rf "$tmp"; return 1; }
    src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    if [ -z "$src" ] || [ ! -d "$src/x64" ]; then
        err "Pacote do VKD3D-Proton em formato inesperado"; rm -rf "$tmp"; return 1
    fi

    rm -rf "$VKD3D_DIR"; mkdir -p "$VKD3D_DIR/x64" "$VKD3D_DIR/x32"
    cp -f "$src"/x64/*.dll "$VKD3D_DIR/x64/"
    if [ -d "$src/x86" ]; then cp -f "$src"/x86/*.dll "$VKD3D_DIR/x32/"; fi   # o VKD3D chama de x86
    printf '%s\n' "$ver" > "$VKD3D_DIR/VERSION"
    rm -rf "$tmp"
    ok "VKD3D-Proton $ver instalado"
}

# ─────────────────────────────────── Prefixo ─────────────────────────────────
wine_quiet() { if [ "$DEBUG_MODE" -eq 1 ]; then "$@"; else "$@" >/dev/null 2>&1; fi; }

init_prefix() {
    if prefix_ready; then return 0; fi
    mkdir -p "$PREFIX_DIR"
    log "Criando o prefixo do Wine (só na primeira vez, pode demorar)..."
    # mscoree/mshtml desativados só aqui, para o Wine não pedir Mono/Gecko durante a criação.
    wine_quiet env WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 WINEDLLOVERRIDES="mscoree,mshtml=" \
        WINEDEBUG=-all "$WINE_DIR/bin/wine" wineboot -u || true
    wine_quiet env WINEPREFIX="$PREFIX_DIR" "$WINE_DIR/bin/wineserver" -w || true
    prefix_ready || { err "Não consegui criar o prefixo do Wine."; return 1; }
}

# Copia as DLLs do DXVK/VKD3D para o prefixo e registra os overrides necessários.
setup_prefix() {
    init_prefix || return 1
    local sys64="$PREFIX_DIR/drive_c/windows/system32"
    local sys32="$PREFIX_DIR/drive_c/windows/syswow64"
    local f name
    local -a dlls=()
    mkdir -p "$sys64" "$sys32"

    local d
    for d in "$DXVK_DIR" "$VKD3D_DIR"; do
        [ -d "$d/x64" ] || continue
        for f in "$d"/x64/*.dll; do
            [ -e "$f" ] || continue
            cp -f "$f" "$sys64/"
            dlls+=("$(basename "$f" .dll)")
        done
        for f in "$d"/x32/*.dll; do
            [ -e "$f" ] || continue
            cp -f "$f" "$sys32/"
        done
    done

    # Sem os overrides o Wine continuaria usando o WineD3D (OpenGL) em vez do DXVK.
    # "native,builtin" cai para o WineD3D se o Vulkan falhar, em vez de quebrar o jogo.
    {
        printf 'Windows Registry Editor Version 5.00\r\n\r\n'
        printf '[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\r\n'
        for name in "${dlls[@]+"${dlls[@]}"}"; do
            printf '"%s"="native,builtin"\r\n' "$name"
        done
        printf '"winemenubuilder.exe"=""\r\n\r\n'      # não cria atalhos no seu menu
        printf '[HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver]\r\n'
        printf '"GrabFullscreen"="Y"\r\n'               # mouse não escapa em jogos FPS (Source)
    } > "$BASE_DIR/startx.reg"

    wine_quiet bash -c 'cd "$1" && exec env WINEPREFIX="$2" WINEDEBUG=-all "$3" regedit /S startx.reg' \
        _ "$BASE_DIR" "$PREFIX_DIR" "$WINE_DIR/bin/wine" \
        || warn "Não consegui gravar as configurações no registro do Wine."
    wine_quiet env WINEPREFIX="$PREFIX_DIR" "$WINE_DIR/bin/wineserver" -w || true
    return 0
}

install_all() {
    check_arch
    install_wine || return 1
    check_wine_libs
    install_dxvk  || warn "DXVK não foi instalado; jogos Direct3D usarão o renderizador padrão do Wine (mais lento)."
    install_vkd3d || warn "VKD3D-Proton não foi instalado; jogos Direct3D 12 não vão funcionar."
    setup_prefix  || return 1
    ok "StartX pronto!"
}

ensure_ready() {
    if is_ready; then return 0; fi
    install_all
}

# ──────────────────────── Detecção de engine e executáveis ───────────────────
# Imprime: unity | source | source2 | goldsrc | (vazio)
detect_engine() {
    local exe="$1" dir stem
    dir="$(dirname -- "$exe")"
    stem="$(basename -- "$exe")"; stem="${stem%.*}"

    if [ -f "$dir/UnityPlayer.dll" ] \
       || [ -n "$(find "$dir" -maxdepth 1 -type d -iname "${stem}_Data" -print -quit 2>/dev/null)" ]; then
        echo unity; return 0
    fi
    if [ -f "$dir/engine2.dll" ]; then
        echo source2; return 0
    fi
    if [ -f "$dir/bin/engine.dll" ] || [ -f "$dir/bin/tier0.dll" ] \
       || [ -f "$dir/bin/x64/tier0.dll" ] || [ -f "$dir/bin/win64/tier0.dll" ]; then
        echo source; return 0
    fi
    if [ -f "$dir/hw.dll" ] || [ -f "$dir/sw.dll" ]; then
        echo goldsrc; return 0
    fi
    echo ""
}

engine_label() {
    case "$1" in
        unity)   echo "Unity" ;;
        source)  echo "Source" ;;
        source2) echo "Source 2" ;;
        goldsrc) echo "GoldSrc" ;;
        *)       echo "" ;;
    esac
}

# Imprime 64 ou 32 lendo o cabeçalho PE do .exe (sem depender do comando 'file').
exe_arch() {
    local exe="$1" off machine
    off="$(od -An -tu4 -j60 -N4 "$exe" 2>/dev/null | tr -d ' \n')"
    [[ "$off" =~ ^[0-9]+$ ]] || return 1
    machine="$(od -An -tx2 -j$((off + 4)) -N2 "$exe" 2>/dev/null | tr -d ' \n')"
    case "$machine" in
        8664|aa64) echo 64 ;;
        014c)      echo 32 ;;
        *)         return 1 ;;
    esac
}

# Executáveis que não são jogos (instaladores, crash handlers, ferramentas do SDK...).
is_noise_exe() {
    local lower="${1,,}" b
    case "$lower" in
        */portable-wine/*|*/drive_c/windows/*|*/_commonredist/*|*/redist/*|*/redistributable*/*|*/directx/*|*/vcredist*/*) return 0 ;;
    esac
    b="${lower##*/}"
    case "$b" in
        unins*.exe|vc_redist*|vcredist*|dxsetup*|dxwebsetup*|dotnetfx*|ndp*|oalinst*|physx*) return 0 ;;
        unitycrashhandler*|crashpad_handler*|crashreport*|crashsender*|crashhandler*|bssndrpt*|werfault*) return 0 ;;
        steamerrorreporter*|steamservice*|steamwebhelper*|unrealcefsubprocess*|qtwebengineprocess*) return 0 ;;
        vbsp.exe|vvis.exe|vrad.exe|studiomdl.exe|bspzip.exe|hammer*|hlmv.exe|faceposer.exe|glview.exe) return 0 ;;
        vtex.exe|vtf2tga.exe|vpk.exe|height2normal.exe|motionmapper.exe|captioncompiler.exe) return 0 ;;
        shadercompile.exe|vmpi_*|elementviewer.exe|dmxconvert.exe|resourcecompiler.exe|vconsole2.exe) return 0 ;;
    esac
    return 1
}

list_games() {
    local dir="$1" f
    [ -d "$dir" ] || return 1
    while IFS= read -r -d '' f; do
        if is_noise_exe "$f"; then continue; fi
        printf '%s\n' "$f"
    done < <(find "$dir" \( -name portable-wine -o -name drive_c \) -prune -o \
                  -maxdepth 6 -type f -iname '*.exe' -print0 2>/dev/null)
    return 0
}

# Preenche GAME_PATHS / GAME_TAGS (jogos de engines conhecidas primeiro).
build_game_list() {
    local dir="$1" rank path tag f
    GAME_PATHS=(); GAME_TAGS=()
    dir="$(cd -- "$dir" 2>/dev/null && pwd)" || return 0
    while IFS=$'\t' read -r rank path tag; do
        [ -n "$path" ] || continue
        GAME_PATHS+=("$path"); GAME_TAGS+=("$tag")
    done < <(
        while IFS= read -r f; do
            tag="$(engine_label "$(detect_engine "$f")")"
            rank=1; if [ -n "$tag" ]; then rank=0; fi
            printf '%s\t%s\t%s\n' "$rank" "$f" "$tag"
        done < <(list_games "$dir") | sort -t$'\t' -k1,1 -k2,2
    )
    return 0
}

# ─────────────────────────────── Ambiente do Wine ────────────────────────────
# Preenche WENV com tudo que o Wine/DXVK/VKD3D precisam. $1 = pasta do jogo (opcional).
make_env() {
    local gamedir="${1:-}" overrides=""
    mkdir -p "$CACHE_DIR/dxvk" "$CACHE_DIR/vkd3d"

    # Mod loaders (BepInEx/MelonLoader no Unity, ASI loaders etc.) usam DLLs "proxy"
    # ao lado do .exe; o Wine só as carrega se o override estiver ligado.
    if [ -n "$gamedir" ]; then
        local d
        for d in winhttp version dinput8 dsound xinput1_3 xinput1_4 xinput9_1_0; do
            if [ -n "$(find "$gamedir" -maxdepth 1 -iname "$d.dll" -print -quit 2>/dev/null)" ]; then
                overrides+="${overrides:+;}$d=n,b"
            fi
        done
    fi

    WENV=(
        "WINEPREFIX=$PREFIX_DIR"
        "WINEARCH=win64"
        "PATH=$WINE_DIR/bin:$PATH"
        "DXVK_STATE_CACHE_PATH=$CACHE_DIR/dxvk"
        "VKD3D_SHADER_CACHE_PATH=$CACHE_DIR/vkd3d"
        "WINEESYNC=1"
        "WINEFSYNC=1"
        "WINE_LARGE_ADDRESS_AWARE=1"
        "PULSE_LATENCY_MSEC=60"
        "mesa_glthread=true"
        "__GL_THREADED_OPTIMIZATIONS=1"
    )
    if [ -n "$overrides" ]; then WENV+=("WINEDLLOVERRIDES=$overrides"); fi
    if [ "$DEBUG_MODE" -eq 1 ]; then
        WENV+=("DXVK_LOG_LEVEL=info")
    else
        WENV+=("WINEDEBUG=-all" "DXVK_LOG_LEVEL=none")
    fi
    if [ -n "${STARTX_HUD:-}" ]; then WENV+=("DXVK_HUD=$STARTX_HUD"); fi
    return 0
}

run_wine() { env "${WENV[@]}" "$WINE_DIR/bin/wine" "$@"; }

stop_wine() {
    if [ -x "$WINE_DIR/bin/wineserver" ] && [ -d "$PREFIX_DIR" ]; then
        WINEPREFIX="$PREFIX_DIR" "$WINE_DIR/bin/wineserver" -k 2>/dev/null || true
    fi
    return 0
}

engine_hint() {
    case "$1" in
        unity)   echo "Unity: tente  ./startx.sh jogo.exe -force-d3d11   (ou -force-vulkan / -force-glcore / -force-d3d12)" ;;
        source)  echo "Source: tente  ./startx.sh jogo.exe -dxlevel 95   (ou -sw para modo janela, -nojoy sem controle)" ;;
        source2) echo "Source 2: tente  ./startx.sh jogo.exe -dx11   (ou -vulkan)" ;;
        goldsrc) echo "GoldSrc: tente  ./startx.sh jogo.exe -gl   (ou -soft)" ;;
        *)       echo "Rode com --debug para ver o que está acontecendo." ;;
    esac
}

# run_exe <arquivo.exe> [argumentos do jogo...]
run_exe() {
    local exe="$1"; shift
    if [ ! -f "$exe" ]; then err "Arquivo não encontrado: $exe"; return 1; fi

    local dir base engine label arch bits="" started rc=0
    dir="$(cd -- "$(dirname -- "$exe")" && pwd)"
    base="$(basename -- "$exe")"
    engine="$(detect_engine "$dir/$base")"
    label="$(engine_label "$engine")"
    arch="$(exe_arch "$dir/$base" || true)"
    if [ -n "$arch" ]; then bits="${arch}-bit"; fi

    local info="${label:+$label}${label:+${bits:+ · }}${bits}"
    log "Rodando: $base${info:+  ($info)}"

    if [ "$arch" = "32" ] && dxvk_installed && [ ! -f "$DXVK_DIR/x32/dxgi.dll" ]; then
        warn "Jogo de 32 bits, mas o DXVK de 32 bits não está instalado. Use Reinstalar."
    fi

    # Argumentos: os da linha de comando têm prioridade sobre STARTX_ARGS.
    local -a gargs=("$@")
    if [ "${#gargs[@]}" -eq 0 ] && [ -n "${STARTX_ARGS:-}" ]; then
        read -r -a gargs <<< "$STARTX_ARGS"
    fi

    make_env "$dir"
    local -a launch=("$WINE_DIR/bin/wine")
    if [[ "${STARTX_VDESKTOP:-}" =~ ^[0-9]+x[0-9]+$ ]]; then
        launch+=(explorer "/desktop=StartX,$STARTX_VDESKTOP")
    fi

    started=$SECONDS
    (
        cd "$dir" || exit 1
        ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true     # o esync precisa de muitos descritores
        exec env "${WENV[@]}" "${launch[@]}" "$base" "${gargs[@]+"${gargs[@]}"}"
    ) || rc=$?

    # Fechou rápido e com erro? Provavelmente não abriu: dá uma dica.
    if [ "$rc" -ne 0 ] && [ $((SECONDS - started)) -lt 15 ]; then
        warn "O jogo fechou logo após abrir (código $rc)."
        printf '  %s%s%s\n' "$C_DIM" "$(engine_hint "$engine")" "$C_RESET" >&2
        return 1
    fi
    return 0
}

# ─────────────────────────── Reinstalar / Desinstalar ────────────────────────
guard_base() {
    if [ "$(basename -- "$BASE_DIR")" != "portable-wine" ] || [ -z "$BASE_DIR" ] || [ "$BASE_DIR" = "/" ]; then
        err "Caminho de instalação suspeito ($BASE_DIR); não vou apagar nada."
        return 1
    fi
}

do_reinstall() {
    guard_base || return 1
    local keep=1
    if [ "$CLEAN_PREFIX" -eq 1 ]; then keep=0; fi

    confirm "Reinstalar Wine, DXVK e VKD3D do zero?" n || { log "Cancelado."; return 0; }
    if [ "$keep" -eq 1 ] && prefix_ready && [ "$ASSUME_YES" -ne 1 ] && [ -t 0 ]; then
        confirm "Manter os saves e configurações dos jogos (prefixo)?" s || keep=0
    fi

    stop_wine
    log "Removendo componentes antigos..."
    rm -rf -- "$WINE_DIR" "$DXVK_DIR" "$VKD3D_DIR" "$DOWNLOAD_DIR"
    if [ "$keep" -eq 0 ]; then
        rm -rf -- "$PREFIX_DIR" "$CACHE_DIR"
        log "Prefixo apagado; será recriado."
    else
        log "Prefixo mantido."
    fi
    install_all
}

do_uninstall() {
    guard_base || return 1
    if [ ! -d "$BASE_DIR" ]; then
        ok "O StartX já está desinstalado (nada em $BASE_DIR)."
        return 0
    fi
    local size
    size="$(du -sh "$BASE_DIR" 2>/dev/null | cut -f1 || true)"
    printf '\n  %sIsto apaga %s (%s):%s Wine, DXVK, VKD3D e o prefixo.\n' "$C_YELLOW" "$BASE_DIR" "${size:-?}" "$C_RESET" >&2
    printf '  Saves que estiverem dentro do prefixo serão perdidos. Seus jogos não são tocados.\n' >&2
    confirm "Desinstalar o StartX?" n || { log "Cancelado."; return 0; }

    stop_wine
    if rm -rf -- "$BASE_DIR"; then
        ok "StartX desinstalado. Rode o script de novo quando quiser reinstalar."
    else
        err "Falha ao remover: $BASE_DIR"
        return 1
    fi
}

# ───────────────────────────────────── UI ────────────────────────────────────
banner_art() {
    cat <<'ART'
 .d8888b. 888                  888   Y88b   d88P
d88P  Y88b888                  888    Y88b d88P
Y88b.     888                  888     Y88o88P
 "Y888b.  888888 8888b. 888d888888888   Y888P
    "Y88b.888       "88b888P"  888      d888b
      "888888   .d888888888    888     d88888b
Y88b  d88PY88b. 888  888888    Y88b.  d88P Y88b
 "Y8888P"  "Y888"Y888888888     "Y888d88P   Y88b
ART
}

print_banner() {
    local cols line i=0 pal=(51 45 39 33 63 99 135 171)
    cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    printf '\n'
    if [ "$cols" -lt 52 ]; then
        printf '  %sStartX%s\n' "$C_BOLD$C_CYAN" "$C_RESET"
        return 0
    fi
    while IFS= read -r line; do
        if [ "$USE_256" -eq 1 ]; then
            printf '  \033[1;38;5;%dm%s\033[0m\n' "${pal[$((i % ${#pal[@]}))]}" "$line"
        else
            printf '  %s%s%s\n' "$C_BOLD$C_CYAN" "$line" "$C_RESET"
        fi
        i=$((i + 1))
    done < <(banner_art)
    return 0
}

status_line() {
    if ! wine_installed; then
        printf '  %s○ Não instalado%s  %s— escolha Jogar ou Reinstalar para instalar%s\n' \
            "$C_YELLOW" "$C_RESET" "$C_DIM" "$C_RESET"
        return 0
    fi
    local wv dv kv
    wv="$("$WINE_DIR/bin/wine" --version 2>/dev/null | sed 's/^wine-//' || true)"
    dv="$(comp_version "$DXVK_DIR")";  kv="$(comp_version "$VKD3D_DIR")"
    printf '  %s●%s Wine %s  %s·%s  DXVK %s  %s·%s  VKD3D %s\n' \
        "$C_GREEN" "$C_RESET" "${wv:-?}" "$C_DIM" "$C_RESET" "${dv:-—}" "$C_DIM" "$C_RESET" "${kv:-—}"
    return 0
}

draw_screen() {
    if [ -t 1 ]; then printf '\033[H\033[2J'; fi
    print_banner
    printf '\n  %sJogos Windows no Linux  ·  Source & Unity%s\n\n' "$C_DIM" "$C_RESET"
    status_line
    printf '\n'
    printf '    %s[1]%s  Jogar\n'       "$C_BOLD$C_CYAN" "$C_RESET"
    printf '    %s[2]%s  Reinstalar\n'  "$C_BOLD$C_CYAN" "$C_RESET"
    printf '    %s[3]%s  Desinstalar\n' "$C_BOLD$C_CYAN" "$C_RESET"
    printf '    %s[0]%s  Sair\n'        "$C_BOLD$C_CYAN" "$C_RESET"
    printf '\n'
    return 0
}

# Lista jogos de uma pasta e deixa a pessoa escolher (número ou caminho colado).
pick_game() {
    local dir i choice rel dirabs
    dir="$(cd -- "$1" && pwd)"
    while true; do
        build_game_list "$dir"
        dirabs="$dir"
        printf '\n  %sJogos em%s %s\n\n' "$C_BOLD" "$C_RESET" "$dir"
        if [ "${#GAME_PATHS[@]}" -eq 0 ]; then
            printf '  %sNenhum .exe encontrado aqui.%s\n' "$C_YELLOW" "$C_RESET"
        else
            for i in "${!GAME_PATHS[@]}"; do
                rel="${GAME_PATHS[$i]#"$dirabs"/}"
                printf '   %s[%2d]%s %s%-10s%s %s\n' "$C_BOLD$C_CYAN" "$((i + 1))" "$C_RESET" \
                    "$C_DIM" "${GAME_TAGS[$i]:+[${GAME_TAGS[$i]}]}" "$C_RESET" "$rel"
            done
        fi
        printf '\n  Número, ou cole o caminho de um .exe ou pasta (Enter volta): '
        read -r choice || return 0
        # limpa aspas, espaços escapados e ~ (arrastar arquivo para o terminal)
        choice="${choice#"${choice%%[![:space:]]*}"}"; choice="${choice%"${choice##*[![:space:]]}"}"
        choice="${choice#[\'\"]}"; choice="${choice%[\'\"]}"; choice="${choice//\\ / }"
        if [[ "$choice" == "~"* ]]; then choice="$HOME${choice#\~}"; fi

        if [ -z "$choice" ]; then return 0; fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#GAME_PATHS[@]}" ]; then
            run_exe "${GAME_PATHS[$((choice - 1))]}" || pause
            return 0
        elif [ -f "$choice" ]; then
            run_exe "$choice" || pause
            return 0
        elif [ -d "$choice" ]; then
            dir="$(cd -- "$choice" && pwd)"
        else
            warn "Opção inválida: $choice"
        fi
    done
}

menu_play() {
    if ! is_ready; then
        install_all || { pause; return 0; }
    fi
    pick_game "$PWD"
}

menu_reinstall() { do_reinstall || true; pause; }
menu_uninstall() { do_uninstall || true; pause; }

main_menu() {
    local choice
    while true; do
        draw_screen
        printf '  Escolha: '
        read -r choice || { echo; break; }
        case "${choice,,}" in
            1|j) menu_play || true ;;
            2|r) menu_reinstall ;;
            3|d) menu_uninstall ;;
            0|q|s) break ;;
            *) ;;
        esac
    done
    printf '\n'
}

print_status() {
    print_banner
    printf '  Diretório: %s\n\n' "$BASE_DIR"
    if wine_installed; then
        printf '  Wine:    %s\n' "$("$WINE_DIR/bin/wine" --version 2>/dev/null | sed 's/^wine-//' || echo '?')"
    else
        printf '  Wine:    não instalado\n'
    fi
    if dxvk_installed;  then printf '  DXVK:    %s\n' "$(comp_version "$DXVK_DIR")";  else printf '  DXVK:    não instalado\n'; fi
    if vkd3d_installed; then printf '  VKD3D:   %s\n' "$(comp_version "$VKD3D_DIR")"; else printf '  VKD3D:   não instalado\n'; fi
    if prefix_ready;    then printf '  Prefixo: criado\n'; else printf '  Prefixo: não criado\n'; fi
    local api
    api="$(vulkan_api)"
    printf '  Vulkan:  %s\n' "${api:-não detectado (instale vulkan-tools para ver)}"
    if [ -d "$BASE_DIR" ]; then printf '  Espaço:  %s\n' "$(du -sh "$BASE_DIR" 2>/dev/null | cut -f1)"; fi
    if wine_installed; then check_wine_libs; fi
    return 0
}

print_help() {
    cat <<'EOF'
StartX — jogos Windows no Linux (Wine + DXVK + VKD3D-Proton)
Compatível com jogos Source (Source 1, Source 2, GoldSrc) e Unity.

USO:
  ./startx.sh                        Abre o menu (Jogar / Reinstalar / Desinstalar)
  ./startx.sh jogo.exe [args]        Roda o jogo direto (args vão para o jogo)
  ./startx.sh <pasta>                Lista os jogos da pasta
  ./startx.sh --lista [pasta]        Só lista os jogos (sem instalar nada)
  ./startx.sh --instalar             Instala tudo (Wine + DXVK + VKD3D)
  ./startx.sh --reinstalar           Reinstala mantendo saves (--limpo apaga o prefixo)
  ./startx.sh --desinstalar          Remove tudo  (--sim pula a confirmação)
  ./startx.sh --status               Mostra o que está instalado
  ./startx.sh --winecfg              Configurador do Wine
  ./startx.sh --shell                Shell com o Wine configurado
  ./startx.sh --winetricks verbos    Instala extras (vcrun2022, corefonts, dotnet48...)
  ./startx.sh --debug [...]          Logs completos (pode ser usado com qualquer comando)

VARIÁVEIS:
  WINE_VARIANT=staging|vanilla       Tipo de Wine (padrão: staging)
  WINE_VERSION / DXVK_VERSION / VKD3D_VERSION=x.y.z   Fixa uma versão
  ENABLE_DXVK=0 / ENABLE_VKD3D=0     Desliga DXVK / Direct3D 12
  STARTX_ARGS="-windowed"            Argumentos padrão para o jogo
  STARTX_VDESKTOP=1280x720           Roda em janela virtual (útil se o fullscreen der problema)
  STARTX_HUD=fps                     Mostra FPS do DXVK (ou "full")

DICAS DE ARGUMENTOS (passe depois do .exe):
  Unity      -force-d3d11 | -force-vulkan | -force-glcore | -force-d3d12 | -popupwindow
  Source     -dxlevel 95 | -sw (janela) | -novid | -nojoy
  Source 2   -dx11 | -vulkan

Tudo fica em ./portable-wine/ — nada é instalado no resto do sistema.
EOF
}

# ──────────────────────────────────── Principal ──────────────────────────────
case "${1:-}" in
    --ajuda|--help|-h)
        print_help
        ;;
    --instalar|--install|--graficos|--graphics)
        install_all
        ;;
    --reinstalar|--reinstall)
        do_reinstall
        ;;
    --desinstalar|--uninstall|--remover)
        do_uninstall
        ;;
    --status)
        print_status
        ;;
    --winecfg)
        ensure_ready
        make_env
        run_wine winecfg
        ;;
    --shell)
        ensure_ready
        make_env
        log "Shell com Wine (rode 'wine prog.exe' ou 'exit')"
        for kv in "${WENV[@]}"; do export "${kv?}"; done
        exec "${SHELL:-bash}"
        ;;
    --winetricks)
        shift
        if [ "$#" -eq 0 ]; then err "Informe o que instalar, ex.: ./startx.sh --winetricks vcrun2022 corefonts"; exit 1; fi
        ensure_ready
        make_env
        if [ ! -x "$BASE_DIR/winetricks" ]; then
            log "Baixando winetricks..."
            fetch "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" "$BASE_DIR/winetricks" \
                || { err "Falha ao baixar o winetricks"; exit 1; }
            chmod +x "$BASE_DIR/winetricks"
        fi
        env "${WENV[@]}" WINE="$WINE_DIR/bin/wine" WINESERVER="$WINE_DIR/bin/wineserver" \
            WINETRICKS_LATEST_VERSION_CHECK=disabled "$BASE_DIR/winetricks" "$@"
        ;;
    --lista|--list)
        build_game_list "${2:-.}"
        for i in "${!GAME_PATHS[@]}"; do
            printf '%-10s %s\n' "${GAME_TAGS[$i]:+[${GAME_TAGS[$i]}]}" "${GAME_PATHS[$i]}"
        done
        ;;
    "")
        main_menu
        ;;
    *)
        if [ -f "$1" ]; then
            ensure_ready
            exe="$1"; shift
            run_exe "$exe" "$@"
        elif [ -d "$1" ]; then
            ensure_ready
            pick_game "$1"
        else
            err "Argumento desconhecido: $1"
            print_help
            exit 1
        fi
        ;;
esac
