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

# flags
debug=

# tools
debug(){
    if [ -n "$debug" ]; then
        echo "$@" >&2
    fi
}

invalid_option(){
    # -k -> k
    c=`echo $1 | cut -d '-' -f2`

    # todo
    echo "rm: illegal option -- $c"
    usage
}


usage()
{
    echo "usage: rm [-f | -i] [-dPRrvW] file ..."
    echo "       unlink file"
}


if [[ "$#" = 0 ]]; then
    echo "safe-rm"
    usage
fi

# overload arguments

FILE_NAME=

# flags
OPT_FORCE=
OPT_INTERACTIVE=
OPT_RECURSIVE=

# temp
i=0

while [ -n "$1" ]
do
    case $1 in
        # -[hH]|--[hH]elp)
        # help
        # shift
        # ;;

        -f|--force)
        OPT_FORCE=1; debug "force"
        shift
        ;;

        -i|--interactive)
        OPT_INTERACTIVE=1; debug "interactive"
        shift
        ;;

        -[rR]|--[rR]ecursive)
        OPT_RECURSIVE=1; debug "recursive"
        shift
        ;;

        -[a-zA-Z0-9]*)
        invalid_option $1
        shift
        ;;

        *)
        FILE_NAME[i]=$1; debug "file: $1"
        ((i += 1))
        shift
        ;;
    esac
done


# make sure recycled bin exists
if [[ ! -e "$TRASH" ]]; then
    echo "Directory \"$TRASH\" does not exist, do you want create it?"
    echo -n "(yes/no): "
    
    read answer
    if [[ "$answer" = "yes" || ! -n $anwser ]]; then
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
            if [[ ! -n "$OPT_RECURSIVE" ]]; then
                echo "$COMMAND: $file: is a directory"
                echo "(maybe you should use a \"-r\" option)"
                fail=1
            fi
        fi
    else
        echo "$COMMAND: $file: No such file or directory"
        fail=1
    fi


    if [[ "$fail" = 0 ]]; then

        # if already in the trash
        if [[ -e "$trash_name" ]]; then
            trash_name="$trash_name $TIME"
            # echo "exists, rename to $trash_name"

        else
            trash_name="$trash_name"
        fi

        # echo "move $file"
        # echo "to $trash_name"

        if [[ "$OPT_INTERACTIVE" = 1 ]]; then
            echo "remove $file? "
            read answer

            if [[ "$answer" = "yes" || "$answer" = "y" || "$answer" = "YES" || "$answer" = "Y" ]]; then
                :
            else
                exit 0
            fi
        fi

        mv "$file" "$trash_name"
    fi
done



