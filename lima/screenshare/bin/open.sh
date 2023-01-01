#!/usr/bin/env bash

bash -c "sleep 1; open 'vnc://$(make -s ip):5900'" &
