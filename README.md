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
