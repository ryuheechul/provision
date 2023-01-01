#!/usr/bin/env bash

ncat --sh-exec "ncat host.lima.internal 5900" -l 5900 --keep-open
