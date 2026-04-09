#!/usr/bin/env bash

# Basic configuration
# ------------------------------------------------------------------------------

# You could modify the root config directory of safe-rm by using
# ```sh
# $ export SAFE_RM_CONFIG_ROOT=/path/to/safe-rm-config
# ```
if [[ -n $XDG_CONFIG_HOME && -d "$XDG_CONFIG_HOME/safe-rm" ]]; then
  # If XDG_CONFIG_HOME is set, use it as the configuration root
  SAFE_RM_CONFIG_ROOT=${SAFE_RM_CONFIG_ROOT:="$XDG_CONFIG_HOME/safe-rm"}
else
  SAFE_RM_CONFIG_ROOT=${SAFE_RM_CONFIG_ROOT:="$HOME/.safe-rm"}
fi

# You could modify the location of the configuration file by using
# ```sh
# $ export SAFE_RM_CONFIG=/path/to/safe-rm.conf
# ```
SAFE_RM_CONFIG=${SAFE_RM_CONFIG:="$SAFE_RM_CONFIG_ROOT/config"}

if [[ -f "$SAFE_RM_CONFIG" ]]; then
  source "$SAFE_RM_CONFIG"
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


error(){
  echo "$@" >&2
}


# global exit code, default to 0
EXIT_CODE=0

# Usage:
# ```
# do_exit $LINENO
# do_exit $LINENO 1
# ```
do_exit(){
  local line=$1
  local code=$EXIT_CODE

  if [[ $# -eq 2 ]]; then
    code=$2
  fi

  # Exit immediately
  debug "$line: exit code $code"
  exit $code
}


if [[ "$(uname -s)" == "Darwin"* && -z $SAFE_RM_DEBUG_LINUX ]]; then
  OS_TYPE="MacOS"
  DEFAULT_TRASH="$HOME/.Trash"
else
  OS_TYPE="Linux"
  DEFAULT_TRASH="$HOME/.local/share/Trash"
  SAFE_RM_USE_APPLESCRIPT=
fi


# The target trash directory to dispose files and directories,
#   defaults to the system trash directory
SAFE_RM_TRASH=${SAFE_RM_TRASH:="$DEFAULT_TRASH"}


if [[ "$OS_TYPE" == "MacOS" ]]; then
  if command -v osascript &> /dev/null; then
    # `SAFE_RM_USE_APPLESCRIPT=no` in your SAFE_RM_CONFIG file
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
else
  if mkdir -p "$SAFE_RM_TRASH/files" &> /dev/null; then
    debug "$LINENO: linux trash enabled"
  else
    error "$COMMAND: failed to create trash directory $SAFE_RM_TRASH/files"
    do_exit $LINENO 1
  fi

  if mkdir -p "$SAFE_RM_TRASH/info" &> /dev/null; then
    :
  else
    error "$COMMAND: failed to create trash info directory $SAFE_RM_TRASH/info"
    do_exit $LINENO 1
  fi
fi


SAFE_RM_PROTECTED_RULES="${SAFE_RM_CONFIG_ROOT}/.gitignore"

debug $SAFE_RM_PROTECTED_RULES

# But if it is not a file
if [[ -f "$SAFE_RM_PROTECTED_RULES" ]]; then
  if command -v git &> /dev/null; then
    debug "$LINENO: protected rules enabled: $SAFE_RM_PROTECTED_RULES"

    if git -C "$SAFE_RM_CONFIG_ROOT" rev-parse --is-inside-work-tree &> /dev/null; then
      :
    else
      error "[WARNING] safe-rm requires a git repository to use protected rules"
      error "Initializing a git repository in \"$SAFE_RM_CONFIG_ROOT\" ..."

      git -C "$SAFE_RM_CONFIG_ROOT" init -q

      error "Success"
    fi
  else
    error "[WARNING] safe-rm requires git installed to use protected rules"
    error "  please install git"
    error "  or remove the file \"$SAFE_RM_PROTECTED_RULES\""
    SAFE_RM_PROTECTED_RULES=
  fi
else
  SAFE_RM_PROTECTED_RULES=
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
  echo "usage: rm [-f | -i] [-dIRrv] file ..."
  echo "       unlink [--] file"

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
  # Case 1:
  # rm -v abc -r --force
  # -> -r will be ignored
  # -> args: ['-v'], files: ['abc', '-r', 'force']

  # Case 2:
  # rm -- -r
  # -> -r will be treated as a file
  # -> args: [], files: ['-r']
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
OPT_EMPTY_DIR=

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

  -d|--directory)
    OPT_EMPTY_DIR=1;    debug "$LINENO: empty dir    : $arg"
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
  if [[ $answer == "yes" || ! -n $answer ]]; then
    mkdir -p "$SAFE_RM_TRASH"
  else
    echo "Canceled!"
    exit 1
  fi
fi


check_return_status(){
  local status=$?
  if [[ $status -ne "0" ]]; then
    debug "$LINENO: last command returned status $status"
    EXIT_CODE=$status
  fi
}

# try to remove a file or directory
remove(){
  local file=$1

  # if is dir
  if [[ -d "$file" && ! -L "$file" ]]; then

    # if a directory, and without '-r' option
    if [[ ! -n $OPT_RECURSIVE ]]; then
      # if with '-d' option, and is an empty dir
      if [[ -n $OPT_EMPTY_DIR && ! $(ls -A "$file") ]]; then
          debug "$LINENO: trash an empty directory $file"
          trash "$file"
          return
      fi

      debug "$LINENO: $file: is a directory"
      error "$COMMAND: $file: is a directory"
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
            debug "$LINENO: $file: Directory not empty: $(ls -A "$file")"

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
      # - does not exist
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
  local dir=$1
  local path
  local restore_nullglob=$(shopt -p nullglob)
  local restore_dotglob=$(shopt -p dotglob)

  # Avoid `ls -A` + unquoted `for` iteration, which splits names by IFS
  # and breaks paths containing spaces (e.g. "a b" -> "a" + "b").
  # Use glob expansion with arrays to keep each entry as one element.
  # dotglob includes hidden files, nullglob avoids a literal "$dir/*" token.
  shopt -s nullglob dotglob
  local list=("$dir"/*)
  eval "$restore_nullglob"
  eval "$restore_dotglob"

  for path in "${list[@]}"; do
    debug "$LINENO: recursively remove: $path"

    remove "$path"
  done
}


trash(){
  local target=$1

  if [[ -n $SAFE_RM_PERM_DEL_FILES_IN_TRASH ]]; then
    if is_in_trash "$target"; then
      # If the target is already in the trash, delete it permanently
      /bin/rm -rf "$target"
    else
      do_trash "$target"
    fi
  else
    do_trash "$target"
  fi

  check_return_status
}


do_trash(){
  local target=$1

  debug "$LINENO: trash $target"

  if is_protected "$target"; then
    error "\"$target\" is protected by your configuration"
    return 1
  fi

  if [[ -n $SAFE_RM_USE_APPLESCRIPT ]]; then
    applescript_trash "$target"
  elif [[ "$OS_TYPE" == "MacOS" ]]; then
    mac_trash "$target"
  else
    linux_trash "$target"
  fi
}


get_absolute_path(){
  local dir
  local base
  dir=$(cd "$(dirname -- "$1")" && pwd)
  base=$(basename -- "$1")
  printf '%s/%s\n' "$dir" "$base"
}


encode_trashinfo_path(){
  local path=$1
  local out=
  local i
  local char
  local hex
  local LC_ALL=C

  for ((i = 0; i < ${#path}; i += 1)); do
    char=${path:i:1}

    case "$char" in
      [a-zA-Z0-9._~/-])
        out="$out$char"
        ;;
      *)
        hex=$(printf '%s' "$char" | od -An -tx1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
        out="$out%$hex"
        ;;
    esac
  done

  printf '%s\n' "$out"
}


is_in_trash(){
  local target_abs
  local trash_abs

  target_abs=$(get_absolute_path "$1") || return 1
  trash_abs=$(cd "$SAFE_RM_TRASH" && pwd) || return 1

  [[ "$target_abs" == "$trash_abs" || "$target_abs" == "$trash_abs"/* ]]
}


# Returns
# - 0: the target is protected
# - 1: the target is not protected
is_protected(){
  if [[ ! -n $SAFE_RM_PROTECTED_RULES ]]; then
    # If no protected rules are set, the target is not protected
    return 1
  fi

  local target=$1
  local abs_path=$(get_absolute_path "$target")

  # /path/to/foo -> path/to/foo
  local rel_path=${abs_path#/}

  debug "$LINENO: check whether $rel_path is protected"

  local ignored=$(git -C "$SAFE_RM_CONFIG_ROOT" check-ignore -v --no-index "$rel_path")

  debug "$LINENO: git check-ignore result: $ignored"

  if [[ -n "$ignored" ]]; then
    return 0
  else
    return 1
  fi
}


applescript_trash(){
  local target=$1

  [[ "$OPT_VERBOSE" == 1 ]] && list_files "$target"

  # #47: Finder alias resolves symlinks to their targets.
  # For symbolic links, fallback to `mv`-based trash to remove the link itself.
  if [[ -L "$target" ]]; then
    debug "$LINENO: symlink detected, fallback to mac_trash: $target"
    mac_trash "$target"
    return $?
  fi

  debug "$LINENO: osascript delete $target"

  osascript -e "tell application \"Finder\" to delete (POSIX file \"$target\" as alias)" &> /dev/null

  return $?
}


_short_time_ret=
short_time(){
  _short_time_ret=$(date +%H.%M.%S)
}

_mac_trash_path_ret=
check_mac_trash_path(){
  local path=$1
  local ext=$2
  local full_path="$path$ext"

  if [[ ! -e "$full_path" ]]; then
    _mac_trash_path_ret=$full_path
    return
  fi

  debug "$LINENO: $full_path already exists"

  short_time
  full_path="$path $_short_time_ret$ext"

  while [[ -e "$full_path" ]]; do
    debug "$LINENO: $full_path already exists"
    full_path="${full_path}X"
  done

  _mac_trash_path_ret=$full_path
}


_traveled=
_to_move=

check_target_to_move(){
  _traveled=
  _to_move=$1

  # basename ./       -> .
  # basename ../      -> ..
  # basename ../abc   -> abc
  # basename ../.abc  -> .abc
  if [[ -d "$_to_move" ]]; then
    # We don't know whether a relative path is the pwd or not
    if [[ "${_to_move:0:1}" == '.' || "$_to_move" == "$__DIRNAME" ]]; then
      cd "$_to_move"

      # pwd can't be piped?
      local current=$(pwd)
      _to_move=$(basename "$current")

      # We can not `mv` a dir that is the pwd,
      #   or it will throw an "Operation not permitted" error,
      #   so we have to `cd` to the parent dir first
      cd ..
      _traveled=1
    fi
  fi
}

# trash a file or dir directly
mac_trash(){
  check_target_to_move "$1"
  local move=$_to_move
  local base=$(basename -- "$move")

  # foo.jpg => "foo" + ".jpg"
  # foo => "foo" + ""

  local name="${base%.*}"
  local ext="${base##*.}"

  if [[ "$name" == "$ext" ]]; then
    ext=
  else
    ext=".$ext"
  fi

  # foo.jpg => "foo 12.34.56.jpg"

  check_mac_trash_path "$SAFE_RM_TRASH/$name" "$ext"
  local trash_path=$_mac_trash_path_ret

  [[ "$OPT_VERBOSE" == 1 ]] && list_files "$1"

  debug "$LINENO: mv $move to $trash_path"
  mv -- "$move" "$trash_path"
  local status=$?

  [[ "$_traveled" == 1 ]] && cd "$__DIRNAME" &> /dev/null

  # Propagate mv status; otherwise callers may treat move failures as success.
  return $status
}


# Check if the base name already exists in the trash
# If it does, foo -> foo.1
# If foo.1 exists, foo.1 -> foo.2
check_linux_trash_base(){
  local base=$1
  local trash="$SAFE_RM_TRASH/files"
  local path="$trash/$base"

  # if already in the trash
  if [[ -e "$path" ]]; then
    debug "$LINENO: $path already exists"

    local max_n=0
    local num=
    local restore_nullglob=$(shopt -p nullglob)
    local restore_dotglob=$(shopt -p dotglob)
    shopt -s nullglob dotglob
    local list=("$trash"/*)
    eval "$restore_nullglob"
    eval "$restore_dotglob"
    local file
    local name
    local suffix

    for file in "${list[@]}"; do
      name=$(basename -- "$file")

      if [[ "$name" != "$base".* ]]; then
        continue
      fi

      suffix=${name#"$base".}

      if [[ ! "$suffix" =~ ^[0-9]+$ ]]; then
        continue
      fi

      # Remove leading zeros and make sure the number is in base 10
      num=$((10#$suffix))
      if ((num > max_n)); then
        max_n=$num
      fi
    done

    (( max_n += 1 ))

    echo "$base.$max_n"
  else
    echo "$base"
  fi
}


# trash a file or dir directly for linux
# - move the target into
linux_trash(){
  local original_path
  local trashinfo_path_value

  original_path=$(get_absolute_path "$1") || return 1
  trashinfo_path_value=$(encode_trashinfo_path "$original_path") || return 1

  check_target_to_move "$1"
  local move=$_to_move
  local base=$(basename -- "$move")

  base=$(check_linux_trash_base "$base")

  local trash_path="$SAFE_RM_TRASH/files/$base"

  [[ "$OPT_VERBOSE" == 1 ]] && list_files "$1"

  # Move the target into the trash
  debug "$LINENO: mv $move to $trash_path"
  mv -- "$move" "$trash_path"
  local move_status=$?

  if [[ $move_status -ne 0 ]]; then
    # Keep failure visible to remove()/EXIT_CODE and skip writing .trashinfo.
    [[ "$_traveled" == 1 ]] && cd "$__DIRNAME" &> /dev/null
    return $move_status
  fi

  # Save linux trash info
  local info_path="$SAFE_RM_TRASH/info/$base.trashinfo"
  local trash_time=$(date +%Y-%m-%dT%H:%M:%S)
  cat > "$info_path" <<EOF
[Trash Info]
Path=$trashinfo_path_value
DeletionDate=$trash_time
EOF
  local info_status=$?

  [[ "$_traveled" == 1 ]] && cd "$__DIRNAME" &> /dev/null

  return $info_status
}


# list all files and maintain outward sequence
# we can't just use `find $file`,
#   'coz `find` act a inward searching, unlike rm -v
list_files(){
  if [[ -d "$1" ]]; then
    local restore_nullglob=$(shopt -p nullglob)
    local restore_dotglob=$(shopt -p dotglob)
    # Keep traversal behavior aligned with recursive_remove(): no word splitting
    # for names with spaces, and include dotfiles for rm -v output.
    shopt -s nullglob dotglob
    local list=("$1"/*)
    eval "$restore_nullglob"
    eval "$restore_dotglob"
    local f

    for f in "${list[@]}"; do
      list_files "$f"
    done
  fi

  echo "$1"
}


# debug: get $FILE_NAME array length
debug "$LINENO: ${#FILE_NAME[@]} files or directory to process: ${FILE_NAME[@]}"

# test remove interactive_once: ask for 3 or more files or with recursive option
if [[ (${#FILE_NAME[@]} > 3 || $OPT_RECURSIVE == 1) && $OPT_INTERACTIVE_ONCE == 1 ]]; then
  echo -n "$COMMAND: remove all arguments? "
  read answer

  # actually, as long as the answer start with 'y', the file will be removed
  # default to no remove
  if [[ ! ${answer:0:1} =~ [yY] ]]; then
    do_exit $LINENO
  fi
fi

for file in "${FILE_NAME[@]}"; do
  debug "$LINENO: result file $file"

  if [[ $file == "/" ]]; then
    error "it is dangerous to operate recursively on /"
    error "are you insane?"
    EXIT_CODE=1
    continue
  fi

  if [[ $file == "." || $file == ".." ]]; then
    error "$COMMAND: \".\" and \"..\" may not be removed"
    EXIT_CODE=1
    continue
  fi

  # the same check also apply on /. /..
  if [[ $(basename -- "$file") == "." || $(basename -- "$file") == ".." ]]; then
    error "$COMMAND: \".\" and \"..\" may not be removed"
    EXIT_CODE=1
    continue
  fi

  if [[ -e "$file" || -L "$file" ]]; then
    remove "$file"
    status=$?
    debug "$LINENO: remove returned status: $status"

    if [[ ! $status == 0 ]]; then
      EXIT_CODE=1
    fi
  elif [[ -z "$OPT_FORCE" ]]; then
    error "$COMMAND: $file: No such file or directory" >&2
    EXIT_CODE=1
  fi
done

do_exit $LINENO
