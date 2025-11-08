PS1="%1~ %# "

if [[ -f "$HOME/.git-hooks.zsh" ]]; then
  source "$HOME/.git-hooks.zsh"
fi
