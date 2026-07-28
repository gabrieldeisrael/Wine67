#!/usr/bin/env bash
set -euo pipefail

# teste.sh - Wine-GE installer + run helper (updated)
# - Apenas Wine-GE (Proton removido)
# - Prefixes win64 (Wow64) por padrão — permite rodar 32-bit dentro de prefix 64-bit
# - Opção para buscar e executar .exe diretamente; cria prefix automaticamente
# - Sem sudo; local: ~/Área de Trabalho/Wine67 (ou ~/Desktop/Wine67)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect desktop path (PT/EN)
DESKTOP="$HOME/Desktop"
[ -d "$HOME/Área de Trabalho" ] && DESKTOP="$HOME/Área de Trabalho"

BASE_DIR="$DESKTOP/Wine67"
INSTALL_DIR="$BASE_DIR/wine"
DXVK_DIR="$BASE_DIR/dxvk"
PREFIXES_DIR="$BASE_DIR/prefixes"
mkdir -p "$INSTALL_DIR" "$DXVK_DIR" "$PREFIXES_DIR"

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m'
BOLD='\033[1m' RESET='\033[0m'

log_err()  { echo -e "${RED}✖ $*${RESET}"  >&2; }
log_ok()   { echo -e "${GREEN}✔ $*${RESET}"; }
log_warn() { echo -e "${YELLOW}⚠ $*${RESET}"; }
log_info() { echo -e "${CYAN}➜ $*${RESET}"; }

MAX_RETRIES=3
RETRY_DELAY=4

spinner() {
  local pid=$1; local msg=${2:-Processing}
  local chars='/-\\|'
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  [%c] %s' "${chars:i%${#chars}:1}" "$msg"
    sleep 0.08; i=$((i+1))
  done
  printf '\r  [✔] %s\n' "$msg"
}

download() {
  local url="$1" dest="$2" name="${3:-file}"
  local attempt=1
  while [ $attempt -le $MAX_RETRIES ]; do
    log_info "Baixando $name (tentativa $attempt/$MAX_RETRIES)"
    rm -f "$dest"
    if curl -L --fail --connect-timeout 15 --max-time 600 -# -o "$dest" "$url" 2>/dev/null; then
      if [ -s "$dest" ]; then
        log_ok "$name baixado: $(du -h "$dest" | cut -f1)"
        return 0
      fi
    fi
    rm -f "$dest"
    log_warn "Falha ao baixar $name"
    attempt=$((attempt+1))
    sleep $RETRY_DELAY
  done
  log_err "Não foi possível baixar $name após $MAX_RETRIES tentativas"
  return 1
}

get_ge_url() {
  local repo="GloriousEggroll/wine-ge-custom"
  local tag
  tag=$(curl -sS --max-time 10 "https://api.github.com/repos/${repo}/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4 || true)
  if [ -n "$tag" ]; then
    echo "https://github.com/${repo}/releases/download/${tag}/wine-lutris-${tag}-x86_64.tar.xz"
    return 0
  fi
  # fallback
  echo "https://github.com/${repo}/releases/download/GE-Proton8-26/wine-lutris-GE-Proton8-26-x86_64.tar.xz"
}

install_dxvk_local() {
  local api_url="https://api.github.com/repos/doitsujin/dxvk/releases/latest"
  local tag
  tag=$(curl -sS --max-time 10 "$api_url" | grep '"tag_name"' | head -1 | cut -d'"' -f4 || true)
  local dxvk_tar="dxvk.tar.gz"
  if [ -n "$tag" ]; then
    local asset_url="https://github.com/doitsujin/dxvk/releases/download/${tag}/dxvk-${tag#v}.tar.gz"
    if download "$asset_url" "$DXVK_DIR/$dxvk_tar" "DXVK (${tag})"; then
      tar -xzf "$DXVK_DIR/$dxvk_tar" -C "$DXVK_DIR"
      rm -f "$DXVK_DIR/$dxvk_tar"
      log_ok "DXVK ${tag} extraído em $DXVK_DIR"
      return 0
    fi
  fi
  log_warn "Não foi possível obter DXVK automaticamente. Você pode colocar um tar.gz de DXVK em $DXVK_DIR e reexecutar."
  return 1
}

for cmd in curl tar grep awk sed file find sort; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_err "Comando ausente: $cmd. Instale-o (ex: sudo apt install $cmd) e rode novamente. Este script NÃO usa sudo por si só."
    exit 1
  fi
done

extract_ge() {
  local tarfile="$1"
  log_info "Extraindo para $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"/tmp_extract || true
  mkdir -p "$INSTALL_DIR"/tmp_extract
  if [[ "$tarfile" == *.tar.xz ]]; then
    tar -xJf "$tarfile" -C "$INSTALL_DIR"/tmp_extract
  else
    tar -xzf "$tarfile" -C "$INSTALL_DIR"/tmp_extract
  fi
  local top
  top=$(find "$INSTALL_DIR/tmp_extract" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)
  if [ -n "$top" ]; then
    shopt -s dotglob
    mv "$top"/* "$INSTALL_DIR"/ 2>/dev/null || true
    mv "$top"/.[!.]* "$INSTALL_DIR"/ 2>/dev/null || true
    shopt -u dotglob
  else
    mv "$INSTALL_DIR/tmp_extract"/* "$INSTALL_DIR"/ 2>/dev/null || true
  fi
  rm -rf "$INSTALL_DIR/tmp_extract"
}

valid_install() {
  if [ -x "$INSTALL_DIR/bin/wine64" ] || [ -x "$INSTALL_DIR/bin/wine" ]; then
    return 0
  fi
  return 1
}

# Create win64 prefix (wow64 capable). We ALWAYS create win64 prefixes so 32-bit .exe run under wow64.
create_win64_prefix() {
  local name="$1"
  local p="$PREFIXES_DIR/$name"
  if [ -d "$p" ] && [ -f "$p/system.reg" ]; then
    log_warn "Prefix já existe: $p"
    return 0
  fi
  mkdir -p "$p"

  local wine64bin="$INSTALL_DIR/bin/wine64"
  if [ ! -x "$wine64bin" ]; then
    # fallback to wine in PATH
    wine64bin=$(command -v wine64 || true)
  fi
  if [ -z "$wine64bin" ]; then
    log_err "wine64 não encontrado. Verifique instalação em $INSTALL_DIR/bin"
    return 1
  fi

  log_info "Criando prefix win64 (wow64) em: $p"
  env -i HOME="$HOME" PATH="$INSTALL_DIR/bin:$PATH" DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$p" WINEARCH=win64 "$wine64bin" wineboot -i >/dev/null 2>&1 &
  pid=$!
  spinner $pid "Inicializando prefix win64"
  wait $pid || true

  # verify
  if [ -f "$p/system.reg" ]; then
    log_ok "Prefix win64 criado: $p"
  else
    log_warn "Prefix criado, mas system.reg ausente; confira: $p"
  fi

  # try to install DXVK into prefix if setup script exists
  local dxvk_setup
  dxvk_setup=$(find "$DXVK_DIR" -maxdepth 2 -name setup_dxvk.sh | head -n1 || true)
  if [ -n "$dxvk_setup" ] && [ -x "$dxvk_setup" ]; then
    log_info "Instalando DXVK no prefix $name"
    (export WINEPREFIX="$p"; export PATH="$INSTALL_DIR/bin:$PATH"; bash "$dxvk_setup" install) >/dev/null 2>&1 || true
    log_ok "Tentativa de instalar DXVK concluída (verifique logs se necessário)."
  fi
}

reinstall_all() {
  log_warn "Removendo instalação em $INSTALL_DIR e prefixes em $PREFIXES_DIR"
  rm -rf "$INSTALL_DIR" "$PREFIXES_DIR" "$DXVK_DIR"
  mkdir -p "$INSTALL_DIR" "$PREFIXES_DIR" "$DXVK_DIR"
  log_ok "Removido. Pronto para reinstalar."
}

# Scan common locations for .exe files and present a list to run
scan_and_run_exe() {
  declare -a SEARCH_PATHS=(
    "$BASE_DIR"
    "$HOME/Downloads"
    "$HOME/Descargas"
    "$HOME/Transferências"
    "/media"
    "/mnt"
    "$SCRIPT_DIR"
  )

  local -a EXES=()
  for sp in "${SEARCH_PATHS[@]}"; do
    [ -d "$sp" ] || continue
    while IFS= read -r -d $'\0' f; do
      EXES+=("$f")
    done < <(find "$sp" -maxdepth 10 -type f -iname "*.exe" -print0 2>/dev/null)
  done

  # dedupe
  IFS=$'\n' read -r -d '' -a EXES < <(printf "%s\0" "${EXES[@]}" | awk '!seen[$0]++' ORS='\0') || true

  if [ ${#EXES[@]} -eq 0 ]; then
    echo "\nNenhum .exe encontrado automaticamente. Forneça o caminho completo para o .exe (ou Enter para cancelar):"
    read -r USER_EXE
    USER_EXE="${USER_EXE//\'/}"
    [ -z "$USER_EXE" ] && { log_info "Cancelado."; return 0; }
    [ -f "$USER_EXE" ] || { log_err "Arquivo não encontrado: $USER_EXE"; return 1; }
    EXES=("$USER_EXE")
  fi

  echo "\nJogos encontrados:"
  for i in "${!EXES[@]}"; do
    printf "  [%d] %s\n" "$((i+1))" "${EXES[$i]}"
  done
  echo "\nEscolha o número (ou 0 para cancelar):"
  read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then log_err "Opção inválida"; return 1; fi
  if [ "$choice" -eq 0 ]; then log_info "Cancelado"; return 0; fi
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#EXES[@]}" ]; then log_err "Opção inválida"; return 1; fi

  local selected="${EXES[$((choice-1))]}"
  log_info "Selecionado: $selected"

  # detect architecture of exe (file)
  local arch="win64"
  if command -v file >/dev/null 2>&1; then
    local info
    info=$(file -b "$selected" 2>/dev/null || true)
    if echo "$info" | grep -qi "32-bit"; then
      arch="win32"
    fi
  fi
  log_info "Arquitetura detectada (exe): $arch -- usando prefix win64 (wow64)"

  # create prefix name from basename
  local game_name
  game_name=$(basename "$selected" .exe | tr -cd '[:alnum:]_-')
  local prefix="$PREFIXES_DIR/$game_name"

  if [ ! -f "$prefix/system.reg" ]; then
    create_win64_prefix "$game_name" || { log_err "Falha ao criar prefix"; return 1; }
  else
    log_info "Usando prefix existente: $prefix"
  fi

  # run the exe with wine64
  local winebin="$INSTALL_DIR/bin/wine64"
  if [ ! -x "$winebin" ]; then
    winebin=$(command -v wine64 || command -v wine || true)
  fi
  if [ -z "$winebin" ]; then
    log_err "wine não encontrou binários. Verifique instalação."; return 1
  fi

  log_info "Executando: WINEPREFIX=$prefix $winebin $selected"
  env WINEPREFIX="$prefix" PATH="$INSTALL_DIR/bin:$PATH" "$winebin" "$selected"
}

main_menu() {
  cat <<EOF

${BOLD}Wine67 Minimal (Wine-GE only) - sem sudo${RESET}
Local: $BASE_DIR

Escolha:
  ${YELLOW}1${RESET} - Instalar Wine-GE (download + extrair)
  ${YELLOW}2${RESET} - Reinstalar (limpar e instalar novamente)
  ${YELLOW}3${RESET} - Buscar e executar .exe (cria prefix win64 automaticamente)
  0 - Sair

EOF
  read -rp "Escolha: " opt
  case "$opt" in
    1) install_flow ;; 
    2) reinstall_flow ;; 
    3) scan_and_run_exe ;; 
    0) log_info "Saindo."; exit 0 ;;
    *) log_err "Opção inválida."; main_menu ;;
  esac
}

install_flow() {
  if valid_install; then
    log_warn "Parece já haver uma instalação em $INSTALL_DIR. Use opção 2 para reinstalar ou remova manualmente."
    return 0
  fi
  local url
  url=$(get_ge_url) || true
  if [ -z "$url" ]; then log_err "Não consegui detectar URL do Wine-GE"; return 1; fi
  local dest="$BASE_DIR/$(basename "$url")"
  download "$url" "$dest" "wine-ge" || return 1
  extract_ge "$dest"
  rm -f "$dest"

  echo "\nDeseja baixar DXVK e tentar instalá-lo localmente? (recomendado para jogos DirectX) [S/n]"
  read -r dxopt; dxopt=${dxopt:-s}
  if [[ "$dxopt" =~ ^[sSyY] ]]; then
    install_dxvk_local || log_warn "DXVK não instalado automaticamente. Você pode colocar o tar.gz em $DXVK_DIR e recriar o prefix."
  fi

  log_ok "Instalação concluída. Binários: $INSTALL_DIR/bin"
}

reinstall_flow() {
  read -rp "Confirma remoção completa de $INSTALL_DIR e prefixes? (s/N): " yn
  case "$yn" in
    s|S|y|Y|sim|SIM) ;;
    *) log_info "Reinstalação cancelada."; return 0 ;;
  esac
  reinstall_all
  install_flow
}

# start
main_menu

exit 0
