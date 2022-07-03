#!/usr/bin/bash
set -ex

. /tmp/environment

curl -s 'https://bootstrap.pypa.io/get-pip.py' | python3
