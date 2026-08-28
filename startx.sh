#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BASE_DIR="$SCRIPT_DIR/portable-wine"
WINE_DIR="$BASE_DIR/wine"
PREFIX_DIR="$BASE_DIR/prefix"
DOWNLOAD_DIR="$BASE_DIR/download"

WINE_VARIANT="${WINE_VARIANT:-vanilla}"

REPO="Kron4ek/Wine-Builds"
API_LATEST="https://api.github.com/repos/${REPO}/releases/latest"

FALLBACK_VERSION="11.15"

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

check_arch() {
  local m
  m="$(uname -m)"
  if [ "$m" != "x86_64" ]; then
    err "Este script foi feito para máquinas x86_64 (encontrei: $m)."
    err "Os builds do Wine usados aqui não cobrem outras arquiteturas."
    exit 1
  fi
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

install_wine() {
  check_arch

  if wine_installed; then
    return 0
  fi

  mkdir -p "$BASE_DIR" "$DOWNLOAD_DIR" "$PREFIX_DIR"

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

find_exes() {
  local dir="${1:-.}"
  find "$dir" -maxdepth 3 -type f -iname '*.exe' -not -path '*/portable-wine/*' 2>/dev/null | sort
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
  ./wine-portatil.sh --winecfg          Abre o winecfg do prefixo portátil.
  ./wine-portatil.sh --shell            Abre um shell com wine no PATH.
  ./wine-portatil.sh --ajuda            Mostra esta mensagem.

Tudo fica dentro de ./portable-wine, ao lado deste script. Nada usa sudo.
Para "desinstalar", basta apagar essa pasta.

Variante do Wine (defina antes de rodar):
  WINE_VARIANT=vanilla ./wine-portatil.sh   (padrão) Wine sem patches extras
  WINE_VARIANT=staging ./wine-portatil.sh   Com patches extras de compatibilidade
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
  --winecfg)
    install_wine
    WINEPREFIX="$PREFIX_DIR" WINEARCH=win64 "$WINE_DIR/bin/wine" winecfg
    ;;
  --shell)
    install_wine
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
    show_menu "."
    ;;
  *)
    install_wine
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
