#!/bin/bash
# user_deprovision.sh
# Advanced user deletion tool
# by Wilberth Barrantes
# for CentOS / RHEl

set -euo pipefail # exit on error, nounset, pipeline fail

logfile="/var/log/user_administration.log"

# Makes sure script is running as root
check_root(){
	if [[ $EUID -ne 0  ]]; then
		echo "Error: Script must run as root. Try: sudo $0"
		exit 1
	fi
	return 0
}

# Log saving
log_action(){
	echo "$(date '+%Y-%m-%d %H:%M:%S')- by ${SUDO_USER:-$(whoami)} on $(hostname) - $1" >> "$logfile"
	return 0
}

# Usage Syntax
correct_usage(){
	echo "How to use:"
	echo "$0 -u username [-f file] [--disable] [--delete] [--backup] [--force] [-h]"
	echo "$0 -f file_with_usernames" # For bulk deletion from txt file
	exit 1
}

# In case is asked to delete protected users as system users or logged users
check_protection(){
	if [ $(id -u "$1") -lt 1000 ]; then
		echo "Error: System user "$1" is protected. Cannot delete "
		exit 1
	elif pgrep -u "$1" > /dev/null; then
		echo "Error: User $1 is logged in. Cannot delete."
		exit 1
	fi
	return 0
}

validate_user(){
	if ! getent passwd "$1" &> /dev/null; then
		echo "Error: User $1 does not exist"
		return 1
	fi
	return 0
}

home_backup(){
	# Make sure $1 is the user name
	local home_dir=$(getent passwd "$1" | cut -d: -f6)
	local backup_dir="/var/backups/user_archives/"
	if ! [ -d "$backup_dir" ]; then
		mkdir -p "$backup_dir"
		echo "Advise: No previous Backup Directory, created: $backup_dir"
	fi
	if [ -d "$home_dir" ]; then
    		tar -czf "/var/backups/user_archives/${1}_$(date +%Y%m%d).tar.gz" -C "$(dirname "$home_dir")" "$(basename "$home_dir")"
    		echo "Backup created for $1 on $backup_dir"
		log_action "Backup created for $home_dir"
	else
		echo "Error: Home directory does not exist: $home_dir"
	fi
	return 0
}

disable_user(){
	# Make sure $1 is the user name
	passwd -l "$1"
	chage -E 0 "$1"
	log_action "Disabled user $1"
	echo "User $1 has been disabled."
	return 0
}

delete_user(){
	local username=$1
	local option
	
	read -p  "Confirm: Delete Home directory for $username? y/n - " option
	case "$option" in
		y|Y) userdel -r "$username"; log_action "Deleted user $username and home directory." ;;
		*) userdel "$username"; log_action "Deleted user $username (home directory preserved).";;
	esac
	return 0
}

# Forcefully terminates all processes owned by the user
force_kill(){
    local username=$1
    if pgrep -u "$username" > /dev/null; then
        echo "Forcing termination of all processes for $username..."
        pkill -9 -u "$username" # SIGKILL signal
        sleep 1 # To provide some time for the system to clean up
        log_action "Forcefully killed processes for $username"
    fi
    return 0
}

user_exec(){

	# Flags are below
	local username=$1

	validate_user "$username" || return 1 # Succed OR Exit

	if [ "$force_mode" = true ]; then
		force_kill "$username"
	else
		check_protection "$username"
	fi
        
        # Execution sequence	
	[[ "$do_backup" == true ]] && home_backup "$username"
	[[ "$do_disable" == true ]] && disable_user "$username"
	[[ "$do_delete" == true ]] && delete_user "$username"
	return 0
}


# === ===

check_root

username=""
file=""
do_backup=false
do_delete=false
do_disable=false
force_mode=false

while [[ $# -gt 0 ]]; do
	case $1 in
		-u) username="$2"; shift 2 ;;
		-f) file="$2"; shift 2 ;;
		--backup) do_backup=true; shift ;;
		--delete) do_delete=true; shift ;;
		--disable) do_disable=true; shift ;;
		--force) force_mode=true; shift ;;
		-h|--help) correct_usage ;;
		*) correct_usage ;;
	esac
done

# Make sure user use an option
if [ "$do_backup" = false ] && [ "$do_disable" = false ] && [ "$do_delete" = false ]; then
    echo "Error: No action specified (choose --backup, --disable, or --delete)."
    correct_usage
fi

# Bulk Mode? yes or no
if [ -n "$file" ]; then
    if [[ ! -f "$file" ]]; then # making sure the file exists
        echo "Error: $file not found."
        exit 1
    fi

    while read -u 3 -r line; do # read line by line assing to var line
        user_clean=$(echo "$line" | xargs)
        if [[ -n "$user_clean" ]]; then
            user_exec "$user_clean" || true # set -e would stop the script here without the true
        fi
    done 3< "$file"

elif [ -n "$username" ]; then
    user_exec "$username"

else
    correct_usage
fi
