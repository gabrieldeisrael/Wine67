#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DESKTOP="$HOME/Desktop"
[ -d "$HOME/Área de Trabalho" ] && DESKTOP="$HOME/Área de Trabalho"
BASE_DIR="$DESKTOP/Wine67"
INSTALL_DIR="$BASE_DIR/wine"
DXVK_DIR="$BASE_DIR/dxvk"
PREFIXES_DIR="$BASE_DIR/prefixes"
mkdir -p "$INSTALL_DIR" "$DXVK_DIR" "$PREFIXES_DIR" "$HOME/.local/bin"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' BOLD='\033[1m' RESET='\033[0m'

log_err(){ echo -e "${RED}✖ $*${RESET}" >&2; }
log_ok(){ echo -e "${GREEN}✔ $*${RESET}"; }
log_warn(){ echo -e "${YELLOW}⚠ $*${RESET}"; }
log_info(){ echo -e "${CYAN}➜ $*${RESET}"; }

MAX_RETRIES=3
RETRY_DELAY=4

spinner_bg() {
  local pid=$1; local msg=${2:-Processing}
  local chars='/-\\|'; i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  [%c] %s' "${chars:i%${#chars}:1}" "$msg"
    sleep 0.08; i=$((i+1))
  done
  printf '\r  [✔] %s\n' "$msg"
}

download() {
 local url dest name
  url="${1:-}"
  dest="${2:-}"
  name="${3:-file}"
  local attempt=1

  while [ $attempt -le $MAX_RETRIES ]; do
    log_info "Baixando $name (tentativa $attempt/$MAX_RETRIES)"
    rm -f "$dest"
    if curl -L --fail --connect-timeout 15 --max-time 600 -# -o "$dest" "$url" 2>/dev/null; then
      [ -s "$dest" ] && { log_ok "$name baixado: $(du -h "$dest" | cut -f1)"; return 0; }
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
  echo "https://github.com/GloriousEggroll/wine-ge-custom/releases/download/GE-Proton8-26/wine-lutris-GE-Proton8-26-x86_64.tar.xz"
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
  log_warn "Não foi possível obter DXVK automaticamente. Coloque um tar.gz em $DXVK_DIR e reexecute."
  return 1
}

# Instala Wine via repositório WineHQ focado em Ubuntu 20.04 (Linux Mint 20.x)
install_system_wine() {
  log_info "Tentando instalar Wine (WineHQ) pelo gerenciador do sistema (focal/Mint 20)..."
  if command -v wine >/dev/null 2>&1 || command -v wine64 >/dev/null 2>&1; then
    log_ok "Wine já disponível: $(wine --version 2>/dev/null || wine64 --version 2>/dev/null || true)"
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    log_err "apt-get não encontrado — este instalador automatizado suporta distribuições baseadas em Debian/Ubuntu (Mint)."
    return 1
  fi

  # detecta codename Ubuntu (focal para Mint 20)
  local ubuntu_codename=""
  ubuntu_codename=$(lsb_release -cs 2>/dev/null || true)
  if [ -f /etc/os-release ]; then
    . /etc/os-release || true
    ubuntu_codename=${UBUNTU_CODENAME:-$ubuntu_codename}
  fi
  # Forçar focal se detectarmos Mint 20 base e não tivermos UBUNTU_CODENAME
  case "$ubuntu_codename" in
    ulyana|uma|ulyssa|uma*) ubuntu_codename="focal" ;; # fallback common Mint codenames -> focal
  esac
  ubuntu_codename=${ubuntu_codename:-focal}

  log_info "Usando codename Ubuntu: $ubuntu_codename"

  # pedir consentimento para usar sudo (se não for root)
  local need_sudo=0
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      read -rp "A instalação precisa executar comandos como root (sudo). Continuar? [S/n]: " yn
      yn=${yn:-s}
      case "$yn" in s|S|y|Y) need_sudo=1 ;; *) log_info "Instalação cancelada pelo usuário."; return 1 ;; esac
    else
      log_err "Não há sudo e você não é root. Impossível instalar automaticamente."
      return 1
    fi
  fi

  # Instala pré-requisitos
  if [ "$need_sudo" -eq 1 ]; then
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends wget ca-certificates gnupg2 software-properties-common apt-transport-https || true
    sudo dpkg --add-architecture i386 || true
    # adicionar chave e repositório WineHQ
    log_info "Adicionando chave do WineHQ..."
    if ! wget -qO- https://dl.winehq.org/wine-builds/winehq.key | sudo apt-key add - >/dev/null 2>&1; then
      log_warn "Falha ao adicionar chave via apt-key; tentando via gpg/arquivo..."
      sudo mkdir -p /etc/apt/keyrings || true
      wget -qO /tmp/winehq.key https://dl.winehq.org/wine-builds/winehq.key || true
      if [ -f /tmp/winehq.key ]; then
        sudo apt-key add /tmp/winehq.key >/dev/null 2>&1 || true
      fi
      rm -f /tmp/winehq.key
    fi

    if ! grep -R "dl.winehq.org/wine-builds" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | grep -q .; then
      log_info "Adicionando repositório WineHQ para ${ubuntu_codename}..."
      sudo add-apt-repository -y "deb https://dl.winehq.org/wine-builds/ubuntu/ ${ubuntu_codename} main" || true
    else
      log_info "Repositório WineHQ já presente."
    fi

    sudo apt-get update -y
    log_info "Instalando winehq-stable..."
    if sudo apt-get install -y --install-recommends winehq-stable; then
      log_ok "winehq-stable instalado com sucesso."
    else
      log_warn "Falha ao instalar winehq-stable. Tentando winehq-devel e wine-stable..."
      sudo apt-get install -y --install-recommends winehq-devel || sudo apt-get install -y wine-stable || true
    fi
  else
    # já é root
    apt-get update -y
    apt-get install -y --no-install-recommends wget ca-certificates gnupg2 software-properties-common apt-transport-https || true
    dpkg --add-architecture i386 || true
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key | apt-key add - >/dev/null 2>&1 || true
    if ! grep -R "dl.winehq.org/wine-builds" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | grep -q .; then
      add-apt-repository -y "deb https://dl.winehq.org/wine-builds/ubuntu/ ${ubuntu_codename} main" || true
    fi
    apt-get update -y
    apt-get install -y --install-recommends winehq-stable || (apt-get install -y --install-recommends winehq-devel || apt-get install -y wine-stable || true)
  fi

  # Verifica se ficou disponível
  if command -v wine >/dev/null 2>&1 || command -v wine64 >/dev/null 2>&1; then
    log_ok "Wine disponível: $(wine --version 2>/dev/null || wine64 --version 2>/dev/null || true)"
    return 0
  fi

  log_err "Não consegui instalar o Wine automaticamente via WineHQ. Instale manualmente conforme https://wiki.winehq.org/Ubuntu"
  return 1
}

for cmd in curl tar grep awk sed file find sort mktemp winetricks wget lsb_release; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [ "$cmd" = "winetricks" ]; then
      log_warn "winetricks não encontrado — algumas correções automáticas (runtimes) não funcionarão. Recomendo instalar winetricks."
    elif [ "$cmd" = "lsb_release" ]; then
      # lsb_release é opcional, mas recomendado
      log_warn "lsb_release não encontrado — suposições de codename serão feitas."
    else
      log_err "Comando ausente: $cmd. Instale-o com o gerenciador de pacotes e rode novamente."
      exit 1
    fi
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

setup_local_wine() {
  if [ -d "$INSTALL_DIR/bin" ] && ( [ -x "$INSTALL_DIR/bin/wine" ] || [ -x "$INSTALL_DIR/bin/wine64" ] ); then
    for b in wine wine64 wineboot winecfg; do
      [ -x "$INSTALL_DIR/bin/$b" ] && ln -sf "$INSTALL_DIR/bin/$b" "$HOME/.local/bin/$b"
    done
    export PATH="$HOME/.local/bin:$PATH"
    log_ok "Wine local instalado em $HOME/.local/bin"
    return 0
  else
    log_warn "Binários do Wine não encontrados em $INSTALL_DIR/bin"
    return 1
  fi
}

valid_install() {
  [ -x "$INSTALL_DIR/bin/wine64" ] || [ -x "$INSTALL_DIR/bin/wine" ] && return 0
  return 1
}

create_prefix() {
  local name="$1"
  local arch="$2"
  local p="$PREFIXES_DIR/$name"
  mkdir -p "$p"
  local winebin="$INSTALL_DIR/bin/wine"
  local wine64bin="$INSTALL_DIR/bin/wine64"
  if [ "$arch" = "win64" ]; then
    winebin="${wine64bin:-$(command -v wine64 || true)}"
    [ -n "$winebin" ] || winebin=$(command -v wine || true)
  else
    winebin="${winebin:-$(command -v wine || true)}"
  fi
  if [ -z "$winebin" ]; then
    log_err "wine não encontrado para criar prefix: $p"; return 1
  fi
  log_info "Criando prefix $arch em: $p"
  env -i HOME="$HOME" PATH="$INSTALL_DIR/bin:$PATH" DISPLAY="${DISPLAY:-:0}" WINEPREFIX="$p" WINEARCH="$arch" "$winebin" wineboot -i >/dev/null 2>&1 &
  pid=$!; spinner_bg $pid "Inicializando prefix $arch"
  wait $pid || true
  if [ -f "$p/system.reg" ]; then
    log_ok "Prefix criado: $p"
  else
    log_warn "Prefix criado, mas system.reg ausente; confira: $p"
  fi

  if command -v winetricks >/dev/null 2>&1; then
    log_info "Instalando runtimes básicos (vcrun2013,vcrun2015,d3dx9,corefonts) no prefix $name"
    env WINEPREFIX="$p" winetricks -q vcrun2013 vcrun2015 d3dx9 corefonts || log_warn "winetricks falhou para $name"
  fi

  local dxvk_setup
  dxvk_setup=$(find "$DXVK_DIR" -maxdepth 2 -name setup_dxvk.sh | head -n1 || true)
  if [ -n "$dxvk_setup" ] && [ -x "$dxvk_setup" ]; then
    log_info "Tentando instalar DXVK no prefix $name"
    (export WINEPREFIX="$p"; export PATH="$INSTALL_DIR/bin:$PATH"; bash "$dxvk_setup" install) >/dev/null 2>&1 || log_warn "Instalação DXVK falhou para $name"
  fi
}

install_wow64_quick() {
  log_info "Instalação rápida do wow64 (criando prefix template win64 e win32)"
  local template="template_prefix"
  local total=20
  for step in $(seq 1 $total); do
    printf '\r[%-20s] %d%%' "$(printf '%0.s#' $(seq 1 $step))" $((step*100/total))
    sleep 0.05
  done
  printf '\n'
  create_prefix "${template}_64" "win64" || log_warn "Criar win64 falhou"
  create_prefix "${template}_32" "win32" || log_warn "Criar win32 falhou"
  log_ok "Template wow64 criado: ${PREFIXES_DIR}/${template}_64 (use para novos jogos win64)"
  return 0
}

reinstall_all() {
  log_warn "Removendo $BASE_DIR e prefixes"
  rm -rf "$BASE_DIR"
  mkdir -p "$INSTALL_DIR" "$PREFIXES_DIR" "$DXVK_DIR"
  log_ok "Removido. Pronto para reinstalar."
}

scan_exes() {
  EXES=()
  declare -a SEARCH_PATHS=(
    "$BASE_DIR" "$HOME/Downloads" "$HOME/Descargas" "$HOME/Transferências" "/media" "/mnt" "$SCRIPT_DIR"
  )
  local tmp; tmp=$(mktemp)
  for sp in "${SEARCH_PATHS[@]}"; do
    [ -d "$sp" ] || continue
    find "$sp" -maxdepth 10 -type f -iname "*.exe" -print >> "$tmp" 2>/dev/null || true
  done
  if [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi
  mapfile -t EXES < <(sort -f "$tmp")
  rm -f "$tmp"
  return 0
}

detect_fs_type() {
  local path="$1"
  df -T "$path" 2>/dev/null | awk 'NR==2{print $2}' || true
}

prepare_run_env() {
  local prefix="$1"
  local fstype
  fstype=$(detect_fs_type "$prefix" || true)
  export WINEDEBUG=-all
  if [ "$fstype" = "ext4" ] || [ "$fstype" = "ext3" ]; then
    export WINEFSYNC=1
    export WINEESYNC=1
    log_info "FS Type: $fstype -> ativando WINEFSYNC/WINEESYNC para melhor desempenho"
  elif echo "$fstype" | grep -qi exfat >/dev/null 2>&1; then
    export WINEFSYNC=0
    export WINEESYNC=0
    log_warn "FS Type: exFAT — sem suporte a symlinks; o desempenho pode variar. Recomenda-se ext4 para melhores resultados."
  else
    export WINEFSYNC=1
    export WINEESYNC=1
  fi
}

run_exe_with_prefix() {
  local selected="$1"
  if [ ! -f "$selected" ]; then log_err "Arquivo não encontrado: $selected"; return 1; fi

  local info; info=$(file -b "$selected" 2>/dev/null || true)
  local arch="win64"
  if echo "$info" | grep -qi "32-bit"; then arch="win32"; fi
  log_info "Arquitetura detectada: $arch"

  local game_name; game_name=$(basename "$selected" .exe | tr -cd '[:alnum:]_-')
  local prefix="$PREFIXES_DIR/$game_name"

  if [ ! -f "$prefix/system.reg" ]; then
    create_prefix "$game_name" "$arch" || { log_err "Falha ao criar prefix $game_name"; return 1; }
  else
    log_info "Usando prefix existente: $prefix"
  fi

  prepare_run_env "$prefix"

  if command -v winetricks >/dev/null 2>&1 ; then
    log_info "Verificando/installing runtimes básicos no prefix (winetricks)..."
    env WINEPREFIX="$prefix" winetricks -q vcrun2013 vcrun2015 d3dx9 corefonts || log_warn "winetricks falhou (ou já instalado)"
  fi

  local dxvk_setup
  dxvk_setup=$(find "$DXVK_DIR" -maxdepth 2 -name setup_dxvk.sh | head -n1 || true)
  if [ -n "$dxvk_setup" ] && [ -x "$dxvk_setup" ]; then
    log_info "Instalando DXVK no prefix $game_name"
    (export WINEPREFIX="$prefix"; export PATH="$INSTALL_DIR/bin:$PATH"; bash "$dxvk_setup" install) >/dev/null 2>&1 || log_warn "DXVK não instalado no prefix $game_name"
  fi

  local lower; lower=$(echo "$game_name" | tr '[:upper:]' '[:lower:]')
  if echo "$lower" | grep -E 'garry|gmod|hl2|source' >/dev/null 2>&1; then
    log_info "Heurística Source/Garry's Mod detectada — usando prefix 32-bit e verificando dependências"
    if [ "$(basename "$prefix")" = "$game_name" ] && [ -f "$PREFIXES_DIR/${game_name}_32/system.reg" ]; then
      prefix="$PREFIXES_DIR/${game_name}_32"
      log_info "Usando prefix 32-bit alternativo: $prefix"
    elif [ ! -f "$PREFIXES_DIR/${game_name}_32/system.reg" ]; then
      create_prefix "${game_name}_32" "win32" || log_warn "Falha criar prefix 32-bit para $game_name"
      prefix="$PREFIXES_DIR/${game_name}_32"
    fi
  fi

  prepare_run_env "$prefix"

  local winebin="$INSTALL_DIR/bin/wine64"
  [ "$arch" = "win32" ] && winebin="$INSTALL_DIR/bin/wine"
  [ ! -x "$winebin" ] && winebin=$(command -v wine64 || command -v wine || true)
  [ -z "$winebin" ] && { log_err "wine não encontrado."; return 1; }

  local exe_dir; exe_dir=$(dirname "$selected")
  local exe_base; exe_base=$(basename "$selected")

  log_info "Executando $exe_base com WINEPREFIX=$prefix"
  ( cd "$exe_dir" && env WINEPREFIX="$prefix" PATH="$INSTALL_DIR/bin:$PATH" "$winebin" start /unix "./$exe_base" ) || \
  env WINEPREFIX="$prefix" PATH="$INSTALL_DIR/bin:$PATH" "$winebin" "$selected"
}

post_install_select_and_run() {
  log_info "Procurando .exe em locais comuns..."
  if ! scan_exes; then
    log_warn "Nenhum .exe encontrado automaticamente."
    echo -e "\nForneça o caminho completo para o .exe (ou Enter para cancelar):"
    read -r USER_EXE
    USER_EXE=$(printf '%s' "$USER_EXE" | tr -d "\\'")
    [ -z "$USER_EXE" ] && { log_info "Cancelado."; return 0; }
    [ -f "$USER_EXE" ] || { log_err "Arquivo não encontrado: $USER_EXE"; return 1; }
    EXES=("$USER_EXE")
  fi

  echo
  echo -e "${BOLD}Arquivos .exe encontrados (TODOS os resultados):${RESET}"
  printf "  %s\n" "${CYAN}Total: ${#EXES[@]}${RESET}"
  echo
  for i in "${!EXES[@]}"; do
    idx=$((i+1))
    fname=$(basename "${EXES[$i]}")
    printf "  ${YELLOW}[%-3d]${RESET} %s\n" "$idx" "$fname"
  done

  echo
  echo "Digite o número do .exe que deseja executar (ex: 1),"
  echo "ou Enter para cancelar:"
  read -r choice
  [ -z "$choice" ] && { log_info "Cancelado."; return 0; }
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then log_err "Opção inválida"; return 1; fi
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#EXES[@]}" ]; then log_err "Opção inválida"; return 1; fi
  local selected="${EXES[$((choice-1))]}"
  selname=$(basename "$selected")
  log_info "Selecionado: $selname"
  run_exe_with_prefix "$selected"
}

quick_install_flow() {
  log_warn "Instalação rápida: removendo e reinstalando"
  reinstall_all
  local url; url=$(get_ge_url) || true
  [ -z "$url" ] && { log_err "Não consegui detectar URL do Wine-GE"; return 1; }
  local dest="$BASE_DIR/$(basename "$url")"

  if download "$url" "$dest" "wine-ge"; then
    extract_ge "$dest"
    rm -f "$dest"
    setup_local_wine || log_warn "Falha ao configurar wine local automaticamente"
    install_dxvk_local || log_warn "Falha ao instalar DXVK automaticamente"
    install_wow64_quick || log_warn "Falha instalar wow64 rápido"
    log_ok "Instalação rápida concluída."
    post_install_select_and_run
    return 0
  fi

  # fallback: instalar wine pelo WineHQ (Ubuntu focal / Mint 20)
  log_warn "Download do Wine-GE falhou. Tentando instalar Wine pelo repositório WineHQ (focal)..."
  if install_system_wine; then
    log_ok "Wine do sistema instalado. Prosseguindo sem Wine-GE."
    post_install_select_and_run
    return 0
  else
    log_err "Não foi possível obter Wine-GE nem instalar Wine do sistema."
    return 1
  fi
}

install_flow() {
  if valid_install; then
    log_warn "Parece haver uma instalação em $INSTALL_DIR."
    echo "Deseja usar a instalação existente e procurar/rodar .exe? [S/n]"
    read -r use_existing; use_existing=${use_existing:-s}
    if [[ "$use_existing" =~ ^[sSyY]$ ]]; then post_install_select_and_run; return 0; fi
    log_info "Continuando para reinstalar..."
    reinstall_all
  fi

  local url; url=$(get_ge_url) || true
  [ -z "$url" ] && { log_err "Não consegui detectar URL do Wine-GE"; return 1; }
  local dest="$BASE_DIR/$(basename "$url")"

  if download "$url" "$dest" "wine-ge"; then
    extract_ge "$dest"
    rm -f "$dest"
    setup_local_wine || log_warn "Wine local não configurado automaticamente"
  else
    log_warn "Falha ao baixar Wine-GE; tentando instalar Wine do sistema (WineHQ)..."
    if install_system_wine; then
      log_ok "Wine do sistema instalado. Prosseguindo sem Wine-GE."
    else
      log_err "Não foi possível obter Wine-GE nem instalar Wine do sistema."
      return 1
    fi
  fi

  echo
  echo "Deseja baixar DXVK e tentar instalá-lo localmente? [S/n]"
  read -r dxopt; dxopt=${dxopt:-s}
  if [[ "$dxopt" =~ ^[sSyY]$ ]]; then install_dxvk_local || log_warn "DXVK não instalado automaticamente"; fi
  echo "Deseja criar prefix template (wow64) rápido? [S/n]"
  read -r wowopt; wowopt=${wowopt:-s}
  if [[ "$wowopt" =~ ^[sSyY]$ ]]; then install_wow64_quick || log_warn "Falha no template wow64"
  fi
  log_ok "Instalação concluída."
  post_install_select_and_run
}

reinstall_flow() {
  read -rp "Confirma remoção completa de $BASE_DIR e prefixes? (s/N): " yn
  case "$yn" in s|S|y|Y|sim|SIM) ;; *) log_info "Reinstalação cancelada."; return 0 ;; esac
  reinstall_all
  install_flow
}

delete_flow() {
  read -rp "Confirma exclusão completa de $BASE_DIR? (s/N): " yn
  case "$yn" in s|S|y|Y|sim|SIM) rm -rf "$BASE_DIR"; log_ok "Excluído $BASE_DIR";; *) log_info "Exclusão cancelada.";; esac
}

draw_header() {
  clear
  printf "%s\n" "=============================================="
  printf "  ${BOLD}Wine67 Minimal (Wine-GE only) - sem sudo${RESET}\n"
  printf "  ${CYAN}Local: $BASE_DIR${RESET}\n"
  printf "%s\n" "=============================================="
}

main_menu() {
  draw_header
  echo
  echo -e "Escolha:"
  printf "  %b %b - %b\n" "${GREEN}●${RESET}" "${YELLOW}[1]${RESET}" "${BOLD}Instalar${RESET}"
  printf "  %b %b - %b\n" "${GREEN}●${RESET}" "${YELLOW}[2]${RESET}" "${BOLD}Executar (lista TODOS os .exe)${RESET}"
  printf "  %b %b - %b\n" "${GREEN}●${RESET}" "${YELLOW}[3]${RESET}" "${BOLD}Reinstalar (recriar pasta inteira)${RESET}"
  printf "  %b %b - %b\n" "${GREEN}●${RESET}" "${YELLOW}[4]${RESET}" "${BOLD}Excluir${RESET}"
  echo
  read -rp "Escolha (use Ctrl+C para sair): " opt
  case "$opt" in
    1) install_flow ;;
    2) post_install_select_and_run ;;
    3) reinstall_flow ;;
    4) delete_flow ;;
    *) log_err "Opção inválida."; sleep 1; main_menu ;;
  esac
}

while true; do
  main_menu
  echo
  read -rp "Pressione Enter para voltar ao menu principal..." _ || true
done

exit 0
