#!/bin/bash

# You could modify these environment variables to change the default constants
# Default to ~/.Trash on Mac, ~/.local/share/Trash/files on Linux.
DEFAULT_TRASH="$HOME/.Trash"
if [[ "$(uname -s)" == "Linux" ]]; then
  DEFAULT_TRASH="$HOME/.local/share/Trash/files"
fi


SAFE_RM_TRASH=${SAFE_RM_TRASH:="$DEFAULT_TRASH"}


# Print debug info or not
SAFE_RM_DEBUG=${SAFE_RM_DEBUG:=}
# -------------------------------------------------------------------------------

# Simple basename: /bin/rm -> rm
COMMAND=${0##*/}

# pwd
__DIRNAME=$(pwd)

GUID=0
TIME=
date_time(){
  TIME=$(date +%Y-%m-%d_%H:%M:%S)-$GUID
  (( GUID += 1 ))
}

# tools
debug(){
  if [[ -n "$SAFE_RM_DEBUG" ]]; then
    echo "[D] $@" >&2
  fi
}


# parse argv -------------------------------------------------------------------------------

invalid_option(){
  # if there's an invalid option, `rm` only takes the second char of the option string
  # case:
  # rm -c
  # -> rm: illegal option -- c
  echo "rm: illegal option -- ${1:1:1}"
  usage
}

usage(){
  echo "usage: rm [-f | -i | -I] [-dPRrvW] file ..."
  echo "       unlink file"

  # if has an invalid option, exit with 64
  exit 64
}


if [[ "$#" = 0 ]]; then
  echo "safe-rm"
  usage
fi

ARG_END=
FILE_NAME=
ARG=

file_i=0
arg_i=0

split_push_arg(){
  # remove leading '-' and split combined short options
  # -vif -> vif -> v, i, f
  split=`echo ${1:1} | fold -w1`

  local arg
  for arg in ${split[@]}; do
    ARG[arg_i]="-$arg"
    ((arg_i += 1))
  done
}

push_arg(){
  ARG[arg_i]=$1
  ((arg_i += 1))
}

push_file(){
  FILE_NAME[file_i]=$1
  ((file_i += 1))
}

# pre-parse argument vector
while [[ -n $1 ]]; do
  # case:
  # rm -v abc -r --force
  # -> -r will be ignored
  # -> args: ['-v'], files: ['abc', '-r', 'force']
  if [[ -n $ARG_END ]]; then
    push_file "$1"

  else
    case $1 in

    # case:
    # rm -v -f -i a b

    # case:
    # rm -vf -ir a b

    # ATTENTION:
    # Regex in bash is not perl regex,
    # in which `'*'` means "anything" (including nothing)
    -[a-zA-Z]*)
      split_push_arg $1; debug "short option $1"
      ;;

    # rm --force a
    --[a-zA-Z]*)
      push_arg $1; debug "option $1"
      ;;

    # rm -- -a
    --)
      ARG_END=1; debug "divider"
      ;;

    # case:
    # rm -
    # -> args: [], files: ['-']
    *)
      push_file "$1"; debug "file $1"
      ARG_END=1
      ;;
    esac
  fi

  shift
done

# flags
OPT_FORCE=
OPT_INTERACTIVE=
OPT_INTERACTIVE_ONCE=
OPT_RECURSIVE=
OPT_VERBOSE=

# global exit code, default to 0
EXIT_CODE=0

# parse options
for arg in ${ARG[@]}; do
  case $arg in

  # There's no --help|-h option for rm on Mac OS
  # [hH]|--[hH]elp)
  # help
  # shift
  # ;;

  -f|--force)
    OPT_FORCE=1;        debug "force        : $arg"
    ;;

  # interactive=always
  -i|--interactive|--interactive=always)
    OPT_INTERACTIVE=1;  debug "interactive  : $arg"
    OPT_INTERACTIVE_ONCE=
    ;;

  # interactive=once. interactive=once and interactive=always are exclusive
  -I|--interactive=once)
    OPT_INTERACTIVE_ONCE=1;  debug "interactive_once  : $arg"
    OPT_INTERACTIVE=;
    ;;

  # both r and R is allowed
  -[rR]|--[rR]ecursive)
    OPT_RECURSIVE=1;    debug "recursive    : $arg"
    ;;

  # only lowercase v is allowed
  -v|--verbose)
    OPT_VERBOSE=1;      debug "verbose      : $arg"
    ;;

  *)
    invalid_option $arg
    ;;
  esac
done
# /parse argv -------------------------------------------------------------------------------


# make sure recycled bin exists
if [[ ! -e $SAFE_RM_TRASH ]]; then
  echo "Directory \"$SAFE_RM_TRASH\" does not exist, do you want create it?"
  echo -n "(yes/no): "

  read answer
  if [[ $answer = "yes" || ! -n $anwser ]]; then
    mkdir -p "$SAFE_RM_TRASH"
  else
    echo "Canceled!"
    exit 1
  fi
fi

# try to remove a file or directory
remove(){
  local file=$1

  # if is dir
  if [[ -d $file ]]; then

  # if a directory, and without '-r' option
  if [[ ! -n $OPT_RECURSIVE ]]; then
    debug "$LINENO: $file: is a directory"
    echo "$COMMAND: $file: is a directory"
    return 1
  fi

  if [[ $file = './' ]]; then
    echo "$COMMAND: $file: Invalid argument"
    return 1
  fi

  if [[ $OPT_INTERACTIVE = 1 ]]; then
    echo -n "examine files in directory $file? "
    read answer

    # actually, as long as the answer start with 'y', the file will be removed
    # default to no remove
    if [[ ${answer:0:1} =~ [yY] ]]; then

      # if choose to examine the dir, recursively check files first
      recursive_remove "$file"

      # interact with the dir at last
      echo -n "remove $file? "
      read answer
      if [[ ${answer:0:1} =~ [yY] ]]; then
        [[ $(ls -A "$file") ]] && {
          echo "$COMMAND: $file: Directory not empty"

          return 1

        } || {
          trash "$file"
          debug "$LINENO: trash returned status $?"
        }
      fi
    fi
  else
    trash "$file"
    debug "$LINENO: trash returned status $?"
  fi

  # if is a file
  else
    if [[ "$OPT_INTERACTIVE" = 1 ]]; then
      echo -n "remove $file? "
      read answer
      if [[ ${answer:0:1} =~ [yY] ]]; then
        :
      else
        return 0
      fi
    fi

    trash "$file"
    debug "$LINENO: trash returned status $?"
  fi
}


recursive_remove(){
  local path

  # use `ls -A` instead of `for` to list hidden files.
  # and `for $1/*` is also weird if `$1` is neithor a dir nor existing that will print "$1/*" directly and rudely.
  # never use `find $1`, for the searching order is not what we want
  local list=$(ls -A "$1")

  [[ -n $list ]] && for path in "$list"; do
    remove "$1/$path"
  done
}


# trash a file or dir directly
trash(){
  debug "trash $1"

  # origin file path
  local file=$1

  # the first parameter to be passed to `mv`
  local move=$file
  local base=$(basename "$file")
  local travel=

  # basename ./       -> .
  # basename ../      -> ..
  # basename ../abc   -> abc
  # basename ../.abc  -> .abc
  if [[ -d "$file" && ${base:0:1} = '.' ]]; then
    # then file must be a relative dir
    cd $file

    # pwd can't be piped?
    move=$(pwd)
    move=$(basename "$move")
    cd ..
    travel=1
  fi

  local trash_name=$SAFE_RM_TRASH/$base

  # if already in the trash
  if [[ -e "$trash_name" ]]; then
    # renew $TIME
    date_time
    trash_name="$trash_name-$TIME"
  fi

  [[ "$OPT_VERBOSE" = 1 ]] && list_files "$file"

  debug "mv $move to $trash_name"
  mv "$move" "$trash_name"

  [[ "$travel" = 1 ]] && cd $__DIRNAME &> /dev/null

  #default status
  return 0
}

# list all files and maintain outward sequence
# we can't just use `find $file`, 'coz `find` act a inward searching, unlike rm -v
list_files(){
  if [[ -d "$1" ]]; then
    local list=$(ls -A "$1")
    local f

    [[ -n $list ]] && for f in "$list"; do
      list_files "$1/$f"
    done
  fi

  echo $1
}


# debug: get $FILE_NAME array length
debug "${#FILE_NAME[@]} files or directory to process: ${FILE_NAME[@]}"

# test remove interactive_once: ask for 3 or more files or with recorsive option
if [[ (${#FILE_NAME[@]} > 2 || $OPT_RECURSIVE = 1) && $OPT_INTERACTIVE_ONCE = 1 ]]; then
  echo -n "$COMMAND: remove all arguments? "
  read answer

  # actually, as long as the answer start with 'y', the file will be removed
  # default to no remove
  if [[ ! ${answer:0:1} =~ [yY] ]]; then
    debug "EXIT_CODE $EXIT_CODE"
    exit $EXIT_CODE
  fi
fi

for file in "${FILE_NAME[@]}"; do
  debug "result file $file"

  if [[ $file = "/" ]]; then
    echo "it is dangerous to operate recursively on /"
    echo "are you insane?"
    EXIT_CODE=1

    # Exit immediately
    debug "EXIT_CODE $EXIT_CODE"
    exit $EXIT_CODE
  fi

  if [[ $file = "." || $file = ".." ]]; then
    echo "$COMMAND: \".\" and \"..\" may not be removed"
    EXIT_CODE=1
    continue
  fi

  #the same check also apply on /. /..
  if [[ $(basename $file) = "." || $(basename $file) = ".." ]]; then
    echo "$COMMAND: \".\" and \"..\" may not be removed"
    EXIT_CODE=1
    continue
  fi

  # deal with wildcard and also, redirect error output
  ls_result=$(ls -d "$file" 2> /dev/null)

  # debug
  debug "ls_result: $ls_result"

  if [[ -n "$ls_result" ]]; then
    for file in "$ls_result"; do
      remove "$file"
      status=$?
      debug "remove returned status: $status"

      if [[ ! $status == 0 ]]; then
        EXIT_CODE=1
      fi
    done
  else
    echo "$COMMAND: $file: No such file or directory"
    EXIT_CODE=1
  fi
done

debug "EXIT_CODE $EXIT_CODE"
exit $EXIT_CODE
