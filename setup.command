#!/bin/bash
# Double-click on a Mac to run setup.sh (asks which repository to set up).
cd "$(dirname "$0")" || exit 1
bash ./setup.sh "$@"
read -r -p "Enter で閉じる"
