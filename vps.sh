#!/usr/bin/env bash
set -e

# === 1. Обновление системы и базовый набор пакетов ===
apt update && apt full-upgrade -y
apt install -y micro sudo unzip autojump fontconfig ufw nano git wget curl zstd zsh net-tools cron socat btop fzf zoxide fonts-font-awesome

# === 2. Настройка часового пояса UTC ===
timedatectl set-timezone UTC

# === 3. Настройка micro ===
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

# === 4. Установка Starship и шрифтов JetBrainsMono Nerd Font (с проверкой) ===
curl -sS https://starship.rs/install.sh | sh -s -- -y >/dev/null 2>&1

if [ ! -d "$HOME/.local/share/fonts/JetBrainsMono" ]; then
    echo "Шрифты JetBrainsMono не найдены. Устанавливаем..."
    cd /tmp
    wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O JetBrainsMono.zip
    unzip -o JetBrainsMono.zip -d JetBrainsMono
    mkdir -p ~/.local/share/fonts/JetBrainsMono
    mv JetBrainsMono/* ~/.local/share/fonts/JetBrainsMono/
    fc-cache -fv
    rm -rf JetBrainsMono JetBrainsMono.zip
    cd ~
else
    echo "Шрифты JetBrainsMono уже установлены, пропускаем скачивание."
fi

# === 5. Включение zsh по умолчанию ===
if command -v zsh >/dev/null 2>&1; then
    chsh -s "$(command -v zsh)"
fi

# === 6. Генерация ~/.zshrc ===
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

# Autojump
zinit ice depth=1
zinit light wting/autojump

# Синтаксическая подсветка команд
zinit ice depth=1
zinit light zsh-users/zsh-syntax-highlighting

# Улучшенное автодополнение
zinit ice depth=1
zinit light zsh-users/zsh-completions

# Autosuggestions на основе истории
zinit ice depth=1
zinit light zsh-users/zsh-autosuggestions

# Автозавершение
zinit ice depth=1
zinit light marlonrichert/zsh-autocomplete

# FZF
zinit ice depth=1
zinit light junegunn/fzf

# FZF-Tab
zinit ice depth=1
zinit light Aloxaf/fzf-tab

# Git aliases (oh-my-zsh)
zinit snippet OMZ::plugins/git/git.plugin.zsh

# Zoxide
zinit ice depth=1
zinit light ajeetdsouza/zoxide

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
# Перезапуск контейнера
rwr() {
  if cd /opt/remnanode 2>/dev/null || cd /opt/remnawave 2>/dev/null; then
    docker compose down && docker compose up -d && docker compose logs -f -t
  else
    echo "Ошибка: ни одна из папок (/opt/remnanode или /opt/remnawave) не найдена."
    return 1
  fi
}

# Пулл контейнера
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

# === 7. Настройка задач Cron ===
systemctl enable cron --now
CRON_JOB="0 19 * * 4 /usr/bin/apt update && /usr/bin/apt full-upgrade -y >> /var/log/apt_autoupdate.log 2>&1"
(crontab -l 2>/dev/null | grep -Fv "$CRON_JOB"; echo "$CRON_JOB") | crontab -

# === 8. Gruvbox Rainbow preset для Starship ===
mkdir -p ~/.config
starship preset gruvbox-rainbow --force -o ~/.config/starship.toml

# === 9. Обновление плагинов Zinit при запуске скрипта ===
if [ -f "$HOME/.local/share/zinit/zinit.zsh" ]; then
    echo "Обновляем плагины Zsh и Zinit..."
    zsh -c "source $HOME/.local/share/zinit/zinit.zsh && zinit self-update -q && zinit update --all -q" >/dev/null 2>&1 || true
fi

# === 10. Завершение работы ===
echo ""
echo "================================================="
echo " Настройка завершена!"
echo " Для повторного запуска или обновления скрипта"
echo " в будущем вы можете использовать команду: scu"
echo "================================================="
echo ""
echo "Переключаюсь в zsh..."

if command -v zsh >/dev/null 2>&1; then
    exec zsh -l
else
    echo "zsh не найден, запусти его вручную после установки."
fi
