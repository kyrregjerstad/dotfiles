setopt auto_cd
setopt no_clobber
setopt hist_ignore_all_dups
setopt interactive_comments

# Completions
[[ -n "$HOMEBREW_PREFIX" ]] && fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit

hash -d p=~/Projects

# Clipboard abstraction
if command -v pbcopy &>/dev/null; then
    clip() { pbcopy "$@"; }
    paste() { pbpaste "$@"; }
elif command -v wl-copy &>/dev/null; then
    clip() { wl-copy "$@"; }
    paste() { wl-paste "$@"; }
elif command -v xclip &>/dev/null; then
    clip() { xclip -selection clipboard "$@"; }
    paste() { xclip -selection clipboard -o "$@"; }
fi

# Open abstraction
if command -v open &>/dev/null; then
    opener() { open "$@"; }
elif command -v xdg-open &>/dev/null; then
    opener() { xdg-open "$@"; }
fi

function my-ip() {
    curl ifconfig.me
}

function clonedev() {
    if [ -z "$1" ]; then
        echo "Usage: clonedev <git-repo-url>"
        return 1
    fi

    git clone "$1" || return 1
    REPO_NAME=$(basename "$1" .git)
    cd "$REPO_NAME" || return 1
    code .
    open "raycast://customWindowManagementCommand?&name=dev%20terminal"
    pnpm install -r || return 1
    echo "Repository setup completed. To start the dev server, run: pnpm dev"
}

function new-dev-terminal() {
    open "warp://launch/~/.warp/launch_configurations/dev-server.yaml"
}

function take {
    mkdir -p $1
    cd $1
}

newbranch() {
    local branch="${1:-$(paste)}"
    git checkout main && git pull && git checkout -b "$branch"
}
alias nb='newbranch'

function c() {
    if [ -d "$1" ]; then
        opener "$1"
    else
        opener .
    fi
}

# Git
alias g=git
alias gs='git status --short'
alias gd='git diff'

alias ga='git add'
alias gap='git add --patch'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend --no-edit'

gP() { git push -u origin "$(git branch --show-current)"; }
alias gp='git pull'
alias gl='git log --graph --all --pretty=format:"%C(magenta)%h %C(white) %an  %ar%C(blue)  %D%n%s%n"'

alias ghid='gh issue develop'

alias v='nvim'

alias gb='git branch'
alias gco='git checkout'
alias gcn='git checkout -b'
alias gcob='git checkout $(git branch --all | rg -v HEAD | sed "s/remotes\/origin\///" | sed "s/^\* //" | sort -u | fzf --reverse --preview "git log --oneline --color=always {}" --preview-window=right:60%)'
alias gi='git init'
alias gcl='git clone'

alias l='eza -lah'
alias ls=eza
alias cat=bat
command -v trash &>/dev/null && alias rm=trash
command -v trash-put &>/dev/null && alias rm=trash-put
alias p=pnpm
alias refresh='source ~/.zshrc'
alias t=turbo
alias b=bun
alias du=dust
alias df=duf

alias cdr='cd $(git rev-parse --show-toplevel)'

alias nz='nvim ~/.zshrc'

alias lz='lazygit'
alias ld='lazydocker'
alias z='zellij'
alias cl='claude'
alias cld='claude --dangerously-skip-permissions'

# Yazi with cd-on-exit
y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    command rm -f -- "$tmp"
}

pm() {
  if [[ -f "bun.lockb" || -f "bun.lock" ]]; then
    echo "bun"
  elif [[ -f "pnpm-lock.yaml" ]]; then
    echo "pnpm"
  elif [[ -f "yarn.lock" ]]; then
    echo "yarn"
  elif [[ -f "package-lock.json" || -f "package.json" ]]; then
    echo "npm"
  else
    echo ""
  fi
}

run() {
  local mgr=$(pm)
  if [[ -z "$mgr" ]]; then
    echo "No package manager detected"
    return 1
  fi
  $mgr run "$@"
}

add() {
  local mgr=$(pm)
  if [[ -z "$mgr" ]]; then
    echo "No package manager detected"
    return 1
  fi
  if [[ "$mgr" == "npm" ]]; then
    npm install "$@"
  else
    $mgr add "$@"
  fi
}

alias d='run dev'
alias build='run build'
alias check='run check'

alias -g NE='2>/dev/null'
alias -g JQ=' | jq'
alias -g C=' | clip'
alias -g P='paste | '

# Vi mode
bindkey -v
export KEYTIMEOUT=1

alias -g ...='../..'
alias -g ....='../../..'
alias -g .....='../../../..'

function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ ${KEYMAP} = '' ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select

function zle-line-init {
  echo -ne '\e[5 q'
}
zle -N zle-line-init

[[ -n "$HOMEBREW_PREFIX" ]] && alias brewup='cd ~/dotfiles/brew && brew bundle dump --force && git add Brewfile'

[ -f ~/.secrets ] && source ~/.secrets

command -v fnm &>/dev/null && eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell zsh)"

# Bun completions (lazy)
bun() {
    unset -f bun
    [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
    bun "$@"
}

# gt completions
if command -v gt &>/dev/null; then
    _gt_yargs_completions() {
        local reply
        local si=$IFS
        IFS=$'
' reply=($(COMP_CWORD="$((CURRENT - 1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" gt --get-yargs-completions "${words[@]}"))
        IFS=$si
        _describe 'values' reply
    }
    compdef _gt_yargs_completions gt
fi

command -v fzf &>/dev/null && source <(fzf --zsh)

if [[ "$CLAUDECODE" != "1" ]]; then
    command -v zoxide &>/dev/null && eval "$(zoxide init --cmd cd zsh)"
fi

command -v starship &>/dev/null && eval "$(starship init zsh)"

if [[ "$TERM_PROGRAM" != "WarpTerminal" ]]; then
    command -v atuin &>/dev/null && eval "$(atuin init zsh)"
fi

command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# Must be last
[[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
# Arch: use /usr/share/ paths
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

true
