setopt auto_cd
setopt no_clobber
setopt hist_ignore_all_dups
setopt interactive_comments

# cmux rewrites its Claude CLI shim on the first prompt. With no_clobber set,
# zsh refuses the integration's > redirection when the shim file already exists
# and prints: `_cmux_install_cli_command_shim:13: file exists: .../claude`.
# Keep no_clobber for normal interactive use, but allow clobber inside that shim
# installer only.
if (( $+functions[_cmux_install_cli_command_shim] )) && (( ! $+functions[_cmux_install_cli_command_shim_no_clobber_safe] )); then
    functions[_cmux_install_cli_command_shim_no_clobber_safe]=$functions[_cmux_install_cli_command_shim]
    _cmux_install_cli_command_shim() {
        setopt local_options clobber
        _cmux_install_cli_command_shim_no_clobber_safe "$@"
    }
fi

# Completions
[[ -n "$HOMEBREW_PREFIX" ]] && fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit -C

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
alias gPnv='git push --no-verify'

alias ghid='gh issue develop'

bbmb() {
	local branch run_url run_id
	branch=$(git branch --show-current) || return
	[[ -n "$branch" ]] || { echo "bbmb: not on a branch" >&2; return 1; }
	git push -u origin "$branch" || return
	run_url=$(gh workflow run build-manual.yaml --ref "$branch" -f branch="$branch" -f fast_pkg=1) || return
	[[ -n "$run_url" ]] || { echo "bbmb: GitHub did not return a run URL" >&2; return 1; }
	run_id=${run_url##*/}

	echo "Build started: $run_url"
	(
		if gh run watch "$run_id" --exit-status --compact >/dev/null 2>&1; then
			terminal-notifier -title "Buttons build succeeded" -message "$branch" -open "$run_url"
		else
			terminal-notifier -title "Buttons build failed" -message "$branch" -open "$run_url"
		fi
	) &!
}

alias v='nvim'
alias nv='NVIM_APPNAME=nvim-vanilla nvim'

alias gb='git branch'
alias gco='git checkout'
alias m='git checkout main'
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

alias bb='cd ~/Projects/bitfocus-buttons/'
alias bkill="$HOME/.local/bin/kill-buttons"

alias cdr='cd $(git rev-parse --show-toplevel)'

alias nz='nvim ~/.zshrc'

alias lg='lazygit'
alias ld='lazydocker'
alias z='zellij'
alias zj='zellij attach "$(zellij list-sessions -n -r -s | head -1)" 2>/dev/null || zellij'
alias oc='opencode'
alias cl='claude'
alias cld='claude --dangerously-skip-permissions'
alias cldc='claude --dangerously-skip-permissions --continue'

# Worktrunk
alias ws='wt switch'
alias wsc='wt switch --create'


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

_run() {
  local scripts
  if [[ -f package.json ]]; then
    if command -v node &>/dev/null; then
      scripts=(${(f)"$(node -e "try{const p=require('./package.json');console.log(Object.keys(p.scripts||{}).join('\n'))}catch{}")"})
    else
      scripts=(${(f)"$(command rg -o '^\s+"([^"]+)":' -r '$1' package.json 2>/dev/null)"})
    fi
    compadd -a scripts
  fi
}
compdef _run run

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

alias c='zed .'
alias d='run dev'
alias build='run build'
alias check='run check'

alias -g NE='2>/dev/null'
alias -g JQ=' | jq'
alias -g C=' | clip'
alias -g P='paste | '

alias -g ta='tmux attach'

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
[ -f ~/.config/zsh/newapp.zsh ] && source ~/.config/zsh/newapp.zsh

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

# Cache generated shell integrations until their executable changes.
_zsh_cached_init() {
	local name="$1" executable="$2"
	shift 2

	local executable_path="${commands[$executable]}"
	[[ -n "$executable_path" ]] || return

	local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
	local cache_file="$cache_dir/$name.zsh"
	local cache_tmp="$cache_file.$$"
	[[ -d "$cache_dir" ]] || command mkdir -p "$cache_dir"

	if [[ ! -s "$cache_file" || "$executable_path" -nt "$cache_file" ]]; then
		if "$executable_path" "$@" >| "$cache_tmp"; then
			command mv -f "$cache_tmp" "$cache_file"
		else
			command rm -f "$cache_tmp"
		fi
	fi

	[[ -s "$cache_file" ]] && source "$cache_file"
}

_zsh_cached_init fzf fzf --zsh

if [[ "$CLAUDECODE" != "1" ]]; then
	_zsh_cached_init zoxide zoxide init --cmd cd zsh
fi

_zsh_cached_init starship starship init zsh

if [[ "$TERM_PROGRAM" != "WarpTerminal" ]]; then
	_zsh_cached_init atuin atuin init zsh
fi

_zsh_cached_init direnv direnv hook zsh

# Must be last
[[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
# Arch: use /usr/share/ paths
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

true

_zsh_cached_init worktrunk wt config shell init zsh
unfunction _zsh_cached_init

export PATH="$HOME/.cargo/bin:$PATH"

# sentry
fpath=("/Users/k/.local/share/zsh/site-functions" $fpath)

# fnm must be initialized after Vite+ PATH changes so `fnm use` wins over Vite+'s bundled Node.
command -v fnm &>/dev/null && eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell zsh)"

# Unity CLI
. "/Users/k/.unity/env"
