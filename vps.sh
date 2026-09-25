#!/usr/bin/env bash
set -e

# Очистка старого лога перед запуском
> /tmp/vps_setup.log

# === Функция спиннера в фоновом режиме ===
spin_loop() {
    local chars=( '|' '/' '-' '\' )
    local delay=0.1
    tput civis 2>/dev/null || true
    while true; do
        for c in "${chars[@]}"; do
            printf " [%s] " "$c"
            sleep $delay
            printf "\b\b\b\b\b"
        done
    done
}

start_spinner() {
    spin_loop &
    SPINNER_PID=$!
}

stop_spinner() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    tput cnorm 2>/dev/null || true
}

# === Функция выполнения каждого этапа ===
run_step() {
    local title="$1"
    shift
    
    echo -n " $title... "
    
    start_spinner
    
    # Перенаправляем вывод в лог-файл
    if "$@" >> /tmp/vps_setup.log 2>&1; then
        stop_spinner
        echo -e "\r\033[K✅ $title — готово"
    else
        stop_spinner
        echo -e "\r\033[K❌ $title — ошибка (лог: /tmp/vps_setup.log)"
        return 1
    fi
}

echo -e "\n🚀 Начинаем настройку сервера...\n"

# === 0.1. Фикс PATH и репозиториев для чистой Debian ===
prepare_debian() {
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
    
    if [ -f /etc/apt/sources.list ]; then
        sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list || true
    fi
}
run_step "Подготовка системного окружения (PATH/Репозитории)" prepare_debian

# === 0.2. Предварительная очистка кэша Zsh перед началом установки ===
pre_clean_zsh() {
    rm -rf ~/.local/share/zinit/completions \
           ~/.local/share/zinit/plugins/marlonrichert---zsh-autocomplete \
           ~/.zcompdump*
}
run_step "Очистка старого кэша Zsh" pre_clean_zsh

# === 1. Обновление системы и базовый набор пакетов ===
run_step "Обновление списка пакетов" apt-get update
run_step "Обновление системы (full-upgrade)" env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
run_step "Установка базовых утилит и шрифтов" env DEBIAN_FRONTEND=noninteractive apt-get install -yq micro sudo unzip autojump fontconfig ufw nano git wget curl zstd zsh net-tools cron socat btop fzf zoxide fonts-font-awesome

# === 2. Настройка часового пояса UTC ===
setup_timezone() {
    timedatectl set-timezone UTC || ln -fs /usr/share/zoneinfo/UTC /etc/localtime
}
run_step "Настройка часового пояса UTC" setup_timezone

# === 3. Настройка micro ===
setup_micro() {
    mkdir -p ~/.config/micro
    cat > ~/.config/micro/bindings.json << 'EOF'
{
    "Alt-/": "lua:comment.comment",
    "CtrlUnderscore": "lua:comment.comment",
    "Ctrl-c": "Copy",
    "Ctrl-v": "Paste"
}
EOF
    cat > ~/.config/micro/settings.json << 'EOF'
{
    "clipboard": "terminal"
}
EOF
}
run_step "Конфигурация редактора micro" setup_micro

# === 4. Установка Starship и шрифтов JetBrainsMono Nerd Font ===
install_starship() {
    curl -sS https://starship.rs/install.sh | sh -s -- -y
}
run_step "Установка Starship" install_starship

install_fonts() {
    if [ ! -d "$HOME/.local/share/fonts/JetBrainsMono" ]; then
        cd /tmp
        wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O JetBrainsMono.zip
        unzip -o JetBrainsMono.zip -d JetBrainsMono
        mkdir -p ~/.local/share/fonts/JetBrainsMono
        mv JetBrainsMono/* ~/.local/share/fonts/JetBrainsMono/
        fc-cache -fv
        rm -rf JetBrainsMono JetBrainsMono.zip
        cd ~
    fi
}
run_step "Проверка и установка шрифтов JetBrainsMono" install_fonts

# === 5. Включение zsh по умолчанию ===
set_zsh_default() {
    if command -v zsh >/dev/null 2>&1; then
        chsh -s "$(command -v zsh)" || true
    fi
}
run_step "Установка Zsh по умолчанию" set_zsh_default

# === 6. Генерация ~/.zshrc ===
generate_zshrc() {
    mkdir -p ~/.local/share/zsh
    touch ~/.local/share/zsh/chpwd-recent-dirs

    cat > ~/.zshrc << 'EOF'
# Полный системный PATH для гарантированного доступа к утилитам
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\(HOME/.local/bin:\)PATH"

# Инициализация работы с историей директорий
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs

# Прямой путь для Zinit
ZINIT_HOME="${HOME}/.local/share/zinit"
if [ ! -f "${ZINIT_HOME}/zinit.zsh" ]; then
    mkdir -p "${ZINIT_HOME}"
    git clone https://github.com/zdharma-continuum/zinit.git "${ZINIT_HOME}"
fi
source "${ZINIT_HOME}/zinit.zsh"

# --- Плагины ---
zinit ice depth=1; zinit light wting/autojump
zinit ice depth=1; zinit light zsh-users/zsh-syntax-highlighting
zinit ice depth=1; zinit light zsh-users/zsh-completions
zinit ice depth=1; zinit light zsh-users/zsh-autosuggestions
zinit ice depth=1; zinit light marlonrichert/zsh-autocomplete
zinit ice depth=1; zinit light junegunn/fzf
zinit ice depth=1; zinit light Aloxaf/fzf-tab
zinit snippet OMZ::plugins/git/git.plugin.zsh
zinit ice depth=1; zinit light ajeetdsouza/zoxide

# Меню history по Ctrl-R (через fzf)
bindkey '^R' fzf-history-widget

# Цвета completion-меню и инициализация
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
autoload -Uz compinit && compinit -u -C
zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '[%d]'

# Алиасы
alias ls='ls --color=auto'
alias rr='/usr/local/bin/remnawave_reverse'
alias rwe="docker exec -it remnawave cli"
alias up="apt update && apt full-upgrade -y"
alias upw="up && rwu"
alias mi="micro"
alias mzh="cd && mi .zshrc"
alias szh="cd && source .zshrc"
alias cl="clear"
alias mds="motd-set"
alias scu="bash <(wget -qO- https://raw.githubusercontent.com/arpicme/vps.sh/refs/heads/main/vps.sh)"
alias zup="zinit self-update -q && zinit update --all -q"

# Функции
rwr() {
  if cd /opt/remnanode 2>/dev/null || cd /opt/remnawave 2>/dev/null; then
    docker compose down && docker compose up -d && docker compose logs -f -t
  else
    echo "Ошибка: ни одна из папок (/opt/remnanode или /opt/remnawave) не найдена."
    return 1
  fi
}

rwu() {
  if cd /opt/remnanode 2>/dev/null || cd /opt/remnawave 2>/dev/null; then
    docker compose pull && docker compose down && docker compose up -d && docker compose logs -f -t
  else
    echo "Ошибка: ни одна из папок (/opt/remnanode или /opt/remnawave) не найдена."
    return 1
  fi
}

# Настройка истории
HISTSIZE=5000
SAVEHIST=5000
HISTFILE=~/.zsh_history

setopt append_history
setopt share_history
setopt inc_append_history
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt extended_history

# Поиск по истории по префиксу
bindkey '^P' history-search-backward
bindkey '^N' history-search-forward

# Starship prompt
eval "$(starship init zsh)"
EOF
}
run_step "Генерация файла конфигурации .zshrc" generate_zshrc

# === 7. Настройка задач Cron ===
setup_cron() {
    systemctl enable cron --now || true
    CRON_JOB="0 19 * * 4 /usr/bin/apt update && env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get full-upgrade -yq >> /var/log/apt_autoupdate.log 2>&1"
    
    (crontab -l 2>/dev/null || true) | grep -Fv "$CRON_JOB" > /tmp/cron_tmp || true
    echo "$CRON_JOB" >> /tmp/cron_tmp
    crontab /tmp/cron_tmp
    rm -f /tmp/cron_tmp
}
run_step "Настройка автоматических обновлений в Cron" setup_cron

# === 8. Gruvbox Rainbow preset для Starship ===
setup_starship_preset() {
    mkdir -p ~/.config
    /usr/local/bin/starship preset gruvbox-rainbow --force -o ~/.config/starship.toml
}
run_step "Применение темы Gruvbox Rainbow для Starship" setup_starship_preset

# === 9. Обновление плагинов Zinit ===
update_zinit_plugins() {
    ZINIT_HOME="${HOME}/.local/share/zinit"
    if [ ! -f "$ZINIT_HOME/zinit.zsh" ]; then
        mkdir -p "$ZINIT_HOME"
        git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
    fi
    zsh -c "source $ZINIT_HOME/zinit.zsh && zinit self-update -q && zinit update --all -q" || true
    return 0
}
run_step "Обновление плагинов Zsh" update_zinit_plugins

# === 10. Завершение работы ===
echo ""
echo "================================================="
echo " 🎉 Настройка успешно завершена!"
echo " Для повторного запуска используйте команду: scu"
echo "================================================="
echo ""

tput cnorm 2>/dev/null || true

if command -v zsh >/dev/null 2>&1; then
    exec zsh -l
else
    echo "zsh не найден, запустите его вручную."
fi
