# Brew (macOS only — Arch uses pacman)
if [[ -d /opt/homebrew ]]; then
    export HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -d /usr/local/Homebrew ]]; then
    export HOMEBREW_PREFIX="/usr/local"
fi

if [[ -n "$HOMEBREW_PREFIX" ]]; then
    export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
    export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX"
    export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
    export MANPATH="$HOMEBREW_PREFIX/share/man:${MANPATH:-}"
    export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"

    export LDFLAGS="-L$HOMEBREW_PREFIX/opt/jpeg/lib"
    export CPPFLAGS="-I$HOMEBREW_PREFIX/opt/jpeg/include"
    export PKG_CONFIG_PATH="$HOMEBREW_PREFIX/opt/jpeg/lib/pkgconfig"
fi

export NODE_OPTIONS="--max-old-space-size=8096"
export BUN_INSTALL="$HOME/.bun"
export XDG_CONFIG_HOME="$HOME/.config"
export MANPAGER="nvim +Man!"
export EDITOR=nvim
export HUSKY=0
export TMPDIR=/tmp

case "$(uname)" in
Darwin)
    export PYTHON=/opt/homebrew/bin/python3
    export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
    export PNPM_HOME="$HOME/Library/pnpm"
    ;;
Linux)
    export PYTHON=/usr/bin/python3
    export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
    export PNPM_HOME="$HOME/.local/share/pnpm"
    ;;
esac

case ":$PATH:" in
*":$PNPM_HOME:"*) ;;
*) export PATH="$PNPM_HOME:$PATH" ;;
esac

export PATH="$BUN_INSTALL/bin:$PATH"
export PATH="$HOME/.console-ninja/.bin:$PATH"
export PATH="$HOME/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
