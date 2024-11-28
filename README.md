# safe-rm

```
 _______  _______  _______  _______         ______    __   __
|       ||   _   ||       ||       |       |    _ |  |  |_|  |
|  _____||  |_|  ||    ___||    ___| ____  |   | ||  |       |
| |_____ |       ||   |___ |   |___ |____| |   |_||_ |       |
|_____  ||       ||    ___||    ___|       |    __  ||       |
 _____| ||   _   ||   |    |   |___        |   |  | || ||_|| |
|_______||__| |__||___|    |_______|       |___|  |_||_|   |_|
```

[![Build Status](https://github.com/kaelzhang/shell-safe-rm/actions/workflows/nodejs.yml/badge.svg)](https://github.com/kaelzhang/shell-safe-rm/actions/workflows/nodejs.yml)

[Safe-rm][safe-rm], a much safer replacement of [`rm`][rm] with **ALMOST FULL** features of the origin [`rm`][rm] command.

The project was initially developed for Mac OS X, and then tested on Linux.

## Features
- Supports both MacOS and Linux with full test coverage.
- Using `safe-rm`, the files or directories you choose to remove will be moved to the system Trash instead of simply deleting them. You could put them back whenever you want manually.
  - On MacOS, `safe-rm` will use [AppleScript][applescript] to delete files or directories as much as possible to enable the built-in "put-back" capability in the system Trash bin.
  - On Linux, it also follows the operating system's conventions for handling duplicate files in the Trash to avoid overwriting
- Supports Custom [configurations](#configuration).

## Supported options

For those implemented options, safe-rm will act **exactly the same** as the original `rm` command:

| Option | Brief | Description |
| ------ | ----- | ------------ |
| `-i`, `--interactive` | **Interactive** | Prompts you to confirm before removing each file |
| `-I`, `--interactive=once` | **Less Interactive** | Prompts only once before removing more than three files or when recursively removing directories |
| `-f`, `--force` | **Force** | Removes files without prompting for confirmation, ignoring nonexistent files and overriding file protections |
| `-r`, `-R`, `--recursive`, `--Recursive` | **Recursive** | Removes directories and their contents recursively. Required for deleting directories |
| `-v`, `--verbose` | **Verbose** | Displays detailed information about each file or directory being removed |
| `-d`, '--directory' | **Remove Empty Directories** | `safe-rm` can check and only remove empty directories specifically with this flag |
| `--` | **End of Options** | Used to indicate the end of options. Useful if a filename starts with a `-` |

Combined short options are also supported, such as

`-rf`, `-riv`, `-rfv`, etc

## Usual Installation

Add an alias to your `~/.bashrc` script,

```sh
alias rm='/path/to/bin/rm.sh'
```

and `/path/to` is where you git clone `shell-safe-rm` in your local machine.

## Permanent Installation

If you have NPM ([NodeJS](https://nodejs.org/)) installed (RECOMMENDED):

```sh
npm i -g safe-rm
```

Or by using the source code, within the root of the current repo (not recommended, may be unstable):

```sh
# If you have NodeJS installed
npm link

# If you don't have NodeJS or npm installed
make && sudo make install

# For those who have no `make` command:
sudo sh install.sh
```

Installing safe-rm will put `safe-rm` in your `/bin` directory. In order to use
`safe-rm`, you need to add an alias to your `~/.bashrc` script and in all yours
currently open terminals, like this:

```sh
alias rm='safe-rm'
```

After installation and alias definition, when you execute `rm` command in the Terminal, lines of below will be printed:

```sh
$ rm
safe-rm
usage: rm [-f | -i] [-dPRrvW] file ...
     unlink file
```

which helps to tell safe-rm from the original rm.

## Uninstall

First remove the `alias rm=...` line from your `~/.bashrc` file, then

```sh
npm uninstall -g safe-rm
```

Or

```sh
make && sudo make uninstall
```

Or

```sh
sudo sh uninstall.sh
```

# Advanced Sections

## Configuration

Since 2.0.0, you could create a configuration file named `.safe-rm.conf` in your HOME directory, to support
- defining your custom trash directory
- allowing `safe-rm` to permanently delete files and directories that are already in the trash
- disallowing `safe-rm` to use [AppleScript][applescript]

For the description of each config, you could refer to the sample file [here](./sample.safe-rm.conf)

If you want to use a custom configuration file

```sh
alias="SAFE_RM_CONF=/path/to/safe-rm.conf /path/to/bin/rm.sh"
```

Or if it is installed by npm:

```sh
alias="SAFE_RM_CONF=/path/to/safe-rm.conf safe-rm"
```


[applescript]: https://en.wikipedia.org/wiki/AppleScript
[rm]: https://en.wikipedia.org/wiki/Rm_(Unix)
[safe-rm]: https://github.com/kaelzhang/shell-safe-rm
