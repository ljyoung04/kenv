# Enable the subsequent settings only in interactive sessions
case $- in
  *i*) ;;
    *) return;;
esac

# ──────────────────────────────────────────────────────────────────────────────
# oh-my-bash
# ──────────────────────────────────────────────────────────────────────────────
export OSH='/opt/oh-my-bash'
OSH_THEME="ht"

completions=(
  git
  ssh
)

aliases=(
  general
)

plugins=(
  git
  bashmarks
)

source "$OSH"/oh-my-bash.sh

# ──────────────────────────────────────────────────────────────────────────────
# smart-bash-history
# ──────────────────────────────────────────────────────────────────────────────
source /opt/smart-bash-history/01-main-settings.sh
shopt -u progcomp

# ──────────────────────────────────────────────────────────────────────────────
# zoxide
# ──────────────────────────────────────────────────────────────────────────────
eval "$(zoxide init bash)"

# ──────────────────────────────────────────────────────────────────────────────
# user config
# ──────────────────────────────────────────────────────────────────────────────
export EDITOR=nano

[ -f ~/.bash_aliases ] && source ~/.bash_aliases
