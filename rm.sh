#!/bin/bash

RECYCLED_BIN="$HOME/Trash_test"

# rm "$RECYCLED_BIN"


function help()
{
    exit 0
}

# overload arguments

# flags
OPT_FORCE=0
OPT_RECURSIVE=0

# temp
i=0

while [ -n "$1" ]
do
    case $1 in
        -[hH]|--[hH]elp)
        help
        shift
        ;;

        -f)
        OPT_FORCE=1
        shift
        ;;

        -[rR]|--[rR]ecursive)
        OPT_RECURSIVE=1
        shift
        ;;

        -[a-zA-Z0-9]*)
        invalid_option $1
        shift
        ;;

        *)
        FILENAME[i]=$1
        ((i += 1))
        shift 1
        ;;
    esac
done

if [[ "$OPT_FORCE" -eq "1" ]]; then
    echo "force"
fi

if [[ "$OPT_RECURSIVE" -eq "1" ]]; then
    echo "recursive"
fi


if [[ ! -d "$RECYCLED_BIN" ]]; then
    echo "Directory \"$RECYCLED_BIN\" does not exist, do you want create it?"
    echo -n "(yes/on):"
    
    read answer
    if [[ "$answer" = "yes" || ! -n "$anwser" ]]
    then
        mkdir -p "$RECYCLED_BIN"
    else
        echo "Canceled!"
        exit 1
    fi
fi



