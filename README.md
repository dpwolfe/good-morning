# environment
Shared Engineering Environment Files

## OS X Setup
Run the following from a command prompt to enable holding key to repeat characters. You will need this when navigating using VI commands:
`defaults write -g ApplePressAndHoldEnabled -bool false`

Add these lines to your ~\.bash_profile, creating one if it doesn't exist:
```shell
export REPO_ROOT=~/repo
source $REPO_ROOT/environment/mac/.bash_profile
```
Set REPO\_ROOT above to your preferred root directory for your cloned github repositories.
