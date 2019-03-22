#!/usr/bin/bash
export LANG="en_US.UTF-8"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#Git autocomplete
# shellcheck source=git-completion.bash
source "$DIR/git-completion.bash"

function contains {
    # contains(string, substring)
    # Returns 0 if string contains the substring, otherwise returns 1
    string="$1"
    substring="$(printf '%q' "$2")"
    if test "${string#*$substring}" != "$string"; then return 0; else return 1; fi
}
function rgfunction { grep -Ers ".{0,40}$1.{0,40}" --color=auto --include="*.$2" -- *; }
function findfunction { find . -name "$1"; }
function unix2dos {
    sed "s/$/$(printf '\r')/" "$1" > "$1.new";
    rm "$1";
    mv "$1.new" "$1";
}
function parse_git_branch {
    git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
}
function npm-exec {
    bin="$1"
    shift
    # shellcheck disable=SC2068
    "$(npm bin)/$bin" $@
}
function kill-function {
    local pid
    pid="$(pgrep $1 | tr '\n' ' ')"
    if [ -n "$pid" ]; then
        kill -s KILL $pid;
        echo "Killed $1 $pid"
    else
        echo "No proc to kill with the name '$1'"
    fi
}
function vpn-connect {
  if [[ -n "$1" ]]; then
    osascript <<-EOF
tell application "System Events"
  tell current location of network preferences
    set VPN to service "$1"
    if exists VPN then connect VPN
      repeat while (current configuration of VPN is not connected)
      delay 1
    end repeat
  end tell
end tell
EOF
  else
    scutil --nc list | grep --color=never "\(Disconnected\)"
    echo "Provide the name of one of the connections above."
  fi
}
function vpn-disconnect {
  if [[ -n "$1" ]]; then
    osascript <<-EOF
tell application "System Events"
  tell current location of network preferences
    set VPN to service "$1"
    if exists VPN then disconnect VPN
  end tell
end tell
return
EOF
  else
    scutil --nc list | grep --color=never "\(Connected\)"
    echo "Provide the name of one of the connections above."
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

# editors
alias vi=vim
alias svi='sudo vim'
alias vis='vim "+set si"'
alias edit='vim'
alias e='vim'

alias ping='ping -c 5'
alias fastping='ping -c 100 -s.2'
alias ports='netstat -tulanp'
alias routes='netstat -rn'

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
alias ebpub='vim $HOME/repo/good-morning/dotfiles/.bash_profile'

alias u2d=unix2dos
alias f=findfunction
alias initem='source $HOME/emsdk_portable/emsdk_env.sh'
alias xs='sudo xcode-select --switch "/Applications/Xcode.app/Contents/Developer/"'
alias dn='debug-node --web-port 8081'

# git
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

alias yul='yarn upgrade-interactive --latest'
alias flushdns='sudo killall -HUP mDNSResponder;sudo killall mDNSResponderHelper;sudo dscacheutil -flushcache'

# create a new SSL cert with Let's Encrypt using certbot and a DNS TXT challenge
alias certonly='sudo certbot certonly --manual --preferred-challenges dns'

gmfunction() {
  pushd "$DIR" > /dev/null || return
  echo "Pulling latest version of good-morning..."
  git pull > /dev/null
  export GOOD_MORNING_RUN=1
  popd > /dev/null || return
  # shellcheck disable=SC1090
  source "$DIR/../good-morning.sh"
}
alias good-morning='gmfunction'

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$HOME/go/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/git/bin:/Library/Developer/CommandLineTools/usr/bin:/Applications/CMake.app/Contents/bin:$PATH"
export PS1='\[\033]0;$TITLEPREFIX:${PWD//[^[:ascii:]]/?}\007\]\n\[\033[32m\]\u@\h \[\033[33m\]\w \[\033[36m\](`parse_git_branch`)\[\033[0m\] \[\033[35m\]\t\[\033[0m\]\n$'

if [ -f "$(brew --prefix)/etc/bash_completion" ]; then
  # shellcheck source=/dev/null
  . "$(brew --prefix)/etc/bash_completion"
fi
