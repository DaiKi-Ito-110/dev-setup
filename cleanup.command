#!/bin/bash
# Double-click on a Mac to run cleanup.sh before returning it.
cd "$(dirname "$0")" || exit 1
bash ./cleanup.sh "$@"
read -r -p "Enter で閉じる"
