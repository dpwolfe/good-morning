#!/usr/bin/bash
export LANG="en_US.UTF-8"

# SIGHUP background jobs on shell exit so closing the terminal tears down child processes.
shopt -s huponexit

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
# Context grep (~40 chars). Alias is `rgr` only — never `rg` (ripgrep); `rg -n` would search for "-n".
function rgfunction {
    if [ $# -eq 0 ]; then
        echo "usage: rgr PATTERN [EXTENSION]   # searches from \$PWD; EXTENSION is bare, e.g. py" >&2
        return 2
    fi
    if [ -n "$2" ]; then
        grep -Ers ".{0,40}$1.{0,40}" --color=auto --include="*.$2" -- *
    else
        # No extension: all files. Old `--include="*."` matched nothing.
        grep -Ers ".{0,40}$1.{0,40}" --color=auto -- *
    fi
}
function findfunction { find . -name "$1" 2>/dev/null; }
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
    "$(npm prefix)/node_modules/.bin/$bin" "$@"
}
function kill-function {
    local pid
    pid="$(pgrep "$1" | tr '\n' ' ')"
    if [ -n "$pid" ]; then
        # shellcheck disable=SC2086
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
# askto [-y|-n] DESCRIPTION [COMMAND] [EXTRA_TEXT]
# Interactive: always prompt. Non-interactive: never `read < /dev/tty` (hangs); -y/--yes proceed, -n/--no
# decline (default). ASKTO_NONINTERACTIVE_DEFAULT=yes|no sets the no-flag fallback for scripted runs.
function askto {
  local noninteractive_default="${ASKTO_NONINTERACTIVE_DEFAULT:-no}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) noninteractive_default=yes; shift;;
      -n|--no)  noninteractive_default=no; shift;;
      --)       shift; break;;
      *)        break;;
    esac
  done

  if [[ $- != *i* ]]; then
    case "$noninteractive_default" in
      y|Y|yes|YES|true|1)
        echo "askto: non-interactive shell, proceeding to $1" >&2
        if [[ -n "${2-}" ]]; then eval "$2"; fi  # ${2-}: no COMMAND is safe under set -u
        return 0;;
      *)
        echo "askto: non-interactive shell, declining to $1" >&2
        return 1;;
    esac
  fi

  echo "Do you want to $1? ${3-}"
  read -r -n 1 -p "(Y/n) " yn < /dev/tty;
  echo # echo newline after input
  # eval: COMMAND is a shell line (pipes/quotes). $($2) word-splits and breaks piped cmds (e.g. gbd).
  case $yn in
    y|Y ) if [[ -n "${2-}" ]]; then eval "$2"; fi; return 0;;
    n|N ) return 1;;
  esac
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
alias rgr=rgfunction

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
pullrm() { if git show-ref -q --verify refs/heads/main; then git pull --rebase origin main; else git pull --rebase origin master; fi; }
alias mm='git merge master'
alias push='git push'
alias pushs='git push --set-upstream origin $(parse_git_branch)'
cm() { if git show-ref -q --verify refs/heads/main; then git checkout main; else git checkout master; fi; }
alias gco='git checkout'
alias gbd='askto "delete all local git branches except master/main" "git branch | grep -Ev \"master|main\" | xargs -n 1 git branch -D"'

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
export PATH="$PYENV_ROOT/bin:$HOME/go/bin:$HOME/.local/bin:$PATH"
export PATH="$PATH:/usr/local/sbin:/usr/local/git/bin:/Applications/CMake.app/Contents/bin:/Library/Developer/CommandLineTools/usr/bin"
export PS1='\[\033]0;$TITLEPREFIX:${PWD//[^[:ascii:]]/?}\007\]\n\[\033[32m\]\u@\h \[\033[33m\]\w \[\033[36m\]($(parse_git_branch 2>/dev/null))\[\033[0m\] \[\033[35m\]\t\[\033[0m\]\n$'
export BASH_SILENCE_DEPRECATION_WARNING=1
export DOCKER_BUILDKIT=1

if [ -f "$(brew --prefix)/etc/bash_completion" ]; then
  # shellcheck source=/dev/null
  . "$(brew --prefix)/etc/bash_completion"
elif [ -f "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]; then
  # shellcheck source=/dev/null
  . "$(brew --prefix)/etc/profile.d/bash_completion.sh"
fi
