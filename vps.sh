#!/usr/bin/env bash
set -e

# === Функция вращающегося спиннера ===
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    # Скрываем курсор в терминале
    tput civis
    
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    
    # Возвращаем курсор обратно
    tput cnorm
}

# === Функция выполнения каждого этапа ===
run_step() {
    local title="$1"
    shift
    
    echo -n " $title... "
    
    # Запускаем команду в фоновом режиме
    "$@" >/dev/null 2>&1 &
    local cmd_pid=$!
    
    # Запускаем анимацию спиннера
    show_spinner $cmd_pid
    
    # Ждем завершения команды и получаем ее код ответа
    wait $cmd_pid
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo -e "\r\033[K✅ $title — готово"
    else
        echo -e "\r\033[K❌ $title — ошибка"
        return 1
    fi
}

echo -e "\n🚀 Начинаем настройку сервера...\n"

# === 1. Обновление системы и базовый набор пакетов ===
run_step "Обновление списка пакетов" apt update
run_step "Обновление системы (full-upgrade)" apt full-upgrade -y
run_step "Установка базовых утилит и шрифтов" apt install -y micro sudo unzip autojump fontconfig ufw nano git wget curl zstd zsh net-tools cron socat btop fzf zoxide fonts-font-awesome

# === 2. Настройка часового пояса UTC ===
run_step "Настройка часового пояса UTC" timedatectl set-timezone UTC

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
        chsh -s "$(command -v zsh)"
    fi
}
run_step "Установка Zsh по умолчанию" set_zsh_default

# === 6. Генерация ~/.zshrc ===
generate_zshrc() {
    mkdir -p ~/.local/share/zsh ~/.local/share/zinit
    touch ~/.local/share/zsh/chpwd-recent-dirs

    cat > ~/.zshrc << 'EOF'
export PATH="$HOME/.local/bin:$PATH"

# Инициализация работы с историей директорий
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs

# Путь для Zinit
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit"
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
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

# Цвета completion-меню и case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '[%d]'

# Алиасы
alias ls='ls --color=auto'
alias rr='/usr/local/bin/remnawave_reverse'
alias rwe="docker exec -it remnawave cli"
alias up="sudo apt update && sudo apt full-upgrade -y"
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
    systemctl enable cron --now
    CRON_JOB="0 19 * * 4 /usr/bin/apt update && /usr/bin/apt full-upgrade -y >> /var/log/apt_autoupdate.log 2>&1"
    (crontab -l 2>/dev/null | grep -Fv "$CRON_JOB"; echo "$CRON_JOB") | crontab -
}
run_step "Настройка автоматических обновлений в Cron" setup_cron

# === 8. Gruvbox Rainbow preset для Starship ===
setup_starship_preset() {
    mkdir -p ~/.config
    starship preset gruvbox-rainbow --force -o ~/.config/starship.toml
}
run_step "Применение темы Gruvbox Rainbow для Starship" setup_starship_preset

# === 9. Обновление плагинов Zinit при запуске скрипта ===
update_zinit() {
    if [ -f "$HOME/.local/share/zinit/zinit.zsh" ]; then
        zsh -c "source $HOME/.local/share/zinit/zinit.zsh && zinit self-update -q && zinit update --all -q"
    fi
}
run_step "Обновление плагинов Zsh и Zinit" update_zinit

# === 10. Завершение работы ===
echo ""
echo "================================================="
echo " 🎉 Настройка успешно завершена!"
echo " Для повторного запуска используйте команду: scu"
echo "================================================="
echo ""
echo "Переключаюсь в zsh..."

if command -v zsh >/dev/null 2>&1; then
    exec zsh -l
else
    echo "zsh не найден, запустите его вручную."
fi
