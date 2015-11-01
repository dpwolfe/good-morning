rgfunction() { egrep -rso ".{0,40}$1.{0,40}" --color=auto --include="*.$2" *; }
findfunction() { find . -name $1; }
unix2dos() { 
    sed "s/$/`echo -e \\\r`/" "$1" > "$1.new";
    rm "$1";
    mv "$1.new" "$1";
}
parse_git_branch() {
    git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
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
alias pull='git pull'
alias pullr='git pull --rebase origin master'
alias mm='git merge master'
alias push='git push'
alias pushs='git push --set-upstream origin $(parse_git_branch)'
alias cm='git checkout master'
alias s='source ~/.bash_profile'
alias ea='vim ~/.bash_profile'
alias eaa='vim ~/repo/devenv/mac/.bash_profile'
alias e='vim'
alias u2d=unix2dos
alias f=findfunction
alias initem='source ./emsdk_portable/emsdk_env.sh'

export PATH="/Applications/CMake.app/Contents/bin":"$PATH"

export PS1='\u@\h:\w ($(parse_git_branch)) \t\n\$'

set -o vi
