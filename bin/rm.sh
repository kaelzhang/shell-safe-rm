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

SAFE_RM_SCOPE_ENV_DEFINED=
SAFE_RM_SCOPE_ENV_VALUE=
if [[ ${SAFE_RM_SCOPE+x} ]]; then
  SAFE_RM_SCOPE_ENV_DEFINED=1
  SAFE_RM_SCOPE_ENV_VALUE=$SAFE_RM_SCOPE
fi

if [[ -f "$SAFE_RM_CONFIG" ]]; then
  source "$SAFE_RM_CONFIG"
fi

if [[ -n "$SAFE_RM_SCOPE_ENV_DEFINED" ]]; then
  SAFE_RM_SCOPE=$SAFE_RM_SCOPE_ENV_VALUE
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
  # FreeDesktop home trash is $XDG_DATA_HOME/Trash; per the XDG base-dir spec,
  # $HOME/.local/share is only the fallback when XDG_DATA_HOME is unset, empty,
  # or relative (a non-absolute value must be ignored).
  if [[ "${XDG_DATA_HOME:0:1}" == "/" ]]; then
    DEFAULT_TRASH="$XDG_DATA_HOME/Trash"
  else
    DEFAULT_TRASH="$HOME/.local/share/Trash"
  fi
  SAFE_RM_USE_APPLESCRIPT=
fi


# Whether to honor options after the first operand (`rm dir -rf`).
# Defaults to auto: enabled on Linux, disabled on MacOS. yes|no to override.
case ${SAFE_RM_OPTIONS_ANYWHERE:0:1} in
  [yY])
    OPTIONS_ANYWHERE=1
    ;;
  [nN])
    OPTIONS_ANYWHERE=
    ;;
  *)
    if [[ "$OS_TYPE" == "Linux" ]]; then
      OPTIONS_ANYWHERE=1
    else
      OPTIONS_ANYWHERE=
    fi
    ;;
esac


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
      [[ -z "$OPTIONS_ANYWHERE" ]] && ARG_END=1
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

  # interactive=always.
  # -i and -I are NOT mutually exclusive: BSD rm always applies the per-file
  # confirmation when -i is given, regardless of -I or argument order. Keeping
  # both flags independent guarantees the per-file prompt is never silently
  # dropped (the -I once-prompt still fires on top when its threshold is met).
  -i|--interactive|--interactive=always)
    OPT_INTERACTIVE=1;  debug "$LINENO: interactive  : $arg"
    ;;

  # interactive=once
  -I|--interactive=once)
    OPT_INTERACTIVE_ONCE=1;  debug "$LINENO: interactive_once  : $arg"
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

  ensure_safe_scope "$file" || return 1

  # if is dir
  if [[ -d "$file" && ! -L "$file" ]]; then

    # if a directory, and without '-r' option
    if [[ ! -n $OPT_RECURSIVE ]]; then
      # with '-d': trash an empty dir, but report a non-empty one as such
      # (matching rm(1)) instead of the generic "is a directory".
      if [[ -n $OPT_EMPTY_DIR ]]; then
        if [[ ! $(ls -A "$file") ]]; then
          debug "$LINENO: trash an empty directory $file"
          trash "$file"
          return
        fi

        error "$COMMAND: $file: Directory not empty"
        return 1
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
  if [[ "$1" == "/" ]]; then
    printf '/\n'
    return
  fi

  dir=$(cd "$(dirname -- "$1")" && pwd) || return 1
  base=$(basename -- "$1")

  case "$base" in
    .)
      printf '%s\n' "$dir"
      ;;

    ..)
      dir=$(cd "$dir/.." && pwd) || return 1
      printf '%s\n' "$dir"
      ;;

    *)
      printf '%s/%s\n' "$dir" "$base"
      ;;
  esac
}


expand_home_path(){
  case $1 in
    "~")
      printf '%s\n' "$HOME"
      ;;

    "~/"*)
      printf '%s/%s\n' "$HOME" "${1#~/}"
      ;;

    *)
      printf '%s\n' "$1"
      ;;
  esac
}


resolve_directory_path(){
  local path
  path=$(expand_home_path "$1")

  (
    cd "$path" &> /dev/null || exit 1
    pwd
  )
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

  if [[ "$target_abs" == "$trash_abs" || "$target_abs" == "$trash_abs"/* ]]; then
    return 0
  fi

  # Per-mount: the target counts as "in trash" only if it actually lives inside
  # the per-mount trash that this target's own filesystem would route to -- the
  # same membership test used for the home trash, NOT a free-floating path
  # pattern (which would wrongly match e.g. a synced copy of another machine's
  # trash sitting on the home filesystem, and permanently delete it).
  if [[ -n $PER_MOUNT_ACTIVE ]]; then
    resolve_linux_trash_root "$1"
    if [[ -n $_trash_topdir && "$target_abs" == "$_trash_root"/files/* ]]; then
      return 0
    fi
  fi

  return 1
}


SAFE_RM_SCOPE_ROOT=
init_safe_rm_scope(){
  if [[ -z "$SAFE_RM_SCOPE" ]]; then
    return 0
  fi

  SAFE_RM_SCOPE_ROOT=$(resolve_directory_path "$SAFE_RM_SCOPE") || {
    error "$COMMAND: invalid SAFE_RM_SCOPE '$SAFE_RM_SCOPE': not an existing directory"
    return 1
  }

  debug "$LINENO: safe rm scope enabled: $SAFE_RM_SCOPE_ROOT"
}


is_in_scope(){
  local target_abs

  if [[ -z "$SAFE_RM_SCOPE_ROOT" ]]; then
    return 0
  fi

  target_abs=$(get_absolute_path "$1") || return 1

  [[ "$target_abs" == "$SAFE_RM_SCOPE_ROOT" || "$target_abs" == "$SAFE_RM_SCOPE_ROOT"/* ]]
}


ensure_safe_scope(){
  if is_in_scope "$1"; then
    return 0
  fi

  error "$COMMAND: target '$1' skipped, unsafe directory scope"
  return 1
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

  # For symlinks we delegate to mac_trash below, which emits its own verbose
  # output; printing here too would list the path twice.
  [[ "$OPT_VERBOSE" == 1 && ! -L "$target" ]] && list_files "$target"

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

  # Use -e || -L so a broken (dangling) symlink already in the trash still
  # counts as a collision; otherwise `-e` follows it, reports "absent", and the
  # move would silently overwrite that symlink.
  if [[ ! -e "$full_path" && ! -L "$full_path" ]]; then
    _mac_trash_path_ret=$full_path
    return
  fi

  debug "$LINENO: $full_path already exists"

  short_time
  full_path="$path $_short_time_ret$ext"

  while [[ -e "$full_path" || -L "$full_path" ]]; do
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
      # Guard the cd: if the target cannot be entered (e.g. no execute bit),
      # we must NOT substitute the parent's basename below — doing so would
      # `mv` the entire parent directory (and all siblings) into the trash.
      # Fall back to moving the original target path as given.
      if ! cd "$_to_move" 2>/dev/null; then
        _to_move=$1
        _traveled=
        return
      fi

      # pwd can't be piped?
      local current=$(pwd)
      _to_move=$(basename "$current")

      # We can not `mv` a dir that is the pwd,
      #   or it will throw an "Operation not permitted" error,
      #   so we have to `cd` to the parent dir first
      if ! cd .. 2> /dev/null; then
        # Could not reach the parent; restore cwd and fall back to the original
        # target rather than mv'ing from an unexpected directory.
        _to_move=$1
        _traveled=
        cd "$__DIRNAME" 2> /dev/null
        return
      fi
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

  # A leading-dot name with no other dot (.bashrc, .gitignore) is extensionless
  # to Finder; without this the split yields an empty name and a duplicate would
  # become " HH.MM.SS.bashrc" (leading space, dot lost).
  if [[ -z "$name" ]]; then
    name=$base
    ext=
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


# ------------------------------------------------------------------------------
# Per-mount trash routing (issue #50)
#
# When enabled, deletions are routed to a trash directory on the SAME filesystem
# as the target, so `mv` stays an instant rename instead of a cross-device copy.
# Follows the FreeDesktop.org trash spec for mount-point trash directories.
# ------------------------------------------------------------------------------

# Device id (st_dev) of a path. `stat -c %d` is supported by coreutils and
# BusyBox; it is the value `mv`/rename() keys off of to decide same-filesystem.
dev_id_of(){
  stat -c '%d' "$1" 2>/dev/null
}


# Print the mount point (top directory) of the filesystem containing $1 (a dir).
# Prefers findmnt (util-linux); falls back to a device-id walk for BusyBox/Alpine.
mount_point_of(){
  local start=$1

  if [[ -n $HAS_FINDMNT ]]; then
    local mp
    mp=$(findmnt -n -o TARGET --target "$start" 2>/dev/null)
    if [[ -n $mp ]]; then
      printf '%s\n' "$mp"
      return 0
    fi
  fi

  # Climb until the device id changes; the last same-device dir is the mount point.
  local dir=$start
  local dev
  dev=$(dev_id_of "$dir") || return 1
  [[ -z $dev ]] && return 1

  local parent
  local pdev
  while [[ "$dir" != "/" ]]; do
    parent=$(dirname -- "$dir")
    pdev=$(dev_id_of "$parent") || return 1
    [[ -z $pdev ]] && return 1

    if [[ "$pdev" != "$dev" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi

    dir=$parent
  done

  printf '/\n'
}


# Ensure a trash directory has its files/ and info/ subdirectories.
ensure_trash_skeleton(){
  mkdir -p "$1/files" "$1/info" &> /dev/null
}


# Select the FreeDesktop trash directory for a mount's top directory.
# Sets _mount_trash_root and returns 0 on success, 1 if none is usable.
_mount_trash_root=
select_mount_trash_dir(){
  local topdir=$1
  _mount_trash_root=

  # Spec: $topdir/.Trash must be a directory, carry the sticky bit, and not be
  # a symbolic link. If the checks pass, use $topdir/.Trash/$uid.
  local admin="$topdir/.Trash"
  if [[ -d "$admin" && ! -L "$admin" && -k "$admin" ]]; then
    if ensure_trash_skeleton "$admin/$SAFE_RM_UID"; then
      _mount_trash_root="$admin/$SAFE_RM_UID"
      return 0
    fi
  fi

  # Otherwise use (and create) $topdir/.Trash-$uid.
  if ensure_trash_skeleton "$topdir/.Trash-$SAFE_RM_UID"; then
    _mount_trash_root="$topdir/.Trash-$SAFE_RM_UID"
    return 0
  fi

  return 1
}


# Resolve the trash root + top directory for a target.
# Sets _trash_root (always) and _trash_topdir (empty => home trash, so the
# .trashinfo Path stays absolute; non-empty => mount trash, Path relative to it).
_trash_root=
_trash_topdir=
resolve_linux_trash_root(){
  local target=$1
  _trash_root=$SAFE_RM_TRASH
  _trash_topdir=

  [[ -z $PER_MOUNT_ACTIVE ]] && return 0

  local abs
  abs=$(get_absolute_path "$target") || return 0
  local parent
  parent=$(dirname -- "$abs")

  local topdir=

  if [[ -n $SAFE_RM_DEBUG_MOUNT_ROOTS ]]; then
    # Test seam: treat the listed prefixes as separate filesystems.
    local rest=$SAFE_RM_DEBUG_MOUNT_ROOTS
    local root
    while [[ -n $rest ]]; do
      root=${rest%%:*}
      if [[ "$rest" == *:* ]]; then
        rest=${rest#*:}
      else
        rest=
      fi

      [[ -z $root ]] && continue

      if [[ "$parent" == "$root" || "$parent" == "$root"/* ]]; then
        topdir=$root
        break
      fi
    done

    # Not under any listed root => home filesystem.
    [[ -z $topdir ]] && return 0
  else
    local pdev
    pdev=$(dev_id_of "$parent") || return 0

    # Same device as the home trash => home trash (mv already instant).
    [[ -z $pdev || "$pdev" == "$HOME_TRASH_DEV" ]] && return 0

    topdir=$(mount_point_of "$parent") || return 0
    [[ -z $topdir || "$topdir" == "/" ]] && return 0
  fi

  # The relative .trashinfo Path requires topdir to be a genuine prefix of the
  # target's path. findmnt canonicalizes symlinks while get_absolute_path does
  # not, so a symlinked mount alias could break that prefix; fall back to the
  # home trash rather than record a malformed (absolute) Path in a mount trash.
  case "$abs/" in
    "$topdir"/*) ;;
    *) return 0 ;;
  esac

  if select_mount_trash_dir "$topdir"; then
    _trash_root=$_mount_trash_root
    _trash_topdir=$topdir
    debug "$LINENO: per-mount trash root $_trash_root (topdir $topdir)"
  fi

  return 0
}


# Pick a trash base name that is free in BOTH files/ and info/.
# foo -> foo (if free), else foo.1, foo.2, ...
# Considering info/ as well prevents reusing the name of an orphan .trashinfo
# (info present, files/ counterpart gone), which would otherwise be clobbered.
check_linux_trash_base(){
  local base=$1
  local trash_root=${2:-$SAFE_RM_TRASH}
  local files="$trash_root/files"
  local info="$trash_root/info"

  # Free only if neither the file nor its info counterpart exists.
  if [[ ! -e "$files/$base" && ! -e "$info/$base.trashinfo" ]]; then
    echo "$base"
    return
  fi

  debug "$LINENO: $base already exists in the trash"

  local max_n=0
  local num=
  local restore_nullglob=$(shopt -p nullglob)
  local restore_dotglob=$(shopt -p dotglob)
  shopt -s nullglob dotglob
  local files_list=("$files"/*)
  local info_list=("$info"/*)
  eval "$restore_nullglob"
  eval "$restore_dotglob"

  # Normalize: file entries as-is; info entries with the .trashinfo suffix removed.
  local names=()
  local entry
  for entry in "${files_list[@]}"; do
    names+=("$(basename -- "$entry")")
  done
  for entry in "${info_list[@]}"; do
    entry=$(basename -- "$entry")
    names+=("${entry%.trashinfo}")
  done

  local name
  local suffix
  for name in "${names[@]}"; do
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
}


# trash a file or dir directly for linux
# - move the target into
linux_trash(){
  local original_path
  local trashinfo_path_value

  original_path=$(get_absolute_path "$1") || return 1

  # Pick the trash directory on the target's own filesystem when possible.
  resolve_linux_trash_root "$1"
  local trash_root=$_trash_root
  local topdir=$_trash_topdir

  if [[ -n $topdir ]]; then
    # Mount-point trash: Path is relative to the top directory (spec).
    trashinfo_path_value=$(encode_trashinfo_path "${original_path#"$topdir"/}") || return 1
  else
    # Home trash: absolute path.
    trashinfo_path_value=$(encode_trashinfo_path "$original_path") || return 1
  fi

  check_target_to_move "$1"
  local move=$_to_move
  local base=$(basename -- "$move")

  # Reserve a unique trash name by atomically creating its .trashinfo FIRST,
  # per the FreeDesktop spec (info-first, opened with O_EXCL). `noclobber` makes
  # the redirect fail if the name is already taken, so a concurrent run or an
  # orphan info file forces a different name instead of overwriting an existing
  # file or clobbering another item's metadata. Retry until a free name is won.
  local trash_time=$(date +%Y-%m-%dT%H:%M:%S)
  local candidate
  local info_path
  local reserved=
  local attempts=0
  while (( attempts < 10000 )); do
    candidate=$(check_linux_trash_base "$base" "$trash_root")
    info_path="$trash_root/info/$candidate.trashinfo"

    if ( set -o noclobber
         printf '[Trash Info]\nPath=%s\nDeletionDate=%s\n' \
           "$trashinfo_path_value" "$trash_time" > "$info_path"
       ) 2> /dev/null; then
      reserved=1
      break
    fi

    # A failure that left no info file behind is not a name collision (e.g. info/
    # is unwritable); retrying would only spin, so stop and report failure.
    if [[ ! -e "$info_path" ]]; then
      break
    fi

    (( attempts += 1 ))
  done

  if [[ -z $reserved ]]; then
    error "$COMMAND: $1: could not reserve a trash name"
    [[ "$_traveled" == 1 ]] && cd "$__DIRNAME" &> /dev/null
    return 1
  fi

  local trash_path="$trash_root/files/$candidate"

  [[ "$OPT_VERBOSE" == 1 ]] && list_files "$1"

  # Move the target into the trash
  debug "$LINENO: mv $move to $trash_path"
  mv -- "$move" "$trash_path"
  local move_status=$?

  if [[ $move_status -ne 0 ]]; then
    # Roll back the reserved info so we never leave info-without-files;
    # keep the failure visible to remove()/EXIT_CODE.
    /bin/rm -f -- "$info_path"
    [[ "$_traveled" == 1 ]] && cd "$__DIRNAME" &> /dev/null
    return $move_status
  fi

  [[ "$_traveled" == 1 ]] && cd "$__DIRNAME" &> /dev/null

  return 0
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

# Per-mount trash: opt-in, Linux only, and only when using the default trash
# (a custom SAFE_RM_TRASH means the user wants a single consolidated location).
PER_MOUNT_ACTIVE=
SAFE_RM_UID=
HAS_FINDMNT=
HOME_TRASH_DEV=
if [[ ${SAFE_RM_TRASH_PER_MOUNT:0:1} =~ [yY] && "$OS_TYPE" == "Linux" ]]; then
  if [[ "$SAFE_RM_TRASH" == "$DEFAULT_TRASH" ]]; then
    PER_MOUNT_ACTIVE=1
    SAFE_RM_UID=$(id -u)
    command -v findmnt &> /dev/null && HAS_FINDMNT=1
    HOME_TRASH_DEV=$(dev_id_of "$SAFE_RM_TRASH")
    debug "$LINENO: per-mount trash enabled (uid=$SAFE_RM_UID findmnt=${HAS_FINDMNT:-0} home_dev=$HOME_TRASH_DEV)"
  else
    debug "$LINENO: per-mount trash disabled: custom SAFE_RM_TRASH"
  fi
fi

init_safe_rm_scope || do_exit $LINENO 1

# test remove interactive_once: ask for more than three files or with recursive option
# Use -gt for a NUMERIC comparison; `>` inside [[ ]] is lexicographic and would
# wrongly skip the prompt for counts like 10-29, 100-299, etc.
if [[ (${#FILE_NAME[@]} -gt 3 || $OPT_RECURSIVE == 1) && $OPT_INTERACTIVE_ONCE == 1 ]]; then
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

  if ! ensure_safe_scope "$file"; then
    EXIT_CODE=1
    continue
  fi

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

  # A trailing slash on a non-directory is ENOTDIR ("Not a directory"), not "No
  # such file or directory"; real rm reports this even under -f.
  if [[ "$file" == */ ]]; then
    stripped=${file%/}
    if [[ -n "$stripped" && ! -d "$stripped" && ( -e "$stripped" || -L "$stripped" ) ]]; then
      error "$COMMAND: $file: Not a directory"
      EXIT_CODE=1
      continue
    fi
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
