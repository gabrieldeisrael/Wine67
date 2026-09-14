#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BASE_DIR="$SCRIPT_DIR/portable-wine"
WINE_DIR="$BASE_DIR/wine"
PREFIX_DIR="$BASE_DIR/prefix"
DOWNLOAD_DIR="$BASE_DIR/download"
DXVK_DIR="$BASE_DIR/dxvk"

WINE_VARIANT="${WINE_VARIANT:-vanilla}"
ENABLE_DXVK="${ENABLE_DXVK:-1}"
DXVK_VERSION="${DXVK_VERSION:-latest}"

REPO="Kron4ek/Wine-Builds"
API_LATEST="https://api.github.com/repos/${REPO}/releases/latest"
DXVK_REPO="doitsujin/dxvk"
DXVK_API_LATEST="https://api.github.com/repos/${DXVK_REPO}/releases/latest"

FALLBACK_VERSION="11.15"
FALLBACK_DXVK="2.6"

log()  { printf '\n==> %s\n' "$1" >&2; }
err()  { printf 'Erro: %s\n' "$1" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  local url="$1" dest="$2"
  if have curl; then
    curl -fL --progress-bar -o "$dest" "$url"
  elif have wget; then
    wget -q --show-progress -O "$dest" "$url"
  else
    err "Preciso de 'curl' ou 'wget' para baixar o Wine, e não achei nenhum dos dois."
    exit 1
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
dxvk_installed() { [ -f "$DXVK_DIR/x64/d3d11.dll" ] && [ -f "$DXVK_DIR/x32/d3d11.dll" ]; }

check_arch() {
  local m
  m="$(uname -m)"
  if [ "$m" != "x86_64" ]; then
    err "Este script foi feito para máquinas x86_64 (encontrei: $m)."
    err "Os builds do Wine usados aqui não cobrem outras arquiteturas."
    exit 1
  fi
}

check_vulkan() {
  if ! have vulkaninfo; then
    log "AVISO: vulkaninfo não encontrado. DXVK pode não funcionar corretamente."
    log "Instale os drivers Vulkan para sua GPU:"
    log "  - Intel: sudo apt install vulkan-tools libvulkan1"
    log "  - NVIDIA: sudo apt install vulkan-tools libvulkan1 nvidia-driver"
    log "  - AMD: sudo apt install vulkan-tools libvulkan1 mesa-vulkan-drivers"
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
    url="$(printf '%s' "$json" \
      | grep -oE '"browser_download_url": *"[^"]+"' \
      | grep -E "$pattern" \
      | sed -E 's/.*"(https:[^"]+)".*/\1/' \
      | head -n1 || true)"
  fi

  if [ -z "$url" ]; then
    local suffix="amd64-wow64.tar.xz"
    [ "$WINE_VARIANT" = "staging" ] && suffix="staging-amd64-wow64.tar.xz"
    url="https://github.com/${REPO}/releases/download/${FALLBACK_VERSION}/wine-${FALLBACK_VERSION}-${suffix}"
    log "Não consegui falar com a API do GitHub (pode ser limite de taxa)."
    log "Usando versão de reserva fixa: $FALLBACK_VERSION"
  fi

  printf '%s' "$url"
}

get_dxvk_download_url() {
  local json url=""
  
  json="$(fetch_stdout "$DXVK_API_LATEST")"
  if [ -n "$json" ]; then
    url="$(printf '%s' "$json" \
      | grep -oE '"browser_download_url": *"[^"]+"' \
      | grep -E 'dxvk-[0-9.]+\.tar\.gz' \
      | sed -E 's/.*"(https:[^"]+)".*/\1/' \
      | head -n1 || true)"
  fi

  if [ -z "$url" ]; then
    url="https://github.com/${DXVK_REPO}/releases/download/v${FALLBACK_DXVK}/dxvk-${FALLBACK_DXVK}.tar.gz"
    log "Não consegui falar com a API do DXVK (pode ser limite de taxa)."
    log "Usando versão de reserva: $FALLBACK_DXVK"
  fi

  printf '%s' "$url"
}

install_dxvk() {
  if [ "$ENABLE_DXVK" != "1" ]; then
    log "DXVK desabilitado (ENABLE_DXVK=0)"
    return 0
  fi

  if dxvk_installed; then
    log "DXVK já instalado em: $DXVK_DIR"
    return 0
  fi

  check_vulkan || true

  log "Procurando a versão mais recente do DXVK..."
  local url filename dest
  url="$(get_dxvk_download_url)"
  filename="$(basename "$url")"
  dest="$DOWNLOAD_DIR/$filename"

  log "Baixando $filename (isso pode levar alguns minutos)"
  fetch "$url" "$dest"

  log "Extraindo DXVK para $DXVK_DIR"
  mkdir -p "$DXVK_DIR/x64" "$DXVK_DIR/x32"
  if ! tar -xzf "$dest" -C "$DOWNLOAD_DIR"; then
    err "Falha ao extrair DXVK. Verifique se o arquivo está corrompido."
    exit 1
  fi

  # Move os arquivos extraídos para o diretório final
  local extracted_dir
  extracted_dir="$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d -name 'dxvk-*' | head -n1)"
  if [ -z "$extracted_dir" ]; then
    err "Não consegui localizar o diretório extraído do DXVK."
    exit 1
  fi

  cp -r "$extracted_dir/x64"/* "$DXVK_DIR/x64/" 2>/dev/null || true
  cp -r "$extracted_dir/x32"/* "$DXVK_DIR/x32/" 2>/dev/null || true
  rm -rf "$extracted_dir" "$dest"

  if ! dxvk_installed; then
    err "A extração terminou mas não encontrei os DLLs do DXVK."
    exit 1
  fi

  log "DXVK instalado com sucesso!"
}

setup_dxvk_prefix() {
  if [ "$ENABLE_DXVK" != "1" ] || ! dxvk_installed; then
    return 0
  fi

  log "Configurando DXVK no prefixo Wine..."

  # Cria diretórios se não existirem
  mkdir -p "$PREFIX_DIR/drive_c/windows/system32" "$PREFIX_DIR/drive_c/windows/syswow64"

  # Copia DLLs de 64-bit
  if [ -d "$DXVK_DIR/x64" ]; then
    for dll in d3d11 dxgi d3d10core d3d9 d3d12 d3d12core dxvk_config; do
      for ext in dll so; do
        if [ -f "$DXVK_DIR/x64/${dll}.${ext}" ]; then
          cp "$DXVK_DIR/x64/${dll}.${ext}" "$PREFIX_DIR/drive_c/windows/system32/" 2>/dev/null || true
        fi
      done
    done
  fi

  # Copia DLLs de 32-bit
  if [ -d "$DXVK_DIR/x32" ]; then
    for dll in d3d11 dxgi d3d10core d3d9 d3d12 d3d12core dxvk_config; do
      for ext in dll so; do
        if [ -f "$DXVK_DIR/x32/${dll}.${ext}" ]; then
          cp "$DXVK_DIR/x32/${dll}.${ext}" "$PREFIX_DIR/drive_c/windows/syswow64/" 2>/dev/null || true
        fi
      done
    done
  fi

  # Configura wine.reg para usar DXVK
  WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" reg add \
    'HKEY_CURRENT_USER\Software\Wine\Direct3D' /v VideoMemorySize /t REG_SZ /d 0 /f 2>/dev/null || true

  log "DXVK configurado no prefixo!"
}

install_wine() {
  check_arch

  if wine_installed; then
    return 0
  fi

  mkdir -p "$BASE_DIR" "$DOWNLOAD_DIR" "$PREFIX_DIR" "$DXVK_DIR/x64" "$DXVK_DIR/x32"

  log "Procurando a versão mais recente do Wine ($WINE_VARIANT, wow64)..."
  local url filename dest
  url="$(get_download_url)"
  filename="$(basename "$url")"
  dest="$DOWNLOAD_DIR/$filename"

  log "Baixando $filename (isso pode levar alguns minutos)"
  fetch "$url" "$dest"

  log "Extraindo para $WINE_DIR"
  mkdir -p "$WINE_DIR"
  if ! tar -xf "$dest" -C "$WINE_DIR" --strip-components=1; then
    err "Falha ao extrair. Verifique se o pacote 'xz-utils' (ou similar) está disponível no sistema."
    exit 1
  fi
  rm -f "$dest"

  if ! wine_installed; then
    err "A extração terminou mas não encontrei $WINE_DIR/bin/wine."
    exit 1
  fi

  log "Instalado! $("$WINE_DIR/bin/wine" --version)"
  log "O prefixo Wine (registro, C:\\ virtual etc.) será criado em: $PREFIX_DIR"
  log "na primeira vez que você rodar um programa."
}

# find_exes estendido: procura no diretório pedido e em pendrives/HDDs externos montados
find_exes() {
  local dir="${1:-.}"
  local mounts=()
  local mp

  # sempre procurar na pasta pedida primeiro
  mounts+=("$dir")

  # pontos comuns onde dispositivos removíveis são montados
  # /run/media/$USER (Linux desktop), /media (Linux), /mnt (Linux), /Volumes (macOS)
  for base in "/run/media/${USER:-$(whoami)}" "/media" "/mnt" "/Volumes"; do
    if [ -d "$base" ]; then
      for mp in "$base"/*; do
        [ -d "$mp" ] && mounts+=("$mp")
      done
    fi
  done

  # se lsblk estiver disponível, use-o para encontrar mountpoints de dispositivos removíveis
  if have lsblk; then
    # formato: RM MOUNTPOINT (RM==1 significa removível)
    while IFS= read -r line; do
      # linha pode ser: "1 /run/media/user/USB" ou "/run/media/user/USB" dependendo da versão
      # extraí apenas o mountpoint final
      mp="$(printf '%s' "$line" | awk '{ for(i=2;i<=NF;i++){ printf "%s%s", $i, (i==NF?ORS:OFS)} }' )"
      [ -n "$mp" ] && mounts+=("$mp")
    done < <(lsblk -rpo 'RM,MOUNTPOINT' 2>/dev/null | awk '$1==1 && $2!="" { $1=""; sub(/^ /,""); print }' || true)
  else
    # fallback: inspeciona /proc/mounts procurando dispositivos em /dev/sd*
    if [ -r /proc/mounts ]; then
      while IFS= read -r line; do
        case "$line" in
          /dev/sd*|/dev/mmcblk*)
            mp="$(printf '%s' "$line" | awk '{print $2}')"
            [ -n "$mp" ] && mounts+=("$mp")
            ;;
        esac
      done < /proc/mounts
    fi
  fi

  # normaliza e remove duplicatas / ignora o BASE_DIR para não vasculhar o portable-wine
  local uniq=() found
  for mp in "${mounts[@]}"; do
    [ -z "$mp" ] && continue
    # resolve simbólicos e remove sufixo
    if [ -d "$mp" ]; then
      mp="$(cd -- "$mp" 2>/dev/null && pwd || echo "$mp")"
    fi
    case "$mp" in
      "$BASE_DIR"*) continue ;; # não descer na pasta do wine portátil
    esac
    found=false
    for u in "${uniq[@]}"; do
      [ "$u" = "$mp" ] && found=true
    done
    $found || uniq+=("$mp")
  done

  # agora busca .exe em cada ponto, com limite de profundidade para não demorar demais
  local res=() file
  for mp in "${uniq[@]}"; do
    [ -d "$mp" ] || continue
    # -maxdepth 5: profundidade limitada; ajustável se precisar vasculhar subpastas muito profundas
    while IFS= read -r file; do
      [ -n "$file" ] && res+=("$file")
    done < <(find "$mp" -maxdepth 5 -type f -iname '*.exe' -not -path "*/portable-wine/*" 2>/dev/null || true)
  done

  # imprime resultados únicos e ordenados
  if [ "${#res[@]}" -gt 0 ]; then
    printf '%s\n' "${res[@]}" | sort -u
  fi
}

run_exe() {
  local exe="$1"
  if [ ! -f "$exe" ]; then
    err "Arquivo não encontrado: $exe"
    exit 1
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
    err "Nenhum arquivo .exe encontrado em: $(cd "$dir" && pwd)"
    exit 1
  fi

  echo "Executáveis encontrados em $(cd "$dir" && pwd):"
  PS3=$'\nEscolha um número para rodar (Ctrl+C cancela): '
  select exe in "${exes[@]}"; do
    if [ -n "${exe:-}" ]; then
      run_exe "$exe"
      break
    else
      echo "Opção inválida, tente de novo."
    fi
  done
}

print_help() {
  cat <<'EOF'
wine-portatil.sh — Wine portátil sem sudo, dentro de uma pasta local.

USO:
  ./wine-portatil.sh                    Instala o Wine (se necessário) e
                                         mostra um menu com os .exe da
                                         pasta atual para escolher e rodar.
  ./wine-portatil.sh <pasta>             Mesma coisa, procurando .exe dentro
                                         de <pasta>.
  ./wine-portatil.sh <programa.exe>     Roda esse .exe diretamente.
  ./wine-portatil.sh --lista [pasta]    Só lista os .exe encontrados.
  ./wine-portatil.sh --instalar         Só baixa/instala o Wine.
  ./wine-portatil.sh --dxvk             Só instala o DXVK (Direct3D->Vulkan).
  ./wine-portatil.sh --winecfg          Abre o winecfg do prefixo portátil.
  ./wine-portatil.sh --shell            Abre um shell com wine no PATH.
  ./wine-portatil.sh --ajuda            Mostra esta mensagem.

Tudo fica dentro de ./portable-wine, ao lado deste script. Nada usa sudo.
Para "desinstalar", basta apagar essa pasta.

Variante do Wine (defina antes de rodar):
  WINE_VARIANT=vanilla ./wine-portatil.sh   (padrão) Wine sem patches extras
  WINE_VARIANT=staging ./wine-portatil.sh   Com patches extras de compatibilidade

Compatibilidade DXVK/DirectX:
  ENABLE_DXVK=1 ./wine-portatil.sh          (padrão) Usa DXVK para melhor
                                             compatibilidade com D3D11/D3D12
  ENABLE_DXVK=0 ./wine-portatil.sh          Desabilita DXVK (modo OpenGL puro)
  DXVK_VERSION=2.5 ./wine-portatil.sh       Especifica versão do DXVK
EOF
}

case "${1:-}" in
  --ajuda|--help|-h)
    print_help
    ;;
  --instalar|--install)
    install_wine
    log "Pronto. Wine em: $WINE_DIR"
    ;;
  --dxvk)
    install_wine
    install_dxvk
    setup_dxvk_prefix
    log "DXVK configurado em: $DXVK_DIR"
    ;;
  --winecfg)
    install_wine
    install_dxvk
    setup_dxvk_prefix
    WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" winecfg
    ;;
  --shell)
    install_wine
    install_dxvk
    setup_dxvk_prefix
    log "Shell com Wine portátil no PATH (rode 'wine programa.exe'; 'exit' sai)"
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
    setup_dxvk_prefix
    show_menu "."
    ;;
  *)
    install_wine
    install_dxvk
    setup_dxvk_prefix
    if [ -f "$1" ]; then
      run_exe "$1"
    elif [ -d "$1" ]; then
      show_menu "$1"
    else
      err "Não entendi o argumento: $1"
      print_help
      exit 1
    fi
    ;;
esac
