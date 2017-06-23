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
    "$(npm bin)/$*"
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

alias k='kill -s KILL'
alias kg='kill -s KILL $(pgrep grunt)'
alias ks='kill -s KILL $(pgrep Safari)'
alias kc='kill -s KILL $(pgrep Chrome)'
alias kf='kill -s KILL $(pgrep firefox)'
alias kn='kill -s KILL $(pgrep node)'

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

alias good_morning='source $DIR/setup.sh'

export PATH="/usr/local/git/bin:/Library/Developer/CommandLineTools/usr/bin:/Applications/CMake.app/Contents/bin:$PATH"
export PS1='\[\033]0;$TITLEPREFIX:${PWD//[^[:ascii:]]/?}\007\]\n\[\033[32m\]\u@\h \[\033[33m\]\w \[\033[36m\](`parse_git_branch`)\[\033[0m\] \[\033[35m\]\t\[\033[0m\]\n$'
