#!/bin/bash

print_header()
{
    header="${1}"
    header_len=${#header}
    printf "\n"
    if [ $header_len -lt 75 ]; then
        padding=$(((75 - $header_len) / 2))
        for ((i = 0; i < $padding; i++)); do
            printf " "
        done
    fi
    printf " %s \n\n" "${header}"
}

min_number() {
    printf "%s\n" "$@" | sort -g | head -n1
}

# This needs to be modified somehow
EPSILON=0.5

RET_TIME=""
evaluate() {
    speed=$1
    delay=$2
    loss=$3
    corrupt=$4
    reorder=$5
    max_time=$6

    ./link_emulator/link speed="$speed" delay="$delay" loss="$loss" corrupt="$corrupt" reorder="$reorder" &> /dev/null &
    sleep 1
    ./recv &> /dev/null &
    sleep 1

    TIMEFORMAT=%R
    #timeout poate creste executia programului putin (motiv pt care adaugam o secunda)
    #timpul este reverificat in do_check sa se incadreze in parametrii
    MAX_TIME=$(echo $MAX_TIME'+'1 | bc -l)
    RET_TIME=$( { time timeout $max_time ./send fileX "$speed" "$delay" &> /dev/null; } 2>&1 )
    if [ $? -ne 0 ] ; then
        RET_TIME=""
    fi

    RET_TIME=$(echo $RET_TIME | sed -E 's/\,/./')
}

do_check() {
    SPEEDS=$1
    DELAYS=$2
    CORRUPTS=$3
    REORDERS=$4
    LOSSES=$5
    POINTS=$6

    for i in "${!DELAYS[@]}"; do
        # Calculate max time
        var1=$(echo "1.25*1048576*8" | bc)
        var2=$(echo "$var1/${SPEEDS[$i]}" | bc)
        var3=$(echo "$var2*0.000001" | bc)
        var4=$(echo "${DELAYS[$i]}*0.001" | bc)
        var5=$(echo "${LOSSES[$i]}*0.01" | bc)
        var6=$(echo "${CORRUPTS[$i]}*0.01" | bc)
        MAX_TIME=$(echo "$var3+$var4+$var5+$var6+$EPSILON" | bc)

        TIMES=(999 999 999)
        for j in {0..2} ; do
            kill $(jobs -rp) &>/dev/null
            wait $(jobs -rp) &>/dev/null

            RET_TIME=""
            evaluate ${SPEEDS[$i]} ${DELAYS[$i]} ${LOSSES[$i]} ${CORRUPTS[$i]} ${REORDERS[$i]} $MAX_TIME
            if [ -z "$RET_TIME" ] ; then
                #time excedeed
                TIMES[$j]=999
                continue
            else
                TIMES[$j]=$RET_TIME
                if [[ $(echo $RET_TIME'<='$MAX_TIME | bc -l) -eq 1 ]]; then
                    break
                fi
            fi
        done

        TIME="$(min_number ${TIMES[0]} ${TIMES[1]} ${TIMES[2]})"
        TIME=$(echo $TIME | sed -E 's/\,/./')
        echo ${TIMES[0]}" "${TIMES[1]}" "${TIMES[2]}

        if [ -e "recv_fileX" ]; then
            if [[ $(echo $TIME'>'$MAX_TIME | bc -l) -eq 1 ]]; then
                echo -n "Test"$((i + 1))" ................................. "
                echo "FAILED - TIMEOUT"
                rm -rf recv_fileX
            else
                chmod u+r recv_fileX
                echo -n "Test"$((i + 1))" ................................. "
                diff fileX recv_fileX &>/dev/null
                if [ $? -eq 0 ]; then
                    echo "PASSED"
                    SUM=$((SUM + ${POINTS[$i]}))
                else
                    echo "FAILED - Files differ"
                fi
                rm -rf recv_fileX
            fi
        else
            echo -n "Test"$((i + 1))" ................................. "
            echo "FAILED - Received file not found"
            rm -rf recv_fileX
        fi

        echo "Max time: "$MAX_TIME
        echo "Running time: "$TIME

        kill $(jobs -rp) &>/dev/null
        wait $(jobs -rp) &>/dev/null
    done
}

# basic test
basic_test()
{
    #################
    SPEEDS=(20 20 20)
    DELAYS=(10 100 500)
    CORRUPTS=(0 0 0)
    REORDERS=(0 0 0)
    LOSSES=(0 0 0)
    POINTS=(7 6 7)
    #################

    echo -e "\n\n############### Running basic tests ####################\n"

    do_check $SPEEDS $DELAYS $CORRUPTS $REORDERS $LOSSES $POINTS
}

# normal test
normal_test()
{
    #################
    SPEEDS=(20 20 20 20)
    DELAYS=(10 100 10 100)
    CORRUPTS=(0 0 0 0)
    REORDERS=(0 0 0 0)
    LOSSES=(1 1 10 10)
    POINTS=(4 5 5 6)
    #################

    echo -e "\n\n############### Running normal tests ####################\n"

    do_check $SPEEDS $DELAYS $CORRUPTS $REORDERS $LOSSES $POINTS
}

# hard test
hard_test()
{
    #################
    SPEEDS=(5 20 20 20)
    DELAYS=(100 10 10 10)
    CORRUPTS=(1 10 1 10)
    REORDERS=(0 0 0 0)
    LOSSES=(0 0 1 10)
    POINTS=(5 5 4 6)
    #################

    echo -e "\n\n############### Running hard tests ####################\n"

    do_check $SPEEDS $DELAYS $CORRUPTS $REORDERS $LOSSES $POINTS
}

# stress test
stress_test()
{
    #################
    SPEEDS=(10 10 10 10)
    DELAYS=(10 10 10 10)
    CORRUPTS=(0 0 0 10)
    REORDERS=(1 10 10 10)
    LOSSES=(0 0 10 10)
    POINTS=(5 7 5 8)
    #################

    echo -e "\n\n############### Running stress tests ####################\n"

    do_check $SPEEDS $DELAYS $CORRUPTS $REORDERS $LOSSES $POINTS
}

print_header "Tema1 - Protocol cu fereastra glisanta"

# running tests

make &> /dev/stderr

killall link &>/dev/null
killall recv &>/dev/null
killall send &>/dev/null
basic_test
killall link &>/dev/null
killall recv &>/dev/null
killall send &>/dev/null
normal_test
killall link &>/dev/null
killall recv &>/dev/null
killall send &>/dev/null
hard_test
killall link &>/dev/null
killall recv &>/dev/null
killall send &>/dev/null
stress_test

make clean &> /dev/stderr

echo -en "\n\nFinal grade: "
    echo $SUM
