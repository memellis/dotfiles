echo "Setting my bash_aliases..."

alias mywindev="cd ${MY_HOME}/MyDevelop"
alias ubupdate="sudo apt-get update && sudo apt-get upgrade"

if [ -f ~/.git_aliases ] ; then
    . ~/.git_aliases
fi
