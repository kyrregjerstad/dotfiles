export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

zstyle ':omz:update' mode reminder # just remind me to update when it's time

plugins=(git)

source $ZSH/oh-my-zsh.sh
setopt auto_cd
hash -d p=~/Projects

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

# custom cursor launcher
function c() {
    if [ -d "$1" ]; then
        open -a "Cursor" "$1"
    else
        open -a "Cursor" .
    fi
}

# Custom aliases
## git
alias g=git
alias gs='git status --short'
alias gd="git diff --output-indicator-new=' ' --output-indicator-old=' ' "

alias ga='git add'
alias gap='git add --patch'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend --no-edit'

alias gP='git push'
alias gp='git pull'
alias gl='git log --graph --all --pretty=format:"%C(magenta)%h %C(white) %an  %ar%C(blue)  %D%n%s%n"'
# %h -- commit hash
# %an -- author name
# %ar -- commit time
# %D -- ref names
# %s -- commit message
# %n -- new line

# gh
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
alias rm=trash # moves files to trash instead of deleting them
alias p=pnpm
alias refresh='source ~/.zshrc'
alias t=turbo

# cd to root of git repo
alias cdr='cd $(git rev-parse --show-toplevel)'

alias lz='lazygit'
alias z='zellij'

# Vi mode
bindkey -v

# Reduce key delay when switching modes (optional but recommended)
export KEYTIMEOUT=1

# Clean up any existing starship hooks before reinitializing
if typeset -f starship_zle-keymap-select > /dev/null; then
  # Starship is already loaded, skip initialization
  :
else
  eval "$(starship init zsh)"
fi
# Vi mode cursor shape indicator
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'  # Block cursor for normal mode
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ ${KEYMAP} = '' ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'  # Beam cursor for insert mode
  fi
}
zle -N zle-keymap-select

# Start with beam cursor on each new prompt
function zle-line-init {
  echo -ne '\e[5 q'
}
zle -N zle-line-init

# Load starship only once to avoid function nesting
type starship_zle-keymap-select >/dev/null || \
  {
    eval "$(starship init zsh)"
  }

# dump brewfile and add to git
alias brewup='cd ~/dotfiles/brew && brew bundle dump --force && git add Brewfile'

export NODE_OPTIONS="--max-old-space-size=8096"
export BUN_INSTALL="$HOME/.bun"
export LDFLAGS="-L/opt/homebrew/opt/jpeg/lib"
export CPPFLAGS="-I/opt/homebrew/opt/jpeg/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/jpeg/lib/pkgconfig"
export XDG_CONFIG_HOME="$HOME/.config"
export MANPAGER="nvim +Man!"
export PYTHON=/opt/homebrew/bin/python3
export EDITOR=nvim

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
*":$PNPM_HOME:"*) ;;
*) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end


eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell zsh)"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export PATH="$BUN_INSTALL/bin:$PATH"

brew() {
    unset -f brew
    if [ "$(arch)" = "arm64" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    brew "$@"
}

PATH=~/.console-ninja/.bin:$PATH
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

source <(fzf --zsh)

# disable zodxide for claude-code
# https://github.com/anthropics/claude-code/issues/2632
if [[ "$CLAUDECODE" != "1" ]]; then
    eval "$(zoxide init --cmd cd zsh)"
fi


bun() {
    unset -f bun
    [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    bun "$@"
}
#compdef gt
###-begin-gt-completions-###
#
# yargs command completion script
#
# Installation: gt completion >> ~/.zshrc
#    or gt completion >> ~/.zprofile on OSX.
#
_gt_yargs_completions() {
    local reply
    local si=$IFS
    IFS=$'
' reply=($(COMP_CWORD="$((CURRENT - 1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" gt --get-yargs-completions "${words[@]}"))
    IFS=$si
    _describe 'values' reply
}
compdef _gt_yargs_completions gt
###-end-gt-completions-###

export PATH="$HOME/bin:$PATH"
export PATH=$PATH:$HOME/go/bin

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/opt/homebrew/share/google-cloud-sdk/path.zsh.inc' ]; then . '/opt/homebrew/share/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc' ]; then . '/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc'; fi


# Only initialize starship if running in Ghostty
if [[ "$TERM_PROGRAM" == "ghostty" ]]; then
    eval "$(starship init zsh)"
fi

export PATH="$HOME/.local/bin:$PATH"

echo 'eval "$(atuin init zsh)"' >> ~/.zshrc
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
eval "$(atuin init zsh)"
