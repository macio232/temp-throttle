#!/bin/bash

# Usage: temp_throttle.sh max_temp
# USE CELSIUS TEMPERATURES.
# version 2.21

cat << EOF
Author: Sepero 2016 (sepero 111 @ gmx . com)
URL: http://github.com/Sepero/temp-throttle/

EOF

# Additional Links
# http://seperohacker.blogspot.com/2012/10/linux-keep-your-cpu-cool-with-frequency.html

# Additional Credits
# Wolfgang Ocker <weo AT weo1 DOT de> - Patch for unspecified cpu frequencies.

# License: GNU GPL 2.0

# Generic  function for printing an error and exiting.
err_exit () {
	echo ""
	echo "Error: $@" 1>&2
	exit 128
}

if [ $# -ne 1 ]; then
	# If temperature wasn't given, then print a message and exit.
	echo "Please supply a maximum desired temperature in Celsius." 1>&2
	echo "For example:  ${0} 60" 1>&2
	exit 2
else
	#Set the first argument as the maximum desired temperature.
	MAX_TEMP=$1
fi


### START Initialize Global variables.

# The frequency will increase when low temperature is reached.
LOW_TEMP=$((MAX_TEMP - 7))

# Temperatures internally are calculated to the thousandth.
MAX_TEMP=${MAX_TEMP}000
LOW_TEMP=${LOW_TEMP}000

FREQ_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"
FREQ_MIN="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"
FREQ_MAX="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"

# Store available cpu frequencies in a space separated string FREQ_LIST.
if [ -f $FREQ_FILE ]; then
	# If $FREQ_FILE exists, get frequencies from it.
	FREQ_LIST=$(cat $FREQ_FILE | xargs -n1 | sort -g -r | xargs) || err_exit "Could not read available cpu frequencies from file $FREQ_FILE"
elif [ -f $FREQ_MIN -a -f $FREQ_MAX ]; then
	# Else if $FREQ_MIN and $FREQ_MAX exist, generate a list of frequencies between them.
	FREQ_LIST=$(seq $(cat $FREQ_MAX) -100000 $(cat $FREQ_MIN)) || err_exit "Could not compute available cpu frequencies"
else
	err_exit "Could not determine available cpu frequencies"
fi

FREQ_LIST_LEN=$(echo $FREQ_LIST | wc -w)

# CURRENT_FREQ will save the index of the currently used frequency in FREQ_LIST.
CURRENT_FREQ=2

# This is a list of possible locations to read the current system temperature.
#TEMPERATURE_FILES="
#/sys/class/thermal/thermal_zone4/temp
#/sys/class/thermal/thermal_zone0/temp
#/sys/class/thermal/thermal_zone1/temp
#/sys/class/thermal/thermal_zone2/temp
#/sys/class/hwmon/hwmon0/temp1_input
#/sys/class/hwmon/hwmon1/temp1_input
#/sys/class/hwmon/hwmon2/temp1_input
#/sys/class/hwmon/hwmon0/device/temp1_input
#/sys/class/hwmon/hwmon1/device/temp1_input
#/sys/class/hwmon/hwmon2/device/temp1_input
#null
#"
#
## Store the first temperature location that exists in the variable TEMP_FILE.
## The location stored in $TEMP_FILE will be used for temperature readings.
#for file in $TEMPERATURE_FILES; do
#	TEMP_FILE=$file
#	[ -f $TEMP_FILE ] && break
#done
#
#[ $TEMP_FILE == "null" ] && err_exit "The location for temperature reading was not found."

TEMP_FILE=$(find /sys/class/thermal/ -type l -name "*thermal_zone*" | while read -r dir; do [[ $(cat "$dir/type") == "x86_pkg_temp" ]] && echo "$dir/temp"; done | head -n 1)
echo "TEMP_FILE=$TEMP_FILE"


### END Initialize Global variables.


### START define script functions.

# Set the maximum frequency for all cpu cores.
set_freq () {
	# From the string FREQ_LIST, we choose the item at index CURRENT_FREQ.
	FREQ_TO_SET=$(echo $FREQ_LIST | cut -d " " -f $CURRENT_FREQ)
	echo $FREQ_TO_SET
	cpupower frequency-set -u $FREQ_TO_SET > /dev/null
}

# Will reduce the frequency of cpus if possible.
throttle () {
	if [ $CURRENT_FREQ -lt $FREQ_LIST_LEN ]; then
	  if [ $CURRENT_FREQ -le 16 ]; then
	    JUMPFREQ=6
	  else
	    JUMPFREQ=1
	  fi
		CURRENT_FREQ=$((CURRENT_FREQ + JUMPFREQ))
		echo -n "throttle "
		set_freq $CURRENT_FREQ
	fi
}

# Will increase the frequency of cpus if possible.
unthrottle () {
	if [ $CURRENT_FREQ -ne 1 ]; then
		CURRENT_FREQ=$((CURRENT_FREQ - 1))
		echo -n "unthrottle "
		set_freq $CURRENT_FREQ
	fi
}

get_temp () {
	# Get the system temperature. Take the max of all counters
#	TEMP=$(cat $TEMPERATURE_FILES 2>/dev/null | xargs -n1 | sort -g -r | head -1)
	TEMP=$(cat $TEMP_FILE)
}

### END define script functions.

echo "Initialize to max CPU frequency"
unthrottle


# Main loop
while true; do
	get_temp # Gets the current temperature and set it to the variable TEMP.
	if   [ $TEMP -gt $MAX_TEMP ]; then # Throttle if too hot.
		throttle
	elif [ $TEMP -le $LOW_TEMP ]; then # Unthrottle if cool.
		unthrottle
	fi
	sleep 0.5 # The amount of time between checking temperatures.
done
