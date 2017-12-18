#!/usr/bin/bash
export LANG="en_US.UTF-8"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#Git autocomplete
# shellcheck source=git-completion.bash
source "$DIR/git-completion.bash"

rgfunction() { grep -Ers ".{0,40}$1.{0,40}" --color=auto --include="*.$2" -- *; }
findfunction() { find . -name "$1"; }
unix2dos() {
    sed "s/$/$(printf '\r')/" "$1" > "$1.new";
    rm "$1";
    mv "$1.new" "$1";
}

parse_git_branch() {
    git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
}
npm-exec() {
    bin="$1"
    shift
    # shellcheck disable=SC2068
    "$(npm bin)/$bin" $@
}
kill-function() {
    local pid
    pid="$(pgrep $1 | tr '\n' ' ')"
    if [ -n "$pid" ]; then
        kill -s KILL $pid;
        echo "Killed $1 $pid"
    else
        echo "No proc to kill with the name '$1'"
    fi
}

alias gvim='/Applications/MacVim.app/Contents/MacOS/Vim -g'
alias ls='ls -G'
alias ll='ls -la'
alias l.='ls -dG .*'

alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'
alias .6='cd ../../../../../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias .......='cd ../../../../../..'

alias grep='grep --color=auto'
alias eg='egrep --color=auto'
alias fg='fgrep --color=auto'
alias rg=rgfunction

alias sha1='openssl sha1'
alias bc='bc -l'
alias mkdir='mkdir -pv'
alias mount='mount |column -t'
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%T"'
alias nowtime=now
alias nowdate='date +"%d-%m-%Y"'

alias vi=vim
alias svi='sudo vim'
alias vis='vim "+set si"'
alias edit='vim'
alias e='vim'

alias ping='ping -c 5'
alias fastping='ping -c 100 -s.2'
alias ports='netstat -tulanp'

alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'

alias k=kill-function
alias kg='kill-function grunt'
alias ks='kill-function safari'
alias kc='kill-function chrome'
alias kf='kill-function firefox'
alias kn='kill-function node'

alias s='source $HOME/.bash_profile'
alias eb='vim $HOME/.bash_profile'
alias ebpub='vim $HOME/repo/environment/mac/.bash_profile'

alias u2d=unix2dos
alias f=findfunction
alias initem='source $HOME/emsdk_portable/emsdk_env.sh'
alias xs='sudo xcode-select --switch "/Applications/Xcode.app/Contents/Developer/"'
alias dn='debug-node --web-port 8081'

alias gc='git commit -m'
alias gca='git commit -a -m'
alias pull='git pull'
alias pullr='git pull --rebase origin'
alias pullrm='git pull --rebase origin master'
alias mm='git merge master'
alias push='git push'
alias pushs='git push --set-upstream origin $(parse_git_branch)'
alias cm='git checkout master'
alias gco='git checkout'

# create a new SSL cert with Let's Encrypt using certbot and a DNS TXT challenge
alias certonly='sudo certbot certonly --manual --preferred-challenges dns'

gmfunction() {
  pushd "$DIR" > /dev/null || return
  echo "Pulling latest for environment repository..."
  git pull > /dev/null
  export GOOD_MORNING_RUN=1
  popd > /dev/null || return
  # shellcheck disable=SC1090
  source "$DIR/setup.sh"
}
alias good_morning='gmfunction'

export PATH="$HOME/.local/bin:/usr/local/git/bin:/Library/Developer/CommandLineTools/usr/bin:/Applications/CMake.app/Contents/bin:$PATH"
export PS1='\[\033]0;$TITLEPREFIX:${PWD//[^[:ascii:]]/?}\007\]\n\[\033[32m\]\u@\h \[\033[33m\]\w \[\033[36m\](`parse_git_branch`)\[\033[0m\] \[\033[35m\]\t\[\033[0m\]\n$'
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

if [ -f "$(brew --prefix)/etc/bash_completion" ]; then
# shellcheck source=/dev/null
. "$(brew --prefix)/etc/bash_completion"
fi
