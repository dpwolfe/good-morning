# Good Morning

First thing to run on a new MacBook and every morning thereafter to keep it up to date.

## Instructions

1. Open the App Store (_Apple Menu > App Store..._) and install all system updates.
2. Open up a Terminal session (_Command + Space_ and type "Terminal")
3. Run this command to kick off the script:

    ```sh
    curl -sL https://raw.githubusercontent.com/dpwolfe/good-morning/master/good-morning.sh | sh
    ```

## What does it do?

_It's automated, but not unattended._ On first run, an opinionated set of common tooling is installed and numerous opinionated system settings are set. You're only prompted the first time to set the system settings. Even if you don't like some settings, you'll probably like 95% of them. Change those you don't like afterwards and feel free to open an issue for feedback on those you think I should prompt everyone about first.

Some of the goodies:

1. Node Version Manager (rvm)
1. Homebrew, installing a variety of formulas and casks
1. Xcode latest
1. Node.js latest and latest LTS
1. Pyenv w/ a Python 2.x and 3.x version and pip
1. An SSH key and GPG key and installing them on GitHub
1. Ruby Version Manager (rvm) with latest Ruby
1. iTerm
1. Configure the terminal to use some dotfiles. Feel free to bring your own dotfiles afterwards.

_Run good-morning... every morning._ Use iTerm. Subsequent runs do many things to keep your system up to date, including:

1. Update Node Version Manager (nvm)
1. Updating you to the latest Node.js and latest LTS of Node.js (using nvm)
    - The previous latest version is uninstalled automatically. That only happens once, so install/re-install older versions as needed since they are not touched by good-morning.
1. Update globally installed node_modules in both latest versions of Node.js
1. Update npm in both latest versions of Node.js
1. Fix ownership to be yours on directories as recommended by Homebrew or found from my own trials by fire
1. Update apps installed via Homebrew casks in addition to brew formulas (regular brews are easy).
1. Update Python versions
1. Update pips, sometimes fixing the install of pip
1. Update Xcode
1. Update Ruby gems
1. Variety of installer cache cleanup and clearing to free up space
