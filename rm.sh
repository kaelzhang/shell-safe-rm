#!/bin/bash

TRASH="$HOME/.Trash"
COMMAND="$0"
Y=`date +%Y`
M=`date +%m`
D=`date +%d`
h=`date +%H`
m=`date +%M`
s=`date +%S`
TIME="$Y-$M-$D $h.$m.$s"

# echo "time: $TIME; Y: $Y"

# rm "$TRASH"


function help()
{
    exit 0
}

# overload arguments

declare -a FILE_NAME

# flags
OPT_FORCE=0
OPT_RECURSIVE=0

# temp
i=0

while [ -n "$1" ]
do
    case $1 in
        # -[hH]|--[hH]elp)
        # help
        # shift
        # ;;

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
        FILE_NAME[i]=$1
        ((i += 1))
        shift 1
        ;;
    esac
done


# make sure recycled bin exists
if [[ ! -e "$TRASH" ]]; then
    echo "Directory \"$TRASH\" does not exist, do you want create it?"
    echo "(yes/no):"
    
    read answer
    if [[ "$answer" -eq "yes" || ! -n "$anwser" ]]; then
        mkdir -p "$TRASH"
    else
        echo "Canceled!"
        exit 1
    fi
fi


for file in ${FILE_NAME[@]}
do
    file_basename=`basename $file`
    trash_name="$TRASH/$file_basename"
    fail=0

    # file
    if [[ -e "$file" ]]; then
        if [[ -d "$file" ]]; then

            # if a directory, and without '-r' option
            if [[ "$OPT_RECURSIVE" -eq "0" ]]; then
                echo "$COMMAND: $file: is a directory"
                echo "  -- maybe you should use a \"-r\" option"
                fail=1
            fi
        fi
    else
        echo "$COMMAND: $file: No such file or directory"
        fail=1
    fi

    

    if [[ "$fail" -eq "0" ]]; then
        # if already in the trash
        if [[ -e "$trash_name" ]]; then
            trash_name=`echo "$trash_name $TIME"`
            # echo "exists, rename to $trash_name"
        fi

        # echo "move $file"
        # echo "to $trash_name"

        mv "$file" "$trash_name"
    fi
done





