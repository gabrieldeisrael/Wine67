#!/usr/bin/env bash
set -euo pipefail

# teste.sh - Reescrito: instalador / reinstalador minimalista para Wine-GE / Proton-GE
# Objetivo: Apenas 2 ações (1=Instalar, 2=Reinstalar). Sem SUDO. Compatível com Linux Mint 20.04.
# Suporta criação correta de prefix win32/win64 (Wow64) e instalação local do DXVK (sem sudo).
# Instalação por usuário em: $HOME/Área de Trabalho/Wine67 (suporta Desktop em pt/en)

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

# Small spinner while a background PID is running
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

# Simple safe downloader with retries
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

# Obtém URL de release mais recente do GloriousEggroll (Proton-GE ou Wine-GE)
get_ge_url() {
  local tipo="$1"
  local repo tag file
  if [ "$tipo" = "proton-ge" ]; then
    repo="GloriousEggroll/proton-ge-custom"
    # release asset usually named: <tag>.tar.gz
    tag=$(curl -sS --max-time 10 "https://api.github.com/repos/${repo}/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4 || true)
    if [ -n "$tag" ]; then
      echo "https://github.com/${repo}/releases/download/${tag}/${tag}.tar.gz"
      return 0
    fi
    # fallback
    echo "https://github.com/${repo}/releases/download/GE-Proton10-34/GE-Proton10-34.tar.gz"
  else
    repo="GloriousEggroll/wine-ge-custom"
    tag=$(curl -sS --max-time 10 "https://api.github.com/repos/${repo}/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4 || true)
    if [ -n "$tag" ]; then
      echo "https://github.com/${repo}/releases/download/${tag}/wine-lutris-${tag}-x86_64.tar.xz"
      return 0
    fi
    # fallback
    echo "https://github.com/${repo}/releases/download/GE-Proton8-26/wine-lutris-GE-Proton8-26-x86_64.tar.xz"
  fi
}

# Obtém URL e instala DXVK localmente (no diretório DXVK_DIR)
install_dxvk_local() {
  # Latest DXVK release (tags like v1.10.3)
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

# Verifica ferramentas mínimas
for cmd in curl tar grep awk sed file; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_err "Comando ausente: $cmd. Instale-o (ex: sudo apt install $cmd) e rode novamente. Este script NÃO usa sudo por si só."
    exit 1
  fi
done

# Extrai o conteúdo do tar para INSTALL_DIR (sem sudo)
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
  # move top-level contents
  local top
  top=$(find "$INSTALL_DIR/tmp_extract" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)
  if [ -n "$top" ]; then
    shopt -s dotglob
    mv "$top"/* "$INSTALL_DIR"/ 2>/dev/null || true
    mv "$top"/.[!.]* "$INSTALL_DIR"/ 2>/dev/null || true
    shopt -u dotglob
  else
    # if tar contained files directly
    mv "$INSTALL_DIR/tmp_extract"/* "$INSTALL_DIR"/ 2>/dev/null || true
  fi
  rm -rf "$INSTALL_DIR/tmp_extract"
  # make main binaries executable
  find "$INSTALL_DIR" -type f -executable -print >/dev/null 2>&1 || true
}

# Validar instalação atual
valid_install() {
  if [ -x "$INSTALL_DIR/bin/wine64" ] || [ -x "$INSTALL_DIR/bin/wine" ] || [ -x "$INSTALL_DIR/proton" ]; then
    return 0
  fi
  return 1
}

# Cria prefix com suporte correto a win32/win64 (Wow64):
# - Para win64: usa WINEARCH=win64 + wine64 wineboot
# - Para win32: usa WINEARCH=win32 + wineboot
create_prefix() {
  local name="$1" arch="$2" # arch = win64|win32
  local p="$PREFIXES_DIR/$name"
  if [ -d "$p" ]; then
    log_warn "Prefix já existe: $p"
    return 0
  fi
  mkdir -p "$p"

  local winebin="${INSTALL_DIR}/bin/wine"
  local wine64bin="${INSTALL_DIR}/bin/wine64"
  if [ -x "$wine64bin" ]; then
    winebin="$wine64bin"
  elif [ -x "$INSTALL_DIR/proton" ]; then
    winebin="$INSTALL_DIR/proton"
  fi

  log_info "Criando prefix $name ($arch) usando $winebin"

  if [ "$arch" = "win64" ]; then
    # Two-step: try env-clean wineboot with wine64 first
    env -i HOME="$HOME" PATH="$INSTALL_DIR/bin:$PATH" DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$p" WINEARCH=win64 "$wine64bin" wineboot -i >/dev/null 2>&1 &
    pid=$!
    spinner $pid "Inicializando prefix win64"
    wait $pid || true
    # Check for syswow64
    if [ ! -d "$p/drive_c/windows/syswow64" ]; then
      log_warn "Prefix win64 não gerou syswow64. Tentando método alternativo..."
      rm -rf "$p" && mkdir -p "$p"
      (export WINEARCH=win64; export WINEPREFIX="$p"; export PATH="$INSTALL_DIR/bin:$PATH"; wine64 wineboot -i) >/dev/null 2>&1 || true
    fi
  else
    # win32
    env -i HOME="$HOME" PATH="$INSTALL_DIR/bin:$PATH" DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$p" WINEARCH=win32 "$winebin" wineboot -i >/dev/null 2>&1 &
    pid=$!
    spinner $pid "Inicializando prefix win32"
    wait $pid || true
  fi

  # Log básico
  if [ -f "$p/system.reg" ]; then
    log_ok "Prefix criado em: $p"
  else
    log_warn "Pareceu criar o prefix, mas system.reg ausente. Verifique manualmente: $p"
  fi

  # Se DXVK foi baixado, tente instalar no prefix com o setup_dxvk.sh
  local dxvk_setup
  dxvk_setup=$(find "$DXVK_DIR" -maxdepth 2 -name setup_dxvk.sh | head -n1 || true)
  if [ -n "$dxvk_setup" ] && [ -x "$dxvk_setup" ]; then
    log_info "Instalando DXVK no prefix $name"
    (export WINEPREFIX="$p"; export PATH="$INSTALL_DIR/bin:$PATH"; bash "$dxvk_setup" install) >/dev/null 2>&1 || true
    log_ok "Tentativa de instalar DXVK concluída (verifique logs se necessário)."
  else
    log_warn "setup_dxvk.sh não encontrado em $DXVK_DIR — pulei instalação do DXVK no prefix"
  fi
}

# Remove instalação completa (reinstalar)
reinstall_all() {
  log_warn "Removendo instalação em $INSTALL_DIR e prefixes em $PREFIXES_DIR"
  rm -rf "$INSTALL_DIR" "$PREFIXES_DIR" "$DXVK_DIR"
  mkdir -p "$INSTALL_DIR" "$PREFIXES_DIR" "$DXVK_DIR"
  log_ok "Removido. Pronto para reinstalar."
}

# Menu principal (somente 1=Instalar e 2=Reinstalar)
main_menu() {
  cat <<EOF

${BOLD}Wine67 Minimal Installer (Mint 20.04) - sem sudo${RESET}
Local: $BASE_DIR

Escolha:
  ${YELLOW}1${RESET} - Instalar (download e configurar Wine-GE/Proton-GE + DXVK opcional)
  ${YELLOW}2${RESET} - Reinstalar (limpar e instalar novamente)
  0 - Sair

EOF
  read -rp "Escolha: " opt
  case "$opt" in
    1) install_flow ;; 
    2) reinstall_flow ;; 
    0) log_info "Saindo."; exit 0 ;;
    *) log_err "Opção inválida."; main_menu ;;
  esac
}

install_flow() {
  # Escolha engine
  echo "\nEscolha engine a instalar:"
  echo "  1) Wine-GE (padrão, leve e compatível)"
  echo "  2) Proton-GE (Proton custom - pode ser maior)"
  read -rp "Engine (1 ou 2) [1]: " eopt
  eopt=${eopt:-1}
  local tipo="wine-ge"
  [ "$eopt" = "2" ] && tipo="proton-ge"

  if valid_install; then
    log_warn "Parece já haver uma instalação em $INSTALL_DIR. Use opção 2 para reinstalar ou remova manualmente."
    return 0
  fi

  local url
  url=$(get_ge_url "$tipo") || true
  if [ -z "$url" ]; then
    log_err "Não consegui detectar URL do $tipo"
    return 1
  fi

  local ext=".tar.gz"
  [[ "$url" == *.tar.xz ]] && ext=".tar.xz"
  local dest="$BASE_DIR/$(basename "$url")"

  download "$url" "$dest" "$tipo" || return 1
  extract_ge "$dest"
  rm -f "$dest"

  # baixar dxvk local (opcional)
  echo "\nDeseja baixar DXVK e tentar instalá-lo localmente? (recomendado para jogos DirectX) [S/n]"
  read -r dxopt
  dxopt=${dxopt:-s}
  if [[ "$dxopt" =~ ^[sSyY] ]]; then
    install_dxvk_local || log_warn "DXVK não instalado automaticamente. Você pode colocar o tar.gz em $DXVK_DIR e recriar o prefix."
  fi

  log_ok "Instalação do engine concluída. Criando um prefix de exemplo (opcional)."

  read -rp "Criar prefix de exemplo agora? Nome do prefix (ou vazio para pular): " prefix_name
  if [ -n "$prefix_name" ]; then
    echo "Escolha arquitetura do prefix: 1) 64-bit (recomendado para jogos 64)  2) 32-bit"
    read -rp "Arquitetura (1/2) [1]: " a
    a=${a:-1}
    local arch=win64
    [ "$a" != "1" ] && arch=win32
    create_prefix "$prefix_name" "$arch"
  fi

  log_ok "Instalação finalizada. Binários: $INSTALL_DIR/bin"
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

# Start
main_menu

exit 0
