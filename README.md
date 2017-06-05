# Shared Engineering Environment Files
Setup a machine quickly instead of wasting half a day.

## macOS Instructions
Run this command in a terminal:

```
curl -sL https://raw.githubusercontent.com/dpwolfe/environment/master/mac/setup.sh | sh
```

A `~\.bash_profile` is created for you by running setup.sh. In case you already had one, add these lines to yours, changing the value for REPO_ROOT below to match your location:
```shell
export REPO_ROOT="$HOME/repo"
source "$REPO_ROOT/environment/mac/.bash_profile"
```
Set REPO\_ROOT above to your preferred root directory for your cloned GitHub repositories.

## Contributors
Yes, please.
