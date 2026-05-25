# Good Morning

First thing to run on a new MacBook and every morning thereafter to keep it up to date.

## Prerequisites

_A fresh install of macOS is ideal, but not required._

- macOS 26 (Tahoe) or newer.
- Admin privileges on your MacBook.
- An Apple ID that has accepted the developer agreement, which you can do for free here: <https://developer.apple.com/account/>
- A solid Internet connection at least for the first run since Xcode will be installed.

## Instructions

1. Install all system updates (_Apple Menu > System Settings > General > Software Update_).
2. Open up a Terminal session (_Command + Space_ for Spotlight Search and type "Terminal").
3. Run this command:

   ```sh
   curl -sL https://raw.githubusercontent.com/dpwolfe/good-morning/master/good-morning.sh | bash
   ```

> **Security note:** Please feel free to review the script before piping to bash: <https://raw.githubusercontent.com/dpwolfe/good-morning/master/good-morning.sh>

## Running it daily

After the first run, type `good-morning` from any new shell session. The alias pulls
the latest version of the script from your local clone, then re-sources it, so you're
always running the newest version.

A typical daily run takes 1-3 minutes when everything is already up-to-date and it's safe
to re-run if interrupted.

## What does it do?

On the first run, it sets up a new MacBook with a list of commonly installed apps and
opinionated system settings. _It's automated, not unattended._ If you are a power user,
you'll probably like 95% of the system settings, which makes it well worth the trouble
of undoing a few that are not to your liking. Change the ones you don't like afterwards
and feel free to open issues for feedback.

### Avoid wasting hours manually installing and setting up the usual laundry list of tools like:

1. Xcode and the Command Line Tools.
2. Homebrew, with an opinionated set of casks and formulas.
   - Casks include: iTerm2, Visual Studio Code, Docker, Brave Browser, Charles, GPG Suite,
     Handbrake, Fira Code, The Unarchiver.
   - Formulas include: `git`, `git-lfs`, `bash`, `zsh`, `go`, `awscli`, `jq`, `fzf`,
     `fd`, `httpie`, `direnv`, `tmux`, `vim`, `wget`, `caddy`, `certbot`, `shellcheck`,
     `pandoc`, `vegeta`, `watchman`, `rbenv`, `ruby-build`, `python@3.14`, `openssl@3`,
     `coreutils`, `sevenzip`, and more.
3. Ruby via rbenv (currently Ruby 3.4.9) with gems: `cocoapods`, `sqlint`,
   `terraform_landscape`.
4. Python packages via pip: `boto`, `gitpython`, `glances`, `lxml`, `packaging`,
   `pip-review`, `pipdeptree`, `pipenv`, `pycurl`, `requests`, `virtualenv`.
5. Node Version Manager (nvm) with the latest Node.js and the latest LTS of Node.js.
6. A new SSH key and GPG key, walking you through their creation and the steps to add
   them to GitHub.
7. Primes your `.bash_profile` with references to dotfiles containing aliases, git bash
   completion, environment variables, paths, etc.
   - Feel free to bring your own dotfiles after the first run.

### _Run good-morning... every morning_ to keep it all up-to-date, including:

1. Update Homebrew along with every installed formula and cask.
2. Update Node Version Manager (nvm), the latest Node.js, and the latest LTS of Node.js.
   - Simple way to discover when a new Node.js version releases.
   - Globally installed packages are automatically re-installed into new Node.js versions.
   - The version immediately before any next version being installed gets uninstalled
     automatically. That only happens during an upgrade. Installs/re-installs of older
     versions are untouched.
3. Update npm and globally installed `node_modules` in the latest Node.js and Node.js LTS.
4. Keep the active Xcode developer directory pointed at `/Applications/Xcode.app` when
   it's installed, accept the Xcode license on your behalf, and install any bundled
   packages that a fresh Xcode drop ships with.
5. Update Ruby gems and pip packages to their latest versions.
6. Fix file and directory ownership to be yours where recommended by Homebrew or as
   was discovered through trial and error.
7. Auto-approve quarantined apps for Gatekeeper where SIP allows it, and surface a
   short list of ones you'll need to approve by hand where it doesn't.
8. Clean installer file caches, freeing up disk space.
9. Apply or re-apply workarounds needed to keep the latest tools, apps, or macOS
   version working in harmony.

## Customization

Fork this repo and edit to taste. The most common things to change:

- **Casks and formulas** -- the `casks=()` and `formulas=()` arrays in `good-morning.sh`.
  Uncomment what you need, comment out what you don't.
- **Pip packages** -- the `pips=()` array.
- **Ruby gems** -- the `gems=()` array inside `installGems`.
- **macOS defaults** -- the long block of `defaults write` commands near the end of the
  script. Each one is independent; remove or tweak individual settings freely.
- **Dotfiles** -- on first run, any existing `~/.bash_profile` is backed up to
  `~/.old_bash_profile_<timestamp>` and replaced with one that sources `dotfiles/`.
  After that, it's yours; the script won't touch it again.

## Troubleshooting

- **Gatekeeper blocks an app** -- Some casks install apps that macOS quarantines. The
  script auto-approves what SIP allows, but for others you'll see a short list at the end
  of the run. Open _System Settings > Privacy & Security_ and click "Open Anyway".
- **Script hangs waiting for sudo** -- The password prompt reads from `/dev/tty`. If your
  terminal multiplexer or IDE doesn't expose a real TTY, run in a plain Terminal window.
- **Something failed but scrollback is gone** -- Check `~/.good-morning-logs/latest.log`
  for the full ANSI-stripped output of the most recent run.
- **A Homebrew formula won't build** -- Run `brew doctor` manually; the script runs it
  after upgrades but skips it when nothing changed.

## Logs

Every run is tee'd to a timestamped, ANSI-stripped log file under
`~/.good-morning-logs/`, with `latest.log` symlinked to the most recent one. Handy when
something failed and your terminal scrollback is already gone.

## Password handling

Steps that need `sudo` are batched through a single prompt. The password is held in
memory encrypted with a random per-session key and discarded when the run ends. The
first time you run it, the script will ask whether to keep it cached between runs in
the same shell session and remember your answer in `~/.good_morning`.

## License

Released under the [MIT License](LICENSE).
