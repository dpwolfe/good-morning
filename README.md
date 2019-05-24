# Good Morning

First thing to run on a new MacBook and every morning thereafter to keep it up to date.

## Pre-requisites

1. You must have admin privileges on your MacBook.
1. You must have an Apple ID that has accepted the developer agreement, which you can do
   for free here: <https://developer.apple.com/agree>

## Instructions

1. Open the App Store (_Apple Menu > App Store..._) and install all system updates.
2. Open up a Terminal session (_Command + Space_ and type "Terminal")
3. Run this command to kick off the script:

    ```sh
    curl -sL https://raw.githubusercontent.com/dpwolfe/good-morning/master/good-morning.sh | sh
    ```

## What does it do?

On the first run, it sets up a new MacBook with a list of commonly installed apps and
opinionated system settings. _It's automated, not unattended._ If you are a power user,
you'll probably like 95% of the system settings, which makes it well worth the trouble
of undoing a few that are not to your liking. Change the ones you don't like afterwards
and feel free to open issues for feedback.

### Avoid wasting hours manually installing and setting up the usual laundry list of tools like:

1. Xcode latest, plus the command line tools and, since Mojave, installs the C headers
   that are no longer present by default.
1. Node Version Manager (nvm) with latest Node.js and latest LTS of Node.js
1. Homebrew, installing a number of frequently used apps and utilities.
   - Includes: Microsoft Office, Docker, Visual Studio Code, Slack, Skype, Minikube + VirtuaBox,
     Spotify, Wireshark, Postman, iTerm2, Charles, DBeaver
1. Pyenv w/ Python 2.x and 3.x versions along with pip
1. A new SSH key and GPG key by walking you through their creation and the steps to add
   them to GitHub
1. Ruby Version Manager (rvm) with the latest Ruby
1. iTerm2
1. Primes your .bash_profile with some dotfiles containing aliases, git bash completion,
   environment variables, paths, etc.
   - Feel free to bring your own dotfiles or edit as needed after the first run.

### _Run good-morning... every morning._ to keep all the apps and tools up-to-date, including:

1. Update Node Version Manager (nvm)
1. Update you to the latest Node.js and latest LTS of Node.js with nvm
   - An easy way to discover when a new Node.js version releases.
   - Globally installed packages are automatically re-installed with new Node.js versions.
   - The version that is immediately before the new version (locally) is uninstalled automatically.
     That only happens during an upgrade, so install/re-install older versions as needed without worry since
     they will not be affected by good-morning.
1. Update npm and globally installed node_modules for the latest Node.js and Node.js LTS.
1. Fix ownership to be yours on directories recommended by Homebrew or as required by casks through trial and error.
1. Update apps (casks) installed via Homebrew in addition to brew formulas (updating brew formulas was already easy).
1. Update Python versions and pip versions. Occasionally fix the install of pip because Python environments are finicky.
1. Update Xcode, uninstalling the immediately previous version similar to Node.js upgrades.
1. Update Ruby and Ruby gems.
1. Keep installer caches clean, freeing up disk space.
