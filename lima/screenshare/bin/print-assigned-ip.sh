#!/usr/bin/env bash

ifconfig | grep -A 1 lima0 | tail -n 1 | awk '{print $2}'
