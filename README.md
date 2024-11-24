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

A much safer replacement of bash `rm` with **ALMOST FULL** features of the origin `rm` command.

Initially developed on Mac OS X, then tested on Linux.

Using `safe-rm`, the files or directories you choose to remove will move to `$HOME/.Trash` instead of simply deleting them. You could put them back whenever you want manually.

If a file or directory with the same name already exists in the Trash, the name of newly-deleted items will be ended with the current date and time.

## Supported options

For those implemented options, safe-rm will act **exactly the same** as the original `rm` command

`-i`, `--interactive`

`-I`, `--interactive=once`

`-f`, `--force`

`-r`, `-R`, `--recursive`, `--Recursive`

`-v`, `--verbose`

`--`

Combined short options are also supported, such as

`-rf`, `-riv`, `-rfv`, etc

## Usual Installation

Add an alias to your `~/.bashrc` script,

```sh
alias rm='/path/to/bin/rm.sh'
```

and `/path/to` is where you git clone `shell-safe-rm` in your local machine.

## Permanent Installation

If you have NPM (node) installed (RECOMMENDED):

```sh
npm i -g safe-rm
```

Or normally with `make` (not recommended, may be unstable):

```sh
make && sudo make install
# and enjoy
```

For those who have no `make` command:

```sh
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
- disallowing `safe-rm` to use [AppleScript](https://en.wikipedia.org/wiki/AppleScript)

For the description of each config, you could refer to the sample file [here](./sample.safe-rm.conf)

If you want to use a custom configuration file

```sh
alias="SAFE_RM_CONF=/path/to/safe-rm.conf /path/to/bin/rm.sh"
```

Or if it is installed by npm:

```sh
alias="SAFE_RM_CONF=/path/to/safe-rm.conf safe-rm"
```
