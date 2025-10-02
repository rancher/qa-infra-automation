#!/bin/bash

NETWORK_PREFIX="10.115.40"
START=2
END=255

[ -n "$1" ] && NETWORK_PREFIX="$1"
[ -n "$2" ] && START="$2"
[ -n "$3" ] && END="$3"

TMPFILE=$(mktemp)

# Check port 22 (SSH) instead of ping
for i in $(seq $START $END); do
    IP="${NETWORK_PREFIX}.${i}"
    (
        if nc -z -w 1 "$IP" 22 &> /dev/null; then
            echo "$i reachable" >> "$TMPFILE"
        else
            echo "$i unreachable" >> "$TMPFILE"
        fi
    ) &
done
wait

sort -n -k1 "$TMPFILE" > "${TMPFILE}.sorted"

longest_start=""
longest_end=""
longest_len=0

current_start=""
current_len=0

while read -r idx status; do
    if [ "$status" = "unreachable" ]; then
        if [ -z "$current_start" ]; then
            current_start=$idx
        fi
        current_len=$((current_len + 1))
    else
        if [ -n "$current_start" ]; then
            if [ $current_len -gt $longest_len ]; then
                longest_start=$current_start
                longest_end=$((idx - 1))
                longest_len=$current_len
            fi
            current_start=""
            current_len=0
        fi
    fi
done < "${TMPFILE}.sorted"

# Handle case where the longest run ends at END
if [ -n "$current_start" ] && [ $current_len -gt $longest_len ]; then
    longest_start=$current_start
    longest_end=$END
    longest_len=$current_len
fi

if [ -n "$longest_start" ]; then
    printf "%s %s\n" "${NETWORK_PREFIX}.${longest_start}" "${NETWORK_PREFIX}.${longest_end}"
else
    printf "%s %s\n" "${NETWORK_PREFIX}.${START}" "${NETWORK_PREFIX}.${END}"
fi

rm -f "$TMPFILE" "${TMPFILE}.sorted"
