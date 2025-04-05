#!/usr/bin/env bash

PREFIX="/bin"

rm $PREFIX/safe-rm
echo "Please remove \"alias rm='$PREFIX/safe-rm'\" from your ~/.bashrc script"
echo "and do 'unalias rm' from all your terminal sessions"
echo "Successfully removed $PREFIX/safe-rm"
