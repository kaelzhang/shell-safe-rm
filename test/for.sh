#!/bin/bash


print(){
    for path in $1/*
    do
        echo $path
    done
}


print $1

n=
a=2

[[ $n ]] && echo "n set" || {
    echo "n not set"
    a=1
}

echo $a