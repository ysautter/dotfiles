[[ -f ~/.bashrc ]] && . ~/.bashrc

export PATH=$PATH:$HOME/.scripts
export EDITOR="vim"
export BROWSER="firefox"
export TERMINAL="st"

if [[ "$(tty)" = "/dev/tty1" ]]; then
    pgrep i3 || startx
fi
