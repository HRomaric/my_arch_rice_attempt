# Powerlevel10k instant prompt (keep at the top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""            # prompt comes from Powerlevel10k below
plugins=(git sudo)
source "$ZSH/oh-my-zsh.sh"

typeset -U path         # no duplicate PATH entries
path=("$HOME/.local/bin" "$HOME/.npm-global/bin" "$HOME/.local/share/coursier/bin" $path)
export EDITOR=code

# Powerlevel10k (Arch: zsh-theme-powerlevel10k-git, Debian: cloned by install.sh — same path)
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Machine-specific stuff (not in git)
[[ ! -f ~/.zshrc.local ]] || source ~/.zshrc.local
