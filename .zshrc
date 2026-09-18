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
alias rwe="docker exec -it remnawave cli"
alias up="sudo apt update && sudo apt full-upgrade -y"
alias upw="up && rwu"
alias mi="micro"
alias mzh="cd && mi .zshrc"
alias szh="cd && source .zshrc"
alias cl="clear"
alias mds="motd-set"

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

# Настроика истории
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
