#!/bin/bash

PREFIX=/bin

cp $PREFIX/rm.bak $PREFIX/rm
chmod 755 $PREFIX/rm
echo "Successfully recovered to the original rm"