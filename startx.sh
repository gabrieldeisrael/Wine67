#!/usr/bin/env bash
set -euo pipefail

# Verifica se o usuário passou a flag --debug (em qualquer posição) e a
# remove da lista de argumentos, para não atrapalhar o resto do parsing.
DEBUG_MODE=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--debug" ]; then
        DEBUG_MODE=1
    else
        ARGS+=("$arg")
    fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if [ "$DEBUG_MODE" -eq 1 ]; then
    # Desativa o -e e o -u
    set +eu
    # Desativa o pipefail
    set +o pipefail
    # Ativa o modo de depuração (-x)
    set -x
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BASE_DIR="$SCRIPT_DIR/portable-wine"
WINE_DIR="$BASE_DIR/wine"
PREFIX_DIR="$BASE_DIR/prefix"
DOWNLOAD_DIR="$BASE_DIR/download"
DXVK_DIR="$BASE_DIR/dxvk"
VKD3D_DIR="$BASE_DIR/vkd3d"

WINE_VARIANT="${WINE_VARIANT:-staging}"
ENABLE_DXVK="${ENABLE_DXVK:-1}"
ENABLE_VKD3D="${ENABLE_VKD3D:-1}"
DXVK_VERSION="${DXVK_VERSION:-latest}"

REPO="Kron4ek/Wine-Builds"
API_LATEST="https://api.github.com/repos/${REPO}/releases/latest"
DXVK_REPO="doitsujin/dxvk"
DXVK_API_LATEST="https://api.github.com/repos/${DXVK_REPO}/releases/latest"
VKD3D_REPO="lutris/vkd3d"
VKD3D_API_LATEST="https://api.github.com/repos/${VKD3D_REPO}/releases/latest"

FALLBACK_VERSION="11.15"
FALLBACK_DXVK="2.8"
FALLBACK_VKD3D="1.10"

log()  { printf '\n==> %s\n' "$1" >&2; }
err()  { printf 'Erro: %s\n' "$1" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
warn() { printf '⚠ Aviso: %s\n' "$1" >&2; }

fetch() {
  local url="$1" dest="$2"
  if have curl; then
    curl -fL --progress-bar -o "$dest" "$url" || return 1
  elif have wget; then
    wget -q --show-progress -O "$dest" "$url" || return 1
  else
    err "Preciso de 'curl' ou 'wget' para baixar, e não achei nenhum dos dois."
    return 1
  fi
}

fetch_stdout() {
  local url="$1"
  if have curl; then
    curl -fsSL "$url" 2>/dev/null || true
  elif have wget; then
    wget -qO- "$url" 2>/dev/null || true
  fi
}

wine_installed() { [ -x "$WINE_DIR/bin/wine" ]; }
dxvk_installed() { [ -d "$DXVK_DIR/x64" ] && [ -f "$DXVK_DIR/x64/d3d11.dll" ]; }
vkd3d_installed() { [ -d "$VKD3D_DIR/x64" ] && [ -f "$VKD3D_DIR/x64/d3d12.dll" ]; }

check_arch() {
  local m
  m="$(uname -m)"
  if [ "$m" != "x86_64" ]; then
    err "Este script foi feito para máquinas x86_64 (encontrei: $m)."
    exit 1
  fi
}

check_vulkan() {
  if ! have vulkaninfo; then
    warn "vulkaninfo não encontrado! Instale drivers Vulkan:"
    warn "  Intel: sudo apt install vulkan-tools libvulkan1"
    warn "  NVIDIA: sudo apt install vulkan-tools libvulkan1"
    warn "  AMD: sudo apt install vulkan-tools libvulkan1 mesa-vulkan-drivers"
    return 1
  fi
  return 0
}

variant_regex() {
  if [ "$WINE_VARIANT" = "staging" ]; then
    printf 'wine-[0-9.]+-staging-amd64-wow64\.tar\.xz'
  else
    printf 'wine-[0-9.]+-amd64-wow64\.tar\.xz'
  fi
}

get_download_url() {
  local pattern json url=""
  pattern="$(variant_regex)"

  json="$(fetch_stdout "$API_LATEST")"
  if [ -n "$json" ]; then
    url="$(printf '%s' "$json" | grep -oE '"browser_download_url": *"[^"]+"' | grep -E "$pattern" | sed -E 's/.*"(https:[^"]+)".*/\1/' | head -n1 || true)"
  fi

  if [ -z "$url" ]; then
    local suffix="amd64-wow64.tar.xz"
    [ "$WINE_VARIANT" = "staging" ] && suffix="staging-amd64-wow64.tar.xz"
    url="https://github.com/${REPO}/releases/download/${FALLBACK_VERSION}/wine-${FALLBACK_VERSION}-${suffix}"
    log "Usando fallback Wine: $FALLBACK_VERSION"
  fi

  printf '%s' "$url"
}

get_dxvk_download_url() {
  local json url=""
  json="$(fetch_stdout "$DXVK_API_LATEST")"
  if [ -n "$json" ]; then
    url="$(printf '%s' "$json" | grep -oE '"browser_download_url": *"[^"]+"' | grep -E 'dxvk-[0-9.]+\.tar\.gz' | sed -E 's/.*"(https:[^"]+)".*/\1/' | head -n1 || true)"
  fi

  if [ -z "$url" ]; then
    url="https://github.com/${DXVK_REPO}/releases/download/v${FALLBACK_DXVK}/dxvk-${FALLBACK_DXVK}.tar.gz"
    log "Usando fallback DXVK: $FALLBACK_DXVK"
  fi

  printf '%s' "$url"
}

get_vkd3d_download_url() {
  local json url=""
  json="$(fetch_stdout "$VKD3D_API_LATEST")"
  if [ -n "$json" ]; then
    url="$(printf '%s' "$json" | grep -oE '"browser_download_url": *"[^"]+"' | grep -E 'vkd3d-[0-9.]+\.tar\.gz' | sed -E 's/.*"(https:[^"]+)".*/\1/' | head -n1 || true)"
  fi

  if [ -z "$url" ]; then
    url="https://github.com/${VKD3D_REPO}/releases/download/v${FALLBACK_VKD3D}/vkd3d-${FALLBACK_VKD3D}.tar.gz"
    log "Usando fallback VKD3D: $FALLBACK_VKD3D"
  fi

  printf '%s' "$url"
}

install_dxvk() {
  if [ "$ENABLE_DXVK" != "1" ]; then
    log "DXVK desabilitado"
    return 0
  fi

  if dxvk_installed; then
    log "DXVK já instalado"
    return 0
  fi

  check_vulkan || return 1

  log "Instalando DXVK (D3D9/D3D10/D3D11 → Vulkan)..."
  local url filename dest extracted_dir
  url="$(get_dxvk_download_url)"
  filename="$(basename "$url")"
  dest="$DOWNLOAD_DIR/$filename"

  fetch "$url" "$dest" || { err "Falha ao baixar DXVK"; return 1; }

  mkdir -p "$DXVK_DIR/x64" "$DXVK_DIR/x32"
  tar -xzf "$dest" -C "$DOWNLOAD_DIR" || { err "Falha ao extrair DXVK"; return 1; }
  
  extracted_dir="$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d \( -name 'dxvk-*' -o -name 'dxvk' \) | head -n1)"
  if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir" ]; then
    err "Diretório DXVK extraído não encontrado"
    return 1
  fi

  [ -d "$extracted_dir/x64" ] && cp -r "$extracted_dir/x64"/* "$DXVK_DIR/x64/" 2>/dev/null || true
  [ -d "$extracted_dir/x32" ] && cp -r "$extracted_dir/x32"/* "$DXVK_DIR/x32/" 2>/dev/null || true
  [ -d "$extracted_dir/x86_64-w64-mingw32" ] && cp -r "$extracted_dir/x86_64-w64-mingw32"/* "$DXVK_DIR/x64/" 2>/dev/null || true
  [ -d "$extracted_dir/i686-w64-mingw32" ] && cp -r "$extracted_dir/i686-w64-mingw32"/* "$DXVK_DIR/x32/" 2>/dev/null || true
  
  rm -rf "$extracted_dir" "$dest"
  log "DXVK instalado!"
}

install_vkd3d() {
  if [ "$ENABLE_VKD3D" != "1" ]; then
    log "VKD3D desabilitado"
    return 0
  fi

  if vkd3d_installed; then
    log "VKD3D já instalado"
    return 0
  fi

  check_vulkan || return 1

  log "Instalando VKD3D (D3D12 → Vulkan)..."
  local url filename dest extracted_dir
  url="$(get_vkd3d_download_url)"
  filename="$(basename "$url")"
  dest="$DOWNLOAD_DIR/$filename"

  fetch "$url" "$dest" || { err "Falha ao baixar VKD3D"; return 1; }

  mkdir -p "$VKD3D_DIR/x64" "$VKD3D_DIR/x32"
  tar -xzf "$dest" -C "$DOWNLOAD_DIR" || { err "Falha ao extrair VKD3D"; return 1; }
  
  extracted_dir="$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d \( -name 'vkd3d-*' -o -name 'vkd3d' \) | head -n1)"
  if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir" ]; then
    err "Diretório VKD3D extraído não encontrado"
    return 1
  fi

  [ -d "$extracted_dir/x64" ] && cp -r "$extracted_dir/x64"/* "$VKD3D_DIR/x64/" 2>/dev/null || true
  [ -d "$extracted_dir/x32" ] && cp -r "$extracted_dir/x32"/* "$VKD3D_DIR/x32/" 2>/dev/null || true
  [ -d "$extracted_dir/x86_64-w64-mingw32" ] && cp -r "$extracted_dir/x86_64-w64-mingw32"/* "$VKD3D_DIR/x64/" 2>/dev/null || true
  [ -d "$extracted_dir/i686-w64-mingw32" ] && cp -r "$extracted_dir/i686-w64-mingw32"/* "$VKD3D_DIR/x32/" 2>/dev/null || true
  
  rm -rf "$extracted_dir" "$dest"
  log "VKD3D instalado!"
}

setup_vulkan_prefix() {
  if [ ! -d "$PREFIX_DIR" ]; then
    return 0
  fi

  log "Configurando renderização Vulkan..."
  
  mkdir -p "$PREFIX_DIR/drive_c/windows/system32" "$PREFIX_DIR/drive_c/windows/syswow64"

  # Instala DXVK DLLs - Override de OpenGL com Vulkan
  if dxvk_installed; then
    log "Instalando DXVK DLLs (D3D11/D3D10/D3D9)..."
    for dll in d3d11 d3d10core d3d10_1 d3d10 d3d9 dxgi; do
      [ -f "$DXVK_DIR/x64/$dll.dll" ] && cp "$DXVK_DIR/x64/$dll.dll" "$PREFIX_DIR/drive_c/windows/system32/" 2>/dev/null || true
      [ -f "$DXVK_DIR/x32/$dll.dll" ] && cp "$DXVK_DIR/x32/$dll.dll" "$PREFIX_DIR/drive_c/windows/syswow64/" 2>/dev/null || true
    done
  fi

  # Instala VKD3D DLLs - D3D12 nativo Vulkan
  if vkd3d_installed; then
    log "Instalando VKD3D DLLs (D3D12)..."
    for dll in d3d12 d3d12core; do
      [ -f "$VKD3D_DIR/x64/$dll.dll" ] && cp "$VKD3D_DIR/x64/$dll.dll" "$PREFIX_DIR/drive_c/windows/system32/" 2>/dev/null || true
      [ -f "$VKD3D_DIR/x32/$dll.dll" ] && cp "$VKD3D_DIR/x32/$dll.dll" "$PREFIX_DIR/drive_c/windows/syswow64/" 2>/dev/null || true
    done
  fi

  # CRÍTICO: Força usar DXVK/VKD3D ao invés de OpenGL
  # Desativa WineD3D/OpenGL completamente
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v CSMT /t REG_SZ /d "enabled" /f 2>/dev/null || true

  # Desativa OpenGL fallback - força Vulkan
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v UseGLSL /t REG_SZ /d "enabled" /f 2>/dev/null || true

  # Melhora sincronização de frame
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v DirectDrawRenderer /t REG_SZ /d "opengl" /f 2>/dev/null || true

  # Desativa query de debug do OpenGL (CAUSA OS ERROS GL_INVALID_OPERATION)
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v LogPixelFormat /t REG_DWORD /d "0" /f 2>/dev/null || true

  # Ativa strict drawable matching
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v StrictDrawableMatching /t REG_SZ /d "enabled" /f 2>/dev/null || true

  # Gerenciamento de memória otimizado
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v VideoMemorySize /t REG_DWORD /d "0" /f 2>/dev/null || true

  # Desativa vsync (melhora FPS)
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v AllowMultisampling /t REG_SZ /d "enabled" /f 2>/dev/null || true

  # Texture filtering
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v TextureMemory /t REG_DWORD /d "2048" /f 2>/dev/null || true

  # DXVK-específico: comportamento D3D12
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v D3D12DeviceType /t REG_SZ /d "discrete" /f 2>/dev/null || true

  log "Renderização Vulkan configurada!"
}

install_wine() {
  check_arch

  if wine_installed; then
    log "Wine já instalado"
    return 0
  fi

  mkdir -p "$BASE_DIR" "$DOWNLOAD_DIR" "$PREFIX_DIR" "$DXVK_DIR/x64" "$DXVK_DIR/x32" "$VKD3D_DIR/x64" "$VKD3D_DIR/x32"

  log "Instalando Wine ($WINE_VARIANT)..."
  local url filename dest
  url="$(get_download_url)"
  filename="$(basename "$url")"
  dest="$DOWNLOAD_DIR/$filename"

  fetch "$url" "$dest" || { err "Falha ao baixar Wine"; return 1; }

  mkdir -p "$WINE_DIR"
  tar -xf "$dest" -C "$WINE_DIR" --strip-components=1 || { err "Falha ao extrair Wine"; return 1; }
  rm -f "$dest"

  if ! wine_installed; then
    err "Wine não foi instalado corretamente"
    return 1
  fi

  log "Wine instalado! $("$WINE_DIR/bin/wine" --version)"
}

find_exes() {
  local dir="${1:-.}"
  local res=() file

  if [ ! -d "$dir" ]; then
    return 1
  fi

  while IFS= read -r file; do
    [ -n "$file" ] && res+=("$file")
  done < <(find "$dir" -maxdepth 5 -type f -iname '*.exe' -not -path "*/portable-wine/*" 2>/dev/null || true)

  if [ "${#res[@]}" -gt 0 ]; then
    printf '%s\n' "${res[@]}" | sort -u
  fi
}

run_exe() {
  local exe="$1"
  if [ ! -f "$exe" ]; then
    err "Arquivo não encontrado: $exe"
    return 1
  fi
  local dir base
  dir="$(cd -- "$(dirname -- "$exe")" && pwd)"
  base="$(basename -- "$exe")"

  log "Rodando: $base"
  (
    cd "$dir"
    WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 PATH="$WINE_DIR/bin:$PATH" \
      "$WINE_DIR/bin/wine" "$base"
  )
}

show_menu() {
  local dir="${1:-.}"
  local exes=()
  while IFS= read -r line; do
    [ -n "$line" ] && exes+=("$line")
  done < <(find_exes "$dir")

  if [ "${#exes[@]}" -eq 0 ]; then
    err "Nenhum .exe encontrado em: $(cd "$dir" && pwd)"
    return 1
  fi

  echo "Executáveis encontrados:"
  PS3=$'\nEscolha um número para rodar (Ctrl+C cancela): '
  select exe in "${exes[@]}"; do
    if [ -n "${exe:-}" ]; then
      run_exe "$exe"
      break
    else
      echo "Opção inválida"
    fi
  done
}

print_help() {
  cat <<'EOF'
🎮 startx.sh — Wine + DXVK + VKD3D (Renderização Vulkan Pura)

USO:
  ./startx.sh                           Instala e mostra menu
  ./startx.sh <programa.exe>           Roda programa
  ./startx.sh <pasta>                  Menu da pasta
  ./startx.sh --lista [pasta]          Lista .exe
  ./startx.sh --instalar               Só Wine
  ./startx.sh --graficos               Instala tudo + otimizações
  ./startx.sh --winecfg                Configurador Wine
  ./startx.sh --shell                  Shell Wine
  ./startx.sh --ajuda                  Esta mensagem
  ./startx.sh --remover                Remover o Wine
  ./startx.sh --debug [...]            Roda com 'set -x' e sem -e/-u/pipefail
                                      (pode ser combinado com qualquer comando acima)

VARIANTES:
  WINE_VARIANT=staging ./startx.sh     Wine com patches (RECOMENDADO)
  WINE_VARIANT=vanilla ./startx.sh     Wine puro

RENDERIZAÇÃO VULKAN:
  ENABLE_DXVK=1 ./startx.sh            D3D9/D3D10/D3D11 → Vulkan (padrão)
  ENABLE_VKD3D=1 ./startx.sh           D3D12 → Vulkan (padrão)
  
CORREÇÕES:
  ✓ GL_INVALID_OPERATION (OpenGL) - RESOLVIDO (usa Vulkan)
  ✓ Texturas esticadas - CSMT ativado
  ✓ Sólidos invisíveis - Strict Drawable Matching
  ✓ Lag - Gerenciamento de memória otimizado
  ✓ Query de Debug - Desativada (fonte dos erros)

TUDO EM: ./portable-wine/
EOF
}

case "${1:-}" in
  --ajuda|--help|-h)
    print_help
    ;;
  --instalar|--install)
    install_wine
    log "Wine pronto em: $WINE_DIR"
    ;;
  --graficos|--graphics)
    install_wine
    install_dxvk
    install_vkd3d
    setup_vulkan_prefix
    log "Sistema Vulkan + DXVK + VKD3D pronto!"
    ;;
  --winecfg)
    install_wine
    install_dxvk
    install_vkd3d
    setup_vulkan_prefix
    WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" winecfg
    ;;
  --remover)
    if rm -rf -- "$BASE_DIR"; then
      echo "Removido: $BASE_DIR"
    else
      err "Falha ao remover: $BASE_DIR"
      exit 1
    fi
    log "Wine removido de: $BASE_DIR"
    exit 0
    ;;
  --shell)
    install_wine
    install_dxvk
    install_vkd3d
    setup_vulkan_prefix
    log "Shell com Wine (rode 'wine prog.exe' ou 'exit')"
    export WINEPREFIX="$PREFIX_DIR"
    export WINEARCH=win64
    export PATH="$WINE_DIR/bin:$PATH"
    exec "${SHELL:-bash}"
    ;;
  --lista|--list)
    install_wine
    find_exes "${2:-.}"
    ;;
  "")
    install_wine
    install_dxvk
    install_vkd3d
    setup_vulkan_prefix
    show_menu "."
    ;;
  *)
    install_wine
    install_dxvk
    install_vkd3d
    setup_vulkan_prefix
    if [ -f "$1" ]; then
      run_exe "$1"
    elif [ -d "$1" ]; then
      show_menu "$1"
    else
      err "Argumento desconhecido: $1"
      print_help
      exit 1
    fi
    ;;
esac