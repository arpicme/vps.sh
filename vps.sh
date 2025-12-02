#!/usr/bin/env bash
set -e

# === 1. Обновление системы и базовый набор пакетов ===
apt update && apt full-upgrade -y
apt install -y micro sudo unzip autojump fontconfig ufw nano git wget curl zstd zsh net-tools cron socat btop fzf zoxide fonts-font-awesome

# === 2. Настройка micro ===
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

# === 3. Установка Starship и шрифтов JetBrainsMono Nerd Font ===
curl -sS https://starship.rs/install.sh | sh -s -- -y

cd /tmp
wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O JetBrainsMono.zip
unzip -o JetBrainsMono.zip -d JetBrainsMono
mkdir -p ~/.local/share/fonts
mv JetBrainsMono/* ~/.local/share/fonts/
fc-cache -fv
rm -rf JetBrainsMono JetBrainsMono.zip
cd ~

# === 4. Включение zsh по умолчанию ===
if command -v zsh >/dev/null 2>&1; then
    chsh -s "$(command -v zsh)"
fi

# === 5. Генерация ~/.zshrc ===
cat > ~/.zshrc << 'EOF'
export PATH="$HOME/.local/bin:$PATH"

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
alias drd="docker compose down && docker compose up -d && docker compose logs -f -t"
alias upf="apt update && apt full-upgrade -y"
alias up="apt update -y"
alias mi="micro"
alias cl="clear"
alias mds="motd-set"

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

# === 6. Gruvbox Rainbow preset для Starship ===
mkdir -p ~/.config
starship preset gruvbox-rainbow -o ~/.config/starship.toml

echo "Готово. Переключаюсь в zsh..."

# === 7. Применяем zsh прямо сейчас ===
if command -v zsh >/dev/null 2>&1; then
    exec zsh -l
else
    echo "zsh не найден, запусти его вручную после установки."
fi
