#!/usr/bin/env bash
set -euo pipefail

# teste.sh - Wine-GE installer + run helper (UI ajustada)
# - Apenas Wine-GE (Proton removido)
# - Prefixes win64/win32 por padrão conforme detectado
# - Após instalar: busca todos os .exe, ordena alfabeticamente e permite executar (todos ou apenas um)
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
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' BG_YELLOW='\033[43m' BLACK='\033[0;30m'
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

# checar comandos necessários (sem sugerir sudo)
for cmd in curl tar grep awk sed file find sort mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_err "Comando ausente: $cmd. Instale-o com o gerenciador de pacotes da sua distribuição e rode novamente."
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

# Install wine locally (no sudo) by creating user-level wrappers/symlinks in ~/.local/bin
setup_local_wine() {
  if [ -d "$INSTALL_DIR/bin" ] && ( [ -x "$INSTALL_DIR/bin/wine" ] || [ -x "$INSTALL_DIR/bin/wine64" ] ); then
    mkdir -p "$HOME/.local/bin"
    for b in wine wine64 wineboot winecfg; do
      if [ -x "$INSTALL_DIR/bin/$b" ]; then
        ln -sf "$INSTALL_DIR/bin/$b" "$HOME/.local/bin/$b"
        chmod +x "$INSTALL_DIR/bin/$b" || true
      fi
    done
    export PATH="$HOME/.local/bin:$PATH"
    log_ok "Wine (local) instalado em $HOME/.local/bin e PATH atualizado para esta sessão."
    log_warn "Para tornar permanente, adicione: export PATH=\"$HOME/.local/bin:\$PATH\" ao seu ~/.profile ou rc de shell."
    return 0
  else
    log_warn "Binários do Wine não encontrados em $INSTALL_DIR/bin; verifique instalação."
    return 1
  fi
}

# Check for 32-bit loader (ld-linux.so.2) and inform user with distro commands if missing
check_32bit_loader() {
  if [ -f /lib/ld-linux.so.2 ] || [ -f /lib32/ld-linux.so.2 ] || [ -f /lib64/ld-linux-x86-64.so.2 ]; then
    return 0
  fi

  log_warn "/lib/ld-linux.so.2 não encontrado — executáveis 32-bit podem falhar (ld-linux loader ausente)."
  cat <<'INSTR'
Instalação (requer sudo) — exemplos por distribuição:

Debian / Ubuntu / Mint:
  sudo dpkg --add-architecture i386
  sudo apt update
  sudo apt install libc6:i386 wine32 -y

Fedora:
  sudo dnf install glibc.i686 wine -y

Arch Linux (habilitar multilib em /etc/pacman.conf):
  sudo pacman -Syu
  sudo pacman -S lib32-glibc wine

openSUSE:
  sudo zypper install glibc-32bit wine

Observação: instalar wine32 (ou pacotes i386/glibc) geralmente resolve '/lib/ld-linux.so.2: could not open' e ShellExecuteEx falhou.
INSTR
  return 1
}

valid_install() {
  if [ -x "$INSTALL_DIR/bin/wine64" ] || [ -x "$INSTALL_DIR/bin/wine" ]; then
    return 0
  fi
  return 1
}

# Create win64 prefix (wow64 capable)
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

# Create win32 prefix
create_win32_prefix() {
  local name="$1"
  local p="$PREFIXES_DIR/$name"
  if [ -d "$p" ] && [ -f "$p/system.reg" ]; then
    log_warn "Prefix já existe: $p"
    return 0
  fi
  mkdir -p "$p"

  local winebin="$INSTALL_DIR/bin/wine"
  if [ ! -x "$winebin" ]; then
    winebin=$(command -v wine || true)
  fi
  if [ -z "$winebin" ]; then
    log_err "wine (32-bit) não encontrado. Verifique instalação em $INSTALL_DIR/bin"
    return 1
  fi

  log_info "Criando prefix win32 em: $p"
  env -i HOME="$HOME" PATH="$INSTALL_DIR/bin:$PATH" DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$p" WINEARCH=win32 "$winebin" wineboot -i >/dev/null 2>&1 &
  pid=$!
  spinner $pid "Inicializando prefix win32"
  wait $pid || true

  if [ -f "$p/system.reg" ]; then
    log_ok "Prefix win32 criado: $p"
  else
    log_warn "Prefix criado, mas system.reg ausente; confira: $p"
  fi
}

reinstall_all() {
  log_warn "Removendo instalação em $BASE_DIR e prefixes"
  rm -rf "$BASE_DIR"
  mkdir -p "$INSTALL_DIR" "$PREFIXES_DIR" "$DXVK_DIR"
  log_ok "Removido. Pronto para reinstalar."
}

# Scan common locations for .exe files and return sorted list (DO NOT dedupe — show all)
scan_exes() {
  declare -a SEARCH_PATHS=(
    "$BASE_DIR"
    "$HOME/Downloads"
    "$HOME/Descargas"
    "$HOME/Transferências"
    "/media"
    "/mnt"
    "$SCRIPT_DIR"
  )

  local tmp
  tmp=$(mktemp)
  for sp in "${SEARCH_PATHS[@]}"; do
    [ -d "$sp" ] || continue
    find "$sp" -maxdepth 10 -type f -iname "*.exe" -print >> "$tmp" 2>/dev/null || true
  done

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 1
  fi

  # sort case-insensitive but keep duplicates (list ALL found)
  mapfile -t EXES < <(sort -f "$tmp")
  rm -f "$tmp"
  return 0
}

run_exe_with_prefix() {
  local selected="$1"
  local arch="win64"
  if command -v file >/dev/null 2>&1; then
    local info
    info=$(file -b "$selected" 2>/dev/null || true)
    if echo "$info" | grep -qi "32-bit"; then
      arch="win32"
    fi
  fi
  log_info "Arquitetura detectada (exe): $arch"

  local game_name
  game_name=$(basename "$selected" .exe | tr -cd '[:alnum:]_-')
  local prefix="$PREFIXES_DIR/$game_name"

  if [ "$arch" = "win32" ]; then
    if [ ! -f "$prefix/system.reg" ]; then
      create_win32_prefix "$game_name" || { log_err "Falha ao criar prefix win32"; return 1; }
    else
      log_info "Usando prefix win32 existente: $prefix"
    fi
  else
    if [ ! -f "$prefix/system.reg" ]; then
      create_win64_prefix "$game_name" || { log_err "Falha ao criar prefix win64"; return 1; }
    else
      log_info "Usando prefix win64 existente: $prefix"
    fi
  fi

  # prefer local wine binaries if available
  local winebin
  if [ "$arch" = "win32" ]; then
    winebin="$INSTALL_DIR/bin/wine"
  else
    winebin="$INSTALL_DIR/bin/wine64"
  fi
  if [ ! -x "$winebin" ]; then
    winebin=$(command -v wine64 || command -v wine || true)
  fi
  if [ -z "$winebin" ]; then
    log_err "wine não encontrou binários. Verifique instalação."; return 1
  fi

  local exe_dir
  exe_dir=$(dirname "$selected")
  local exe_base
  exe_base=$(basename "$selected")

  # Try running with start /unix from the exe directory (avoids ShellExecuteEx errors)
  ( cd "$exe_dir" && env WINEPREFIX="$prefix" PATH="$INSTALL_DIR/bin:$PATH" "$winebin" start /unix "./$exe_base" ) || \
  # Fallback: run absolute path
  env WINEPREFIX="$prefix" PATH="$INSTALL_DIR/bin:$PATH" "$winebin" "$selected"
}

# After install: scan, present alphabetical list and let user run
post_install_select_and_run() {
  log_info "Procurando .exe em locais comuns..."
  if ! scan_exes; then
    log_warn "Nenhum .exe encontrado automaticamente."
    echo -e "\nForneça o caminho completo para o .exe (ou Enter para cancelar):"
    read -r USER_EXE
    USER_EXE="${USER_EXE//\'//}"
    [ -z "$USER_EXE" ] && { log_info "Cancelado."; return 0; }
    [ -f "$USER_EXE" ] || { log_err "Arquivo não encontrado: $USER_EXE"; return 1; }
    EXES=("$USER_EXE")
  fi

  echo
  echo -e "${BOLD}Arquivos .exe encontrados (ordem alfabética — TODOS os resultados):${RESET}"
  printf "  %s\n" "${CYAN}Total: ${#EXES[@]}${RESET}"
  echo
  for i in "${!EXES[@]}"; do
    idx=$((i+1))
    fname=$(basename "${EXES[$i]}")
    # index and filename in yellow (foreground)
    printf "  %b[%d]%b %b%s%b\n" "${YELLOW}" "$idx" "${RESET}" "${YELLOW}${BOLD}" "$fname" "${RESET}"
  done

  echo
  echo "Digite um número para executar apenas aquele .exe,"
  echo "ou 'a' para executar TODOS em ordem alfabética,"
  echo "ou Enter para cancelar:"
  read -r choice
  if [ -z "$choice" ]; then log_info "Cancelado."; return 0; fi

  if [[ "$choice" =~ ^[aA]$ ]]; then
    for exe in "${EXES[@]}"; do
      fname=$(basename "$exe")
      log_info ">>> Executando: $fname"
      run_exe_with_prefix "$exe" || log_warn "Falha ao executar: $fname"
      echo
    done
    return 0
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then log_err "Opção inválida"; return 1; fi
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#EXES[@]}" ]; then log_err "Opção inválida"; return 1; fi
  local selected="${EXES[$((choice-1))]}"
  selname=$(basename "$selected")
  log_info "Selecionado: $selname"
  run_exe_with_prefix "$selected"
}

# Quick install: remove everything and run normal install non-interactive where possible
quick_install_flow() {
  log_warn "Execução de instalação rápida: removendo pasta inteira e reinstalando"
  reinstall_all
  local url
  url=$(get_ge_url) || true
  if [ -z "$url" ]; then log_err "Não consegui detectar URL do Wine-GE"; return 1; fi
  local dest="$BASE_DIR/$(basename "$url")"
  download "$url" "$dest" "wine-ge" || return 1
  extract_ge "$dest"
  rm -f "$dest"

  setup_local_wine || log_warn "Falha ao configurar wine local automaticamente"
  install_dxvk_local || log_warn "Falha ao instalar DXVK automaticamente"
  log_ok "Instalação rápida concluída. Binários: $INSTALL_DIR/bin"
  post_install_select_and_run
}

install_flow() {
  # check 32-bit loader early and inform the user (does not block install)
  check_32bit_loader || true

  if valid_install; then
    log_warn "Parece já haver uma instalação em $INSTALL_DIR."
    echo "Deseja usar a instalação existente e procurar/rodar .exe? [S/n]"
    read -r use_existing; use_existing=${use_existing:-s}
    if [[ "$use_existing" =~ ^[sSyY] ]]; then
      post_install_select_and_run
      return 0
    else
      log_info "Continuando para reinstalar..."
      reinstall_all
    fi
  fi

  local url
  url=$(get_ge_url) || true
  if [ -z "$url" ]; then log_err "Não consegui detectar URL do Wine-GE"; return 1; fi
  local dest="$BASE_DIR/$(basename "$url")"
  download "$url" "$dest" "wine-ge" || return 1
  extract_ge "$dest"
  rm -f "$dest"

  # try to make wine available for the user without sudo
  if setup_local_wine; then
    log_ok "Wine local configurado."
  else
    log_warn "Wine local não configurado automaticamente. Você pode rodar o script novamente após extrair o binário em $INSTALL_DIR/bin."
  fi

  echo
  echo "Deseja baixar DXVK e tentar instalá-lo localmente? (recomendado para jogos DirectX) [S/n]"
  read -r dxopt; dxopt=${dxopt:-s}
  if [[ "$dxopt" =~ ^[sSyY] ]]; then
    install_dxvk_local || log_warn "DXVK não instalado automaticamente. Você pode colocar o tar.gz em $DXVK_DIR e recriar o prefix."
  fi

  log_ok "Instalação concluída. Binários: $INSTALL_DIR/bin"
  post_install_select_and_run
}

reinstall_flow() {
  read -rp "Confirma remoção completa de $BASE_DIR e prefixes? (s/N): " yn
  case "$yn" in
    s|S|y|Y|sim|SIM) ;;
    *) log_info "Reinstalação cancelada."; return 0 ;;
  esac
  reinstall_all
  install_flow
}

draw_header() {
  clear
  local title="Wine67 Minimal (Wine-GE only) - sem sudo"
  local location="Local: $BASE_DIR"
  printf "%s\n" "=============================================="
  printf "%s\n" "  ${BOLD}${title}${RESET}"
  printf "%s\n" "  ${CYAN}${location}${RESET}"
  printf "%s\n" "=============================================="
}

main_menu() {
  draw_header
  echo
  echo -e "Escolha:"
  printf "  %b %b - %b\n" "${GREEN}●${RESET}" "${YELLOW}[1]${RESET}" "${BOLD}Instalar / Executar${RESET}"
  printf "  %b %b - %b\n" "${GREEN}●${RESET}" "${YELLOW}[2]${RESET}" "${BOLD}Reinstalar (recriar pasta inteira)${RESET}"
  printf "  %b %b - %b\n" "${GREEN}●${RESET}" "${YELLOW}[3]${RESET}" "${BOLD}Instalação rápida (recria pasta inteira e tenta configurar)${RESET}"
  echo
  read -rp "Escolha (use Ctrl+C para sair): " opt
  case "$opt" in
    1) install_flow ;;
    2) reinstall_flow ;;
    3) quick_install_flow ;;
    *) log_err "Opção inválida."; sleep 1; main_menu ;;
  esac
}

# start
while true; do
  main_menu
  echo
  read -rp "Pressione Enter para voltar ao menu principal..." _ || true
done

exit 0
