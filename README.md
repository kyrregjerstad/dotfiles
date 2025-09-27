# My dotfiles

This directory contains the dotfiles for my system

## Requirements

Ensure you have the following installed on your system

### Git

```
brew install git
```

### Stow

```
brew install stow
```

## Installation

First, check out the dotfiles repo in your $HOME directory using git

```zsh
git clone git@github.com/kyrregjerstad/dotfiles.git
cd dotfiles
```

then use GNU stow to create symlinks

```zsh
stow .
```

The directory structure in the dotfiles directory needs to be the same as in the parent root dir. `~/config/123/settings.abc` will be `~/dotfiles/config/123/settings.abc`

## Adding a new config file to your stow dotfiles repo

**Step 1: Move the existing file into your dotfiles repo**
```bash
# Navigate to your dotfiles directory
cd ~/dotfiles

# Create the directory structure that mirrors where the file lives
mkdir -p "path/to/config/directory"

# Move the actual file from your system into the dotfiles repo
mv "/actual/path/to/configfile" "path/to/config/directory/"
```

**Step 2: Create the symlink with stow**
```bash
# From your dotfiles directory
stow .
```

**Key points:**
- Always **move** the real file into your dotfiles repo (don't copy)
- The directory structure in dotfiles must exactly match the target location
- Run `stow .` to create the symlinks
- The symlink will point from the original location back to your dotfiles repo

**Verification:**
```bash
# Check that the symlink was created correctly
ls -la "/path/to/original/location/"
# Should show a symlink pointing back to your dotfiles repo
```

This ensures your config files live in your dotfiles repo and are symlinked to where applications expect them.
