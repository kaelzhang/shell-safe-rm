#!/bin/bash

n=-abcde

split_echo(){
    split=`echo $1 | fold -w1`

    local s

    for s in ${split[@]}
    do
        echo $s
    done
}

split_echo $n

echo $s

cut_echo(){
    echo "remove leading char ${1:1}"
}

cut_echo abcdefg


match(){
    if [[ ${1:0:1} =~ [aA] ]]; then
        echo start with a
    else
        echo no
    fi
}

match abc

match Acbdfd
match ddd

