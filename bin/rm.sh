#!/bin/bash

# Basic configuration
# ------------------------------------------------------------------------------

DEFAULT_SAFE_RM_CONF="$HOME/.safe-rm.conf"

# You could modify the location of the configuration file by using
# ```sh
# $ export SAFE_RM_CONF=/path/to/safe-rm.conf
# ```
SAFE_RM_CONF=${SAFE_RM_CONF:="$DEFAULT_SAFE_RM_CONF"}

if [[ -f "$SAFE_RM_CONF" ]]; then
  source "$SAFE_RM_CONF"
fi


# Print debug info or not
SAFE_RM_DEBUG=${SAFE_RM_DEBUG:=}

# Whether to delete files in the trash permanently, defaults to NO
if [[ ${SAFE_RM_PERM_DEL_FILES_IN_TRASH:0:1} =~ [yY] ]]; then
  SAFE_RM_PERM_DEL_FILES_IN_TRASH=1
else
  SAFE_RM_PERM_DEL_FILES_IN_TRASH=
fi


debug(){
  if [[ -n "$SAFE_RM_DEBUG" ]]; then
    echo "[D] $@" >&2
  fi
}


OS="$(uname -s)"

case "$OS" in
    Darwin*)
      OS_TYPE="MacOS"
      DEFAULT_TRASH="$HOME/.Trash"
      ;;

    # We treat all other systems as Linux
    *)
      OS_TYPE="Linux"
      DEFAULT_TRASH="$HOME/.local/share/Trash/files"
      SAFE_RM_USE_APPLESCRIPT=
      ;;
esac


# The target trash directory to dispose files and directories,
#   defaults to the system trash directory
SAFE_RM_TRASH=${SAFE_RM_TRASH:="$DEFAULT_TRASH"}


if [[ "$OS_TYPE" == "MacOS" ]]; then
  if command -v osascript &> /dev/null; then
    # `SAFE_RM_USE_APPLESCRIPT=no` in your SAFE_RM_CONF file
    #   to disable AppleScript
    if [[ "$SAFE_RM_USE_APPLESCRIPT" == "no" ]]; then
      debug "$LINENO: applescript disabled by conf"
      SAFE_RM_USE_APPLESCRIPT=

    elif [[ "$SAFE_RM_TRASH" == "$DEFAULT_TRASH" ]]; then
      debug "$LINENO: applescript enabled"
      SAFE_RM_USE_APPLESCRIPT=1
    else
      debug "$LINENO: applescript disabled due to custom trash"
      SAFE_RM_USE_APPLESCRIPT=
    fi
  else
    SAFE_RM_USE_APPLESCRIPT=
  fi
fi

# ------------------------------------------------------------------------------

# Simple basename: /bin/rm -> rm
COMMAND=${0##*/}

# pwd
__DIRNAME=$(pwd)


# parse argv
# ------------------------------------------------------------------------------

invalid_option(){
  # if there's an invalid option, `rm` only takes the second char of the option string
  # case:
  # rm -c
  # -> rm: illegal option -- c
  echo "rm: illegal option -- ${1:1:1}"
  usage
}

usage(){
  echo "usage: rm [-f | -i] [-dIPRrvW] file ..."
  echo "       unlink file"

  # if has an invalid option, exit with 64
  exit 64
}


if [[ "$#" == 0 ]]; then
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
      split_push_arg $1; debug "$LINENO: short option $1"
      ;;

    # rm --force a
    --[a-zA-Z]*)
      push_arg $1; debug "$LINENO: option $1"
      ;;

    # rm -- -a
    --)
      ARG_END=1; debug "$LINENO: divider"
      ;;

    # case:
    # rm -
    # -> args: [], files: ['-']
    *)
      push_file "$1"; debug "$LINENO: file $1"
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
    OPT_FORCE=1;        debug "$LINENO: force        : $arg"
    ;;

  # interactive=always
  -i|--interactive|--interactive=always)
    OPT_INTERACTIVE=1;  debug "$LINENO: interactive  : $arg"
    OPT_INTERACTIVE_ONCE=
    ;;

  # interactive=once. interactive=once and interactive=always are exclusive
  -I|--interactive=once)
    OPT_INTERACTIVE_ONCE=1;  debug "$LINENO: interactive_once  : $arg"
    OPT_INTERACTIVE=;
    ;;

  # both r and R is allowed
  -[rR]|--[rR]ecursive)
    OPT_RECURSIVE=1;    debug "$LINENO: recursive    : $arg"
    ;;

  # only lowercase v is allowed
  -v|--verbose)
    OPT_VERBOSE=1;      debug "$LINENO: verbose      : $arg"
    ;;

  *)
    invalid_option $arg
    ;;
  esac
done
# /parse argv
# ------------------------------------------------------------------------------


# make sure recycled bin exists
if [[ ! -e $SAFE_RM_TRASH ]]; then
  echo "Directory \"$SAFE_RM_TRASH\" does not exist, do you want create it?"
  echo -n "(yes/no): "

  read answer
  if [[ $answer == "yes" || ! -n $anwser ]]; then
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
  if [[ -d "$file" && ! -L "$file" ]]; then

    # if a directory, and without '-r' option
    if [[ ! -n $OPT_RECURSIVE ]]; then
      debug "$LINENO: $file: is a directory"
      echo "$COMMAND: $file: is a directory"
      return 1
    fi

    if [[ "$file" == './' ]]; then
      echo "$COMMAND: $file: Invalid argument"
      return 1
    fi

    if [[ "$OPT_INTERACTIVE" == 1 ]]; then
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
      # The file
      # - is a symbolic link
      # - is a file
      # - does not existx
      trash "$file"
      debug "$LINENO: trash returned status $?"
    fi

  # if is a file
  else
    if [[ "$OPT_INTERACTIVE" == 1 ]]; then
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


trash(){
  local target=$1

  if [[ -n $SAFE_RM_PERM_DEL_FILES_IN_TRASH ]]; then
    if [[ "$target" == "$SAFE_RM_TRASH"* ]]; then
      # If the target is already in the trash, delete it permanently
      /bin/rm -rf "$target"
    else
      do_trash "$target"
    fi
  else
    do_trash "$target"
  fi
}


do_trash(){
  debug "$LINENO: trash $1"

  if [[ -n $SAFE_RM_USE_APPLESCRIPT ]]; then
    applescript_trash "$1"
  elif [[ "$OS_TYPE" == "MacOS" ]]; then
    mac_trash "$1"
  else
    linux_trash "$1"
  fi
}


applescript_trash(){
  local file=$1

  debug "$LINENO: osascript delete $file"

  osascript -e "tell application \"Finder\" to delete (POSIX file \"$file\" as alias)" &> /dev/null

  # TODO: handle osascript errors
  return 0
}


_short_time_ret=
short_time(){
  _short_time_ret=$(date +%H.%M.%S)
}

_check_trash_path_ret=
check_trash_path(){
  local path=$1

  # if already in the trash
  if [[ -e "$path" ]]; then
    debug "$LINENO: $path already exists"

    # renew $_short_time_ret
    short_time
    _check_trash_path_ret="$path $_short_time_ret"
    check_trash_path "$_check_trash_path_ret"
  else
    _check_trash_path_ret=$path
  fi
}


# trash a file or dir directly
mac_trash(){
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
  if [[ -d "$file" && "${base:0:1}" == '.' ]]; then
    # then file must be a relative dir
    cd $file

    # pwd can't be piped?
    move=$(pwd)
    move=$(basename "$move")
    cd ..
    travel=1
  fi

  local trash_path=$SAFE_RM_TRASH/$base
  check_trash_path "$trash_path"
  trash_path=$_check_trash_path_ret

  [[ "$OPT_VERBOSE" == 1 ]] && list_files "$file"

  debug "$LINENO: mv $move to $trash_path"
  mv "$move" "$trash_path"

  [[ "$travel" == 1 ]] && cd $__DIRNAME &> /dev/null

  # default status
  return 0
}


# trash a file or dir directly for linux
# - move the target into
linux_trash(){
  :
}


# list all files and maintain outward sequence
# we can't just use `find $file`,
#   'coz `find` act a inward searching, unlike rm -v
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
debug "$LINENO: ${#FILE_NAME[@]} files or directory to process: ${FILE_NAME[@]}"

# test remove interactive_once: ask for 3 or more files or with recursive option
if [[ (${#FILE_NAME[@]} > 2 || $OPT_RECURSIVE == 1) && $OPT_INTERACTIVE_ONCE == 1 ]]; then
  echo -n "$COMMAND: remove all arguments? "
  read answer

  # actually, as long as the answer start with 'y', the file will be removed
  # default to no remove
  if [[ ! ${answer:0:1} =~ [yY] ]]; then
    debug "$LINENO: EXIT_CODE $EXIT_CODE"
    exit $EXIT_CODE
  fi
fi

for file in "${FILE_NAME[@]}"; do
  debug "$LINENO: result file $file"

  if [[ $file == "/" ]]; then
    echo "it is dangerous to operate recursively on /"
    echo "are you insane?"
    EXIT_CODE=1

    # Exit immediately
    debug "$LINENO: EXIT_CODE $EXIT_CODE"
    exit $EXIT_CODE
  fi

  if [[ $file == "." || $file == ".." ]]; then
    echo "$COMMAND: \".\" and \"..\" may not be removed"
    EXIT_CODE=1
    continue
  fi

  # the same check also apply on /. /..
  if [[ $(basename "$file") == "." || $(basename "$file") == ".." ]]; then
    echo "$COMMAND: \".\" and \"..\" may not be removed"
    EXIT_CODE=1
    continue
  fi

  # deal with wildcard and also, redirect error output
  ls_result=$(ls -d "$file" 2> /dev/null)

  # debug
  debug "$LINENO: ls_result: $ls_result"

  if [[ -n "$ls_result" ]]; then
    for file in "$ls_result"; do
      remove "$file"
      status=$?
      debug "$LINENO: remove returned status: $status"

      if [[ ! $status == 0 ]]; then
        EXIT_CODE=1
      fi
    done
  elif [[ -z "$OPT_FORCE" ]]; then
    echo "$COMMAND: $file: No such file or directory" >&2
    EXIT_CODE=1
  fi
done

debug "$LINENO: EXIT_CODE $EXIT_CODE"
exit $EXIT_CODE
