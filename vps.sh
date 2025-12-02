#!/bin/bash

# VPS Setup Script
# Автоматическая настройка сервера с ZSH, Starship, Micro и всеми необходимыми инструментами
# Автор: arpicme
# Описание: Обновление сервера, установка пакетов, настройка ZSH с плагинами и шрифтами

set -e  # Выход при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_section() {
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
}

# ========================================
# Шаг 1: Обновление системы и установка базовых пакетов
# ========================================
print_section "Шаг 1: Обновление системы и установка базовых пакетов"

print_status "Обновление репозиториев..."
apt update

print_status "Полное обновление системы..."
apt full-upgrade -y

print_status "Установка базовых пакетов..."
apt install -y \
    micro \
    sudo \
    unzip \
    autojump \
    fontconfig \
    ufw \
    nano \
    git \
    wget \
    curl \
    zstd \
    zsh \
    net-tools \
    cron \
    socat \
    btop

print_success "Базовые пакеты установлены"

# ========================================
# Шаг 2: Настройка Micro
# ========================================
print_section "Шаг 2: Настройка Micro"

print_status "Создание директории конфигурации Micro..."
mkdir -p ~/.config/micro

print_status "Создание bindings.json..."
cat > ~/.config/micro/bindings.json <<'EOF'
{
"Alt-/": "lua:comment.comment",
"CtrlUnderscore": "lua:comment.comment",
"Ctrl-c": "Copy",
"Ctrl-v": "Paste"
}
EOF

print_status "Создание settings.json..."
cat > ~/.config/micro/settings.json <<'EOF'
{
"clipboard": "terminal"
}
EOF

print_success "Micro настроен"

# ========================================
# Шаг 3: Установка ZSH, шрифтов и зависимостей
# ========================================
print_section "Шаг 3: Установка ZSH, шрифтов и зависимостей"

print_status "Установка дополнительных пакетов для ZSH..."
apt update
apt install -y \
    zsh \
    git \
    curl \
    wget \
    unzip \
    fontconfig \
    fzf \
    micro \
    autojump \
    zoxide \
    fonts-font-awesome

print_status "Установка Starship..."
curl -sS https://starship.rs/install.sh | sh -s -- -y

print_status "Скачивание и установка JetBrains Mono Nerd Font..."
cd /tmp

if [ -f JetBrainsMono.zip ]; then
    rm JetBrainsMono.zip
fi

wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O JetBrainsMono.zip

print_status "Распаковка шрифтов..."
unzip -o JetBrainsMono.zip -d JetBrainsMono

print_status "Создание директории шрифтов..."
mkdir -p ~/.local/share/fonts

print_status "Копирование шрифтов..."
mv JetBrainsMono/* ~/.local/share/fonts/

print_status "Обновление кэша шрифтов..."
fc-cache -fv

print_status "Очистка временных файлов..."
rm -rf JetBrainsMono JetBrainsMono.zip

cd ~

print_success "ZSH, шрифты и зависимости установлены"

# ========================================
# Шаг 4: Установка ZSH как оболочки по умолчанию
# ========================================
print_section "Шаг 4: Установка ZSH как оболочки по умолчанию"

if which zsh > /dev/null; then
    print_status "ZSH найден, устанавливаем как оболочку по умолчанию..."
    chsh -s $(which zsh)
    print_success "ZSH установлен как оболочка по умолчанию"
else
    print_error "ZSH не найден!"
    exit 1
fi

# ========================================
# Шаг 5: Создание и настройка .zshrc
# ========================================
print_section "Шаг 5: Создание и настройка .zshrc"

print_status "Создание файла .zshrc..."
touch ~/.zshrc

print_status "Заполнение .zshrc конфигурацией..."
cat > ~/.zshrc <<'EOF'
export PATH="$HOME/.local/bin:$PATH"

# Функция проверки наличия ZINIT и установки его в случае отсутствия
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit"
if [ ! -d $ZINIT_HOME ]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Плагины

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

# Поиск с нечетким соответствием по файлам и истории
zinit ice depth=1
zinit light junegunn/fzf

# Дополнение к FZF — супер крутая работа Tab/Completion
zinit ice depth=1
zinit light Aloxaf/fzf-tab

# Git aliases и улучшения (от oh-my-zsh)
zinit snippet OMZ::plugins/git/git.plugin.zsh

# Продвинутый cd (zoxide)
zinit ice depth=1
zinit light ajeetdsouza/zoxide

# Меню history по Ctrl-R (через fzf)
bindkey '^R' fzf-history-widget

# Цвета completion-меню и поддержка case-insensitive
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
HISTSIZE=5000                # Количество команд в истории (можно увеличить)
SAVEHIST=5000                # Количество команд, сохраняемых в истории между сессиями shell
HISTFILE=~/.zsh_history      # Файл истории

# Настройки истории без дубликатов и с мощным поиском
setopt append_history        # Каждая сессия дописывает в историю, не перезаписывает её
setopt share_history         # Общая история между всеми окнами/сессиями
setopt inc_append_history    # Мгновенно сохранять команду в файл истории после выполнения
setopt hist_ignore_all_dups  # Не хранить одинаковые команды
setopt hist_save_no_dups     # Не сохранять дубликаты при выходе
setopt hist_find_no_dups     # Исключать повторы при поиске по истории
setopt hist_ignore_dups      # Не показывать дубликаты новой команды
setopt hist_ignore_space     # Команда с пробелом в начале не попадет в историю (для приватного)
setopt hist_reduce_blanks    # Удалять лишние пробелы из команд
setopt extended_history      # Время выполнения каждой команды

# Улучшаем поиск: ^P/^N — только по совпадающим префиксам
bindkey '^P' history-search-backward
bindkey '^N' history-search-forward

# Использование Starship в качестве промта
eval "$(starship init zsh)"
EOF

print_success ".zshrc создан и заполнен"

# ========================================
# Шаг 6: Применение изменений .zshrc
# ========================================
print_section "Шаг 6: Применение изменений"

print_status "Загрузка конфигурации .zshrc..."
source ~/.zshrc

print_success "Конфигурация загружена"

# ========================================
# Шаг 7: Установка Starship темы
# ========================================
print_section "Шаг 7: Установка Starship темы"

print_status "Установка Gruvbox Rainbow темы для Starship..."
mkdir -p ~/.config
starship preset gruvbox-rainbow -o ~/.config/starship.toml

print_success "Starship тема установлена"

# ========================================
# Завершение
# ========================================
print_section "Завершение"

print_success "✓ Все шаги выполнены успешно!"
echo -e "\n${GREEN}Конфигурация сервера завершена!${NC}"
echo -e "\n${YELLOW}Установленные компоненты:${NC}"
echo "  • Micro (редактор) ✓"
echo "  • ZSH (оболочка) ✓"
echo "  • Starship (промт) ✓"
echo "  • JetBrains Mono Nerd Font ✓"
echo "  • ZINIT (менеджер плагинов) ✓"
echo "  • ZSH плагины (fzf, syntax-highlighting, autosuggestions и др.) ✓"
echo "  • Базовые утилиты (git, wget, curl, btop и др.) ✓"

echo -e "\n${YELLOW}Полезные алиасы:${NC}"
echo "  • mi - открыть micro"
echo "  • cl - очистить терминал"
echo "  • upf - обновить систему полностью"
echo "  • up - обновить репозитории"
echo "  • drd - перезапустить docker compose с логами"
echo "  • rr - запустить remnawave_reverse"

echo -e "\n${YELLOW}Горячие клавиши ZSH:${NC}"
echo "  • Ctrl+R - поиск по истории (fzf)"
echo "  • Ctrl+P - поиск назад по истории (по префиксу)"
echo "  • Ctrl+N - поиск вперед по истории (по префиксу)"
echo "  • Alt+/ - комментарий в Micro"

echo -e "\n${BLUE}Для начала новой сессии ZSH выполните:${NC}"
echo "  exec zsh"
echo -e "\n${GREEN}Спасибо за использование VPS Setup Script!${NC}\n"
