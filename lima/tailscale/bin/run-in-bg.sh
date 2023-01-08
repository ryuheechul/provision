#!/usr/bin/env bash

# this script is expected be called something like Automator.app
# use Automator to run it and register the Automator "app" on login items
# to run this to survive every reboot

# inspired by https://github.com/ryuheechul/dotfiles/blob/8371620a1ea8486333192956fbb2b9144977d9d5/bin/darwin/watch-appearance-changes.sh

# https://unix.stackexchange.com/a/115431
this_script_d="${0:a:h}"

# use whatever shell can work out right path
project_d="${this_script_d}/.." \
	zsh -c 'pushd "${project_d}"; make start-notty' \
	>/dev/null 2>&1 &
# some how going into background is necessary to prevent hanging with automator https://apple.stackexchange.com/a/340443/368485
