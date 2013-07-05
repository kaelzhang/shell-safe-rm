#!/bin/bash


print(){
    case $1 in
        1[0-9][0-9]*)
            echo 1
            ;;

        1[0-9]*)
            echo 3
            ;;

        1)
            echo 4
            ;;

        *)
            echo 5
            ;;
    esac
}

print_2(){
    case $1 in
        1[0-9]+)
            echo 1
            ;;

        1[0-9]*)
            echo 2
            ;;
        *)
            echo 3
            ;;
    esac
}

print_3(){
    case $1 in
        .|..)
            echo 1
            ;;

        a)
            echo 2
            ;;

        aa)
            echo 3
            ;;
    esac
}

print 1234
print 123
print 12
print 1

echo ---------

print_2 1234
print_2 123
print_2 12
print_2 1

echo ---------

print_3 a
print_3 aa
print_3 ..
print_3 .