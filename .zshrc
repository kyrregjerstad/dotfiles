export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

zstyle ':omz:update' mode reminder # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(zsh-nvm git zsh-autosuggestions)

source $ZSH/oh-my-zsh.sh

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
alias v='nvim'

# %h -- commit hash
# %an -- author name
# %ar -- commit time
# %D -- ref names
# %s -- commit message
# %n -- new line

alias gb='git branch'

alias gco='git checkout'
alias gi='git init'
alias gcl='git clone'

alias l='eza -lah'
alias ls=eza
alias rm=trash # moves files to trash instead of deleting them
alias p=pnpm
alias refresh='source ~/.zshrc'
alias t=turbo

alias y='yarn'
alias yw='yarn workspace'
alias ywd='yarn workspace dashboard'
alias ywc='yarn workspace candidate'
alias ywt='yarn workspace tests'
alias lz='lazygit'

export NODE_OPTIONS="--max-old-space-size=8096"
export BUN_INSTALL="$HOME/.bun"
export LDFLAGS="-L/opt/homebrew/opt/jpeg/lib"
export CPPFLAGS="-I/opt/homebrew/opt/jpeg/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/jpeg/lib/pkgconfig"
export PYTHON=/opt/homebrew/bin/python3

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
*":$PNPM_HOME:"*) ;;
*) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

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
eval "$(zoxide init --cmd cd zsh)"

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
