#!/bin/bash
#version 4.0 dated 12/17/2023
#By Brian Wallace

#initially based on the script found here by user kernelkaribou
#https://github.com/kernelkaribou/synology-monitoring

#This script pulls various information from the Synology NAS

#this script is not required if using data collectors like telegraf however it allows different control of the data collection and this supports additional logging from DVA unit NVidia graphics cards that cannot be collected through telegraf as it is pulled not from SNMP but from the NVidia drivers directly. 

#this script supports automatic email notifications if the system temperatures, or HDDs are too hot, GPU too hot, disk or raid status errors and more

#This script works in conjunction with a PHP powered web-based administration control panel to configure all of the script settings

#***************************************************
#Dependencies:
#***************************************************
#1.) this script is designed to be executed every 60 seconds. It has a configurable parameter "capture_interval" that allows the script to loop 6x, 4x, 2x, or 1x time(s) every 60 seconds. 
#2.) RAMDISK
	#NOTE: to reduce disk IOPS activity, it is recommended to create a RAMDISK for the temp files this script uses
	#to do so, create a scheduled task on boot up in Synology Task Scheduler to add the following line

		#mount -t tmpfs -o size=1% ramdisk $notification_file_location

		#where "$notification_file_location" is the location you want the files stored and is a variable configured below

#3.) this script only supports SNMP V3. This is because lower versions are less secure 
	#SNMP must be enabled on the host NAS for the script to gather the NAS NAME
	#the snmp settings for the NAS can all be entered into the web administration page
#4.) This script can be run through Synology Task Scheduler. However it has been observed that running large scripts like this as frequently as every 60 seconds causes the synoschedtask system application to use large amounts of resources and causes the script to execute slowly
	#details of this issue can be seen here:
	#https://www.reddit.com/r/synology/comments/kv7ufq/high_disk_usage_on_disk_1_caused_by_syno_task/
	#to fix this it is recommend to directly edit the crontab at /etc/crontab
	
	#this can be accomplished using vi /etc/crontab
	
	#add the following line: 
	#	*	*	*	*	*	root	$path_to_file/$filename
	#details on crontab can be found here: https://man7.org/linux/man-pages/man5/crontab.5.html
#5.) This script only supports InfluxdB version 2.x as version 1.x is no longer supported, it is recommended to upgrade to version 2 anyways
#6.) this script only supports DSM versions 6.x.x through 7.2.x  --- as of 12/17/2023. Versions below 6.x.x. are not supported. 



#############################################
#VERIFICATIONS
#############################################
#1.) data is collected into influx properly.............................................................................................................  VERIFIED 12/17/2023
#2.) SNMP errors:
	#a.) bad SNMP username causes script to shutdown with email.........................................................................................  VERIFIED 12/17/2023
	#b.) bad SNMP authpass causes script to shutdown with email.........................................................................................  VERIFIED 12/17/2023
	#c.) bad SNMP privacy pass causes script to shutdown with email.....................................................................................  VERIFIED 12/17/2023
	#d.) bad SNMP ip address causes script to shutdown with email.......................................................................................  VERIFIED 12/17/2023
	#e.) bad SNMP port causes script to shutdown with email.............................................................................................  VERIFIED 12/17/2023
	#f.) verify email is sent when RAID is not normal...................................................................................................  VERIFIED 12/17/2023
	#g.) verify email is sent when disk is not normal...................................................................................................  VERIFIED 12/17/2023
	#h.) error emails a through g above only are sent within the allowed time interval..................................................................  VERIFIED 12/17/2023
#3.) verify that when "sendmail" is unavailable (IE mail plus server is not working), emails are not sent, and the appropriate warnings are displayed...  VERIFIED 12/17/2023
#4.) verify script behavior when config file is unavailable.............................................................................................  VERIFIED 12/17/2023
#5.) verify script behavior when config file has wrong number of arguments..............................................................................  VERIFIED 12/17/2023
#6.) verify script behavior when the target device is not available / responding to pings...............................................................  VERIFIED 12/17/2023
#7.) verify disk temp emails are sent if disks are too hot..............................................................................................  VERIFIED 12/17/2023
#8.) verify cpu temp emails are sent if CPU is too hot..................................................................................................  VERIFIED 12/17/2023
#9.) verify GPU temp emails are sent if GPU is too hot..................................................................................................  VERIFIED 12/17/2023
#10) error emails for #7 through #9 above only are sent within the allowed time interval................................................................  VERIFIED 12/17/2023
#11.verify SS commanded to shutdown when utilization and temp are too low for 15 minutes................................................................  VERIFIED 12/17/2023
#12.verify after GPU utilization and temperature are normal the email tracking file is deleted..........................................................  VERIFIED 12/17/2023
#13.verify behavior when SS is successfully shutdown....................................................................................................  VERIFIED 12/17/2023
#14.verify behavior when SS fails to shutdown...........................................................................................................  VERIFIED 12/17/2023
#15.verify behavior when SS is successfully restarts....................................................................................................  VERIFIED 12/17/2023
#16.verify behavior when SS fails to restart............................................................................................................  VERIFIED 12/17/2023
#17.verify behavior when SS auto restart is NOT enabled.................................................................................................  VERIFIED 12/17/2023
#18.verify behavior script is not ROOT..................................................................................................................  VERIFIED 12/17/2023
#19.verify behavior when log directory is not available.................................................................................................  VERIFIED 12/17/2023
#20.verify behavior when log directory is not readable..................................................................................................  VERIFIED 12/17/2023
#21.verify behavior when log directory is not writable..................................................................................................  VERIFIED 12/17/2023
#22.verify behavior when DSM version is below 7.0.......................................................................................................  VERIFIED 12/17/2023
#23.verify behavior when DSM version is equal to 7.0....................................................................................................  VERIFIED 12/17/2023
#24.verify behavior when DSM version is equal to 7.1....................................................................................................  VERIFIED 12/17/2023


#########################################
#variable initialization
#########################################

#########################################################
#EMAIL SETTINGS USED IF CONFIGURATION FILE IS UNAVAILABLE
#These variables will be overwritten with new corrected data if the configuration file loads properly. 
email_address="email@email.com"
from_email_address="email@email.com"
#########################################################


#log_file_location="/volume1/web/logging/notifications"
#lock_file_location="$log_file_location/synology_snmp.lock"
#config_file_location="/volume1/web/config/config_files/config_files_local/system_config2.txt"
#SS_Station_restart_tracking="$log_file_location/SS_Station_restart_tracking.txt"
#use_mail_plus_server=0 #Note, while mail plus server is not required to send emails if desired, the email process is 17x times slower if NOT using mail plus server. In addition mailplus server queues the messages so if they fail to send, it will try again later, and it keeps a log of all messages sent. because of this it is recommended to use Mail Plus server

#NOTE THIS IS NOT THE NAME UNDER "CONTROL PANEL --> INFO CENTER"
#THIS VALUE IS DRAWN FROM "CONTROL PANEL --> TERMINAL & SNMP --> SNMP DEVICE INFORMATION --> DEVICE NAME
#nas_name="Your_NAS_Name" #this is only needed if the script cannot access the server name over SNMP, or if the config file is unavailable and will be used in any error messages

#depending on the number of drives, if the system has SSD's or regular HDD disks, the time required to execute the entire script takes time and may not be the same on all systems.
#this value can be adjusted to ensure the script executes all of its capture intervals within 60 seconds. 
#otherwise the script will not allow the next script to execute and a ~60 second period of time will NOT have data collected. 
#
#run the script with "time" before it such as "bash time synology_snmp.sh" and ensure the time required is less than 59 seconds, adjust the number to be below 59 seconds
#capture_interval_adjustment=6 



#for my personal use as i have multiple Synology systems, these lines can be deleted by other users and the 4x lines above can be un-commented. Also un-comment the capture_interval_adjustment variable above
######################################################################################
sever_type=1 #1=server2, 2=serverNVR, 3=serverplex

if [[ $sever_type == 1 ]]; then
	log_file_location="/volume1/web/logging/notifications"
	lock_file_location="$log_file_location/${0##*/}.lock"
	config_file_location="/volume1/web/config/config_files/config_files_local/system_config2.txt"
	SS_Station_restart_tracking="$log_file_location/SS_Station_restart_tracking.txt"
	capture_interval_adjustment=8
	use_mail_plus_server=1
	nas_name_error="Server2" #this is only needed if the script cannot access the server name over SNMP, or if the config file is unavailable and will be used in any error messages
fi

if [[ $sever_type == 2 ]]; then
	log_file_location="/volume1/web/logging/notifications"
	lock_file_location="$log_file_location/synology_snmp.lock"
	config_file_location="/volume1/web/logging/system_config_NVR2.txt"
	SS_Station_restart_tracking="$log_file_location/SS_Station_restart_tracking.txt"
	capture_interval_adjustment=13
	use_mail_plus_server=1
	nas_name_error="Server_NVR"  #this is only needed if the script cannot access the server name over SNMP, or if the config file is unavailable and will be used in any error messages
fi

if [[ $sever_type == 3 ]]; then
	log_file_location="/volume1/web/logging/notifications"
	lock_file_location="$log_file_location/synology_snmp.lock"
	config_file_location="/volume1/web/config/config_files/config_files_local/system_config2.txt"
	SS_Station_restart_tracking="$log_file_location/SS_Station_restart_tracking.txt"
	capture_interval_adjustment=3
	use_mail_plus_server=1
	nas_name_error="Server-PLEX"  #this is only needed if the script cannot access the server name over SNMP, or if the config file is unavailable and will be used in any error messages
fi

######################################################################################


#########################################
#Script Start
#########################################

debug=0
unsupported_OID=0
disk_temp_messge_tracker=();
disk_status_messge_tracker=();
raid_messge_tracker=();
SS_restart_delay_minuets=15 #how long to wait in minutes before restarting SurveillanceStation if GPU load is low

#check that the script is running as root or some of the commands required will not work
if [[ $( whoami ) != "root" ]]; then
	echo -e "ERROR - Script requires ROOT permissions, exiting script"
	exit 1
fi

#check that this is a Synology unit as this script uses Synology specific IODs and SNMP details.
if [ ! -r "/proc/sys/kernel/syno_hw_version" ]; then
	echo "This is not running on a Synology System, exiting script"
	exit 1
fi

#check that the required working directory is available, readable, and writable. it should be since we are root, but better check
if [ -d "$log_file_location" ]; then
	if [ -r "$log_file_location" ]; then
		if [ ! -r "$log_file_location" ]; then
			echo -e "ERROR - The script directory \"$log_file_location\" is not writable, exiting script"
			exit 1
		fi
	else
		echo -e "ERROR - The script directory \"$log_file_location\" is not readable, exiting script"
		exit 1
	fi
else
	echo -e "ERROR - The script directory \"$log_file_location\" is not available, exiting script"
	exit 1
fi

#create a lock file in the ramdisk directory to prevent more than one instance of this script from executing at once
if ! mkdir "$lock_file_location"; then
	echo -e "Failed to acquire lock.\n" >&2
	exit 1
fi
trap 'rm -rf $lock_file_location' EXIT #remove the lockdir on exit

#########################################################
#this function pings google.com to confirm internet access is working prior to sending email notifications 
#########################################################
check_internet() {
ping -c1 "google.com" > /dev/null #ping google.com									
	local status=$?
	if ! (exit $status); then
		false
	else
		true
	fi
}
#########################################################
#this function is used to send notifications
#########################################################
function send_mail(){
#email_last_sent_log_file=${1}			this file contains the UNIX time stamp of when the email is sent so we can track how long ago an email was last sent
#message_text=${2}						this string of text contains the body of the email message
#email_subject=${3}						this string of text contains the email subject line
#email_contents_file=${4}				this file is where the contents of the email are saved prior to sending and it contains the log of the email transmission, either will indicated email sent successfully or will include the error details
#error_message=${5}						this string of text is only displayed when the script is executed from the CLI, it will be part of the error message if the email is not sent correctly
#email_interval=${6}					this numerical value will control how many minutes must pass before the next email is allowed to be sent
#use_mail_plus_server=${7}				this will control if mail plus server (IE sendmail) or ssmtp will be used to send emails. ssmtp is much slower to execute but does not require the installation of mail plus server
	local message_tracker=""
	local time_diff=0
	echo "${2}"
	echo ""
	if check_internet; then
		local current_time=$( date +%s )
		if [ -r "${1}" ]; then #file is available and readable 
			read message_tracker < "${1}"
			time_diff=$((( $current_time - $message_tracker ) / 60 ))
		else
			echo -n "$current_time" > "${1}"
			time_diff=$(( ${6} + 1 ))
		fi
				
		if [ $time_diff -ge ${6} ]; then
			local now=$(date +"%T")
			echo "the email has not been sent in over ${6} minutes, re-sending email"
			if [[ ${7} == 1 ]]; then #if this is a value of 1, use mail plus
				#verify MailPlus Server package is installed and running as the "sendmail" command is not installed in Synology by default. the MailPlus Server package is required
				local install_check=$(/usr/syno/bin/synopkg list | grep MailPlus-Server)
				if [ "$install_check" != "" ];then
					#"MailPlus Server is installed, verify it is running and not stopped"
					local status=$(/usr/syno/bin/synopkg is_onoff "MailPlus-Server")
					if [ "$status" = "package MailPlus-Server is turned on" ]; then
						echo "from: $from_email_address " > "${4}"
						echo "to: $email_address " >> "${4}"
						echo "subject: ${3}" >> "${4}"
						echo "" >> "${4}"
						echo "$now - ${2}" >> "${4}" #adding the mailbody text. 
						local email_response=$(sendmail -t < "${4}"  2>&1)
						if [[ "$email_response" == "" ]]; then
							echo "" |& tee -a "${4}"
							echo -e "Email to \"$email_address\" Sent Successfully\n" |& tee -a "${4}"
							message_tracker=$current_time
							time_diff=0
							echo -n "$message_tracker" > "${1}"
						else
							echo -e "Warning, an error occurred while sending the ${5} notification email. the error was: $email_response\n" |& tee -a "${4}"
						fi
					else
						echo -e "Warning Mail Plus Server is Installed but not running, unable to send email notification\n" |& tee -a "${4}"
					fi
				else
					echo -e "Mail Plus Server is not installed, unable to send email notification\n" |& tee -a "${4}"
				fi
			else #since the value is not equal to 1, use ssmtp command
				echo "From: $from_email_address " > "${4}"
				echo "Subject: ${3}" >> "${4}"
				echo "" >> "${4}"
				echo -e "\n$now - ${2}\n" >> "${4}" #adding the mailbody text. 
				
				#the "ssmtp" command can only take one email address destination at a time. so if there are more than one email addresses in the list, we need to send them one at a time
				address_explode=(`echo $email_address | sed 's/;/\n/g'`) #explode on the semicolon separating the different possible addresses
				local xx=0
				for xx in "${!address_explode[@]}"; do
					local email_response=$(ssmtp ${address_explode[$xx]} < "${4}"  2>&1)
					if [[ "$email_response" == "" ]]; then
						echo "" |& tee -a "${4}"
						echo -e "Email to \"${address_explode[$xx]}\" Sent Successfully\n" |& tee -a "${4}"
						message_tracker=$current_time
						time_diff=0
						echo -n "$message_tracker" > "${1}"
					else
						echo -e "Warning, an error occurred while sending the ${5} notification email. the error was: $email_response\n" |& tee -a "${4}"
					fi
				done
			fi
		else
			echo -e "Only $time_diff minuets have passed since the last notification, email will be sent every ${6} minutes. $(( ${6} - $time_diff )) Minutes Remaining Until Next Email\n"
		fi
	else
		echo -e "Internet is not available, skipping sending email\n" |& tee -a "${4}"
	fi
}

#reading in variables from configuration file. this configuration file is edited using a web administration page. or the file can be edited directly. 
#If the file does not yet exist, opening the web administration page will create a file with default settings
if [ -r "$config_file_location" ]; then
	#file is available and readable 
	read input_read < "$config_file_location"
	explode=(`echo $input_read | sed 's/,/\n/g'`) #explode on the comma separating the variables
	
	#verify the correct number of configuration parameters are in the configuration file
	if [[ ! ${#explode[@]} == 44 ]]; then
		echo ""
		send_mail "$log_file_location/${0##*/}_Config_file_incorrect_last_message_sent.txt" "WARNING - the configuration file is incorrect or corrupted. It should have 44 parameters, it currently has ${#explode[@]} parameters." "Warning NAS \"$nas_name_error\" SNMP Monitoring Failed for script \"${0##*/}\" - Configuration file is incorrect" "$log_file_location/${0##*/}_email_contents.txt" "Config File Incorrect Alert" 60 $use_mail_plus_server
		exit 1
	fi
	
	max_disk_temp_f=${explode[0]}
	max_CPU0_f=${explode[1]}
	email_address=${explode[2]}
	email_interval=${explode[3]} #in minutes 
	capture_system=${explode[4]} #1=capture, 0=no capture
	capture_memory=${explode[5]} #1=capture, 0=no capture
	capture_cpu=${explode[6]} #1=capture, 0=no capture
	capture_volume=${explode[7]} #1=capture, 0=no capture
	capture_raid=${explode[8]} #1=capture, 0=no capture
	capture_disk=${explode[9]} #1=capture, 0=no capture
	capture_ups=${explode[10]} #1=capture, 0=no capture
	capture_network=${explode[11]} #1=capture, 0=no capture
	capture_interval=${explode[12]} #number of seconds to wait between captures. 
	nas_url=${explode[13]}
	influxdb_host=${explode[14]}
	influxdb_port=${explode[15]}
	influxdb_name=${explode[16]}
	influxdb_user=${explode[17]}
	influxdb_pass=${explode[18]}
	script_enable=${explode[19]}
	max_disk_temp=${explode[20]}
	max_CPU0=${explode[21]}
	snmp_authPass1=${explode[22]}
	snmp_privPass2=${explode[23]}
	number_drives_in_system=${explode[24]}
	GPU_installed=${explode[25]} #set to 1 if using a DVA system with a GPU installed
	nas_snmp_user=${explode[26]}
	snmp_auth_protocol=${explode[27]} #MD5  or SHA 
	snmp_privacy_protocol=${explode[28]} #AES or DES
	capture_GPU=${explode[29]}
	max_GPU_f=${explode[30]}
	max_GPU=${explode[31]}
	from_email_address=${explode[32]}
	influx_http_type=${explode[33]} #set to "http" or "https" based on your influxDB version
	influxdb_org=${explode[34]}
	enable_SS_restart=${explode[35]} #if the unit is a DVA unit with a GPU, the GPU runs hot and has high GPU usage. If the temperature and GPU usage are too low, then for some reason the system is no longer performing deep video analysis. This option allows the package to be restarted automatically to try fixing the issue
	SS_restart_GPU_usage_threshold=${explode[36]}
	SS_restart_GPU_temp_threshold=${explode[37]}
	capture_synology_services=${explode[38]}
	capture_FlashCache=${explode[39]}
	capture_iSCSI_LUN=${explode[40]}
	capture_SHA=${explode[41]}
	capture_NFS=${explode[42]}
	capture_iSCSI_Target=${explode[43]}
	
	if [ $debug -eq 1 ]; then
		echo "max_disk_temp_f is $max_disk_temp_f"
		echo "max_CPU0_f is $max_CPU0_f"
		echo "email_address is $email_address"
		echo "email_interval is $email_interval"
		echo "capture_system is $capture_system"
		echo "capture_memory is $capture_memory"
		echo "capture_cpu is $capture_cpu"
		echo "capture_volume is $capture_volume"
		echo "capture_raid is $capture_raid"
		echo "capture_disk is $capture_disk"
		echo "capture_ups is $capture_ups"
		echo "capture_network is $capture_network"
		echo "capture_interval is $capture_interval"
		echo "nas_url is $nas_url"
		echo "influxdb_host is $influxdb_host"
		echo "influxdb_port is $influxdb_port"
		echo "influxdb_name is $influxdb_name"
		echo "influxdb_user is $influxdb_user"
		echo "influxdb_pass is $influxdb_pass"
		echo "script_enable is $script_enable"
		echo "max_disk_temp is $max_disk_temp"
		echo "max_CPU0 is $max_CPU0"
		echo "snmp_authPass1 is $snmp_authPass1"
		echo "snmp_privPass2 is $snmp_privPass2"
		echo "number_drives_in_system is $number_drives_in_system"
		echo "GPU_installed is $GPU_installed"
		echo "nas_snmp_user is $nas_snmp_user"
		echo "snmp_auth_protocol is $snmp_auth_protocol" 
		echo "snmp_privacy_protocol is $snmp_privacy_protocol"
		echo "capture_GPU is $capture_GPU"
		echo "max_GPU_f is $max_GPU_f"
		echo "max_GPU is $max_GPU"
		echo "from_email_address is $from_email_address"
		echo "influx_http_type is $influx_http_type"
		echo "influxdb_org is $influxdb_org"
		echo "enable_SS_restart is $enable_SS_restart"
		echo "SS_restart_GPU_usage_threshold is $SS_restart_GPU_usage_threshold"
		echo "SS_restart_GPU_temp_threshold is $SS_restart_GPU_temp_threshold"
		echo "capture_synology_services is $capture_synology_services"
		echo "capture_FlashCache is $capture_FlashCache"
		echo "capture_iSCSI_LUN is $capture_iSCSI_LUN"
		echo "capture_SHA is $capture_SHA"
		echo "capture_NFS is $capture_NFS"
		echo "capture_iSCSI_Target is $capture_iSCSI_Target"
	fi


	if [ $script_enable -eq 1 ]
	then
	
		#confirm that the Synology NVidia drivers are actually installed. If they are not installed, set the correct flag
		if ! command -v nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader &> /dev/null
		then
			capture_GPU=0
			max_GPU_f=0
			max_GPU=0
			GPU_message_tracker=0
			GPU_installed=0
			if [ $debug -eq 1 ];then
				echo "NVidia Drivers are not installed"
			fi
		else
			GPU_installed=1
			if [ $debug -eq 1 ];then
				echo "NVidia Drivers are correctly installed"
			fi
		fi
		
		#confirm that the Synology SNMP settings were configured otherwise exit script
		if [ "$nas_snmp_user" = "" ];then
			send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "Synology NAS Username is BLANK, please configure the SNMP settings" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
			exit 1
		else
			if [ "$snmp_authPass1" = "" ];then
				send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "Synology NAS Authentication Password is BLANK, please configure the SNMP settings" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
				exit 1
			else
				if [ "$snmp_privPass2" = "" ];then
					send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "Synology NAS Privacy Password is BLANK, please configure the SNMP settings" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
					exit 1
				else
					if [ $debug -eq 1 ];then
						echo "Synology SNMP settings are not Blank"
					fi
				fi
			fi
		fi
		
		
		#determine DSM version to ensure as different DSM versions support different OIDs
		DSMVersion=$(                   cat /etc.defaults/VERSION | grep -i 'productversion=' | cut -d"\"" -f 2)
		nas_name=""
		# Getting NAS hostname from NAS, and capturing error output in the event we get an error during the SNMP_walk
		#NOTE THIS IS NOT THE NAME UNDER "CONTROL PANEL --> INFO CENTER"
		#THIS VALUE IS DRAWN FROM "CONTROL PANEL --> TERMINAL & SNMP --> SNMP DEVICE INFORMATION --> DEVICE NAME
		nas_name=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SNMPv2-MIB::sysName.0 -Ovqt 2>&1)

		#since $nas_name is the first time we have performed a SNMP request, let's make sure we did not receive any errors that could be caused by things like bad passwords, bad user name, incorrect auth or privacy types etc
		#if we receive an error now, then something is wrong with the SNMP settings and this script will not be able to function so we should exit out of it. 
		#the five main error are
		#1 - too short of a password
			#Error: pass phrase chosen is below the length requirements of the USM (min=8).
			#snmpwalk:  (The supplied password length is too short.)
			#Error generating a key (Ku) from the supplied privacy pass phrase.

		#2
			#Timeout: No Response from localhost:161

		#3
			#snmpwalk: Unknown user name

		#4
			#snmpwalk: Authentication failure (incorrect password, community or key)
			
		#5
			#we get nothing, the results are blank

		if [[ "$nas_name" == "Error:"* ]]; then #will search for the first error type
			send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "warning, the SNMP Auth password and or the Privacy password supplied is below the minimum 8 characters required. Exiting Script" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
			exit 1
		fi
		
		if [[ "$nas_name" == "Timeout:"* ]]; then #will search for the second error type
			send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "The SNMP target did not respond. This could be the result of a bad SNMP privacy password, the wrong IP address, the wrong port, or SNMP services not being enabled on the target device" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
			exit 1
		fi
		
		if [[ "$nas_name" == "snmpwalk: Unknown user name"* ]]; then #will search for the third error type
			send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "warning, The supplied username is incorrect. Exiting Script" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
			exit 1
		fi
		
		if [[ "$nas_name" == "snmpwalk: Authentication failure (incorrect password, community or key)"* ]]; then #will search for the fourth error type
			send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "The Authentication protocol or password is incorrect. Exiting Script" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
			exit 1
		fi
		
		if [[ "$nas_name" == "" ]]; then #will search for the fifth error type
			send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "Something is wrong with the SNMP settings, the results returned a blank/empty value. Exiting Script" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
			exit 1
		fi

		if [[ "$nas_name" == "snmpwalk: Timeout" ]]; then #will search for the fifth error type
			send_mail "$log_file_location/${0##*/}_SNMP-Error_last_message_sent.txt" "The SNMP target did not respond. This could be the result of a bad SNMP privacy password, the wrong IP address, the wrong port, or SNMP services not being enabled on the target device" "SNMP Setting Error for \"$nas_name_error\"" "$log_file_location/${0##*/}_email_contents.txt" "SNMP Error" $email_interval $use_mail_plus_server
			exit 1
		fi

		if [ ! $capture_interval -eq 10 ]; then
			if [ ! $capture_interval -eq 15 ]; then
				if [ ! $capture_interval -eq 30 ]; then
					if [ ! $capture_interval -eq 60 ]; then
						echo "capture interval is not one of the allowable values of 10, 15, 30, or 60 seconds. Exiting the script"
						exit 1
					fi
				fi
			fi
		fi

		#loop the script 
		total_executions=$(( 60 / $capture_interval))
		echo "Capturing $total_executions times"
		i=0
		while [ $i -lt $total_executions ]; do
			
			#Create empty URL
			post_url=

			#########################################
			#GETTING VARIOUS SYSTEM INFORMATION
			#########################################
			
			if [ $capture_system -eq 1 ]
			then
				
				measurement="synology_system"
				
				#System up time
				system_uptime=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 HOST-RESOURCES-MIB::hrSystemUptime.0 -Ovt)
				
				#System Status,  1 is on line, 0 is failed/off line
				system_status=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-SYSTEM-MIB::systemStatus.0 -Oqv)
				
				#Fan status, 1 is on line, 0 is failed/off line
				system_fan_status=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-SYSTEM-MIB::systemFanStatus.0 -Oqv)
				
				#Fan status, 1 is on line, 0 is failed/off line
				cpu_Fan_Status=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-SYSTEM-MIB::cpuFanStatus.0 -Oqv)
				
				#Various SYNOLOGY-SYSTEM stats for common OID
				while IFS= read -r line; do
				
					if [[ $line == SYNOLOGY-SYSTEM-MIB::modelName.0* ]]; then 
						model=${line/"SYNOLOGY-SYSTEM-MIB::modelName.0 = STRING: "/}
					
					elif [[ $line == SYNOLOGY-SYSTEM-MIB::serialNumber.0* ]]; then
						serial=${line/"SYNOLOGY-SYSTEM-MIB::serialNumber.0 = STRING: "/}
					
					elif [[ $line == SYNOLOGY-SYSTEM-MIB::upgradeAvailable.0* ]]; then
						upgrade=${line/SYNOLOGY-SYSTEM-MIB::upgradeAvailable.0 = INTEGER: /}
					
					elif [[ $line == SYNOLOGY-SYSTEM-MIB::version.0* ]]; then
						version=${line/"SYNOLOGY-SYSTEM-MIB::version.0 = STRING: "/}
					
					fi
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.4.1.6574.1.5) #Parent OID for SYNOLOGY-SYSTEM-MIB
				
				# Synology NAS Temperature
				system_temp=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.4.1.6574.1.2 -Oqv)
				
				#System details to post
				post_url=$post_url"$measurement,nas_name=$nas_name uptime=$system_uptime,system_status=$system_status,fan_status=$system_fan_status,model=$model,serial_number=$serial,upgrade_status=$upgrade,dsm_version=$version,system_temp=$system_temp,cpu_Fan_Status=$cpu_Fan_Status
		"
				#capturing expansion unit details
				expansion_info=()
				unsupported_OID=0
				while IFS= read -r line; do
					if [[ $line == "SYNOLOGY-EBOX-MIB::synologyEbox = No Such Object available on this agent at this OID"* ]]; then
						unsupported_OID=1
					else
						if [[ $line == SYNOLOGY-EBOX-MIB::eboxIndex* ]]; then
							id=${line/"SYNOLOGY-EBOX-MIB::eboxIndex."/}; id=${id%" = INTEGER:"*}
							expansion_ID=${line#*INTEGER: };
							expansion_info+=([$id]=$expansion_ID)
						fi
					fi
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.105)
				
				if [ $unsupported_OID -eq 0 ]; then
					for id in "${!expansion_info[@]}"
					do
						expansion_ID=${expansion_info[$id]}
					
						while IFS= read -r line; do
							if [[ "$line" == "SYNOLOGY-EBOX-MIB::eboxModel.$id ="* ]]; then
								expanion_model=${line/"SYNOLOGY-EBOX-MIB::eboxModel."$id" = STRING: "/}
							fi
							if [[ "$line" == "SYNOLOGY-EBOX-MIB::eboxPower.$id ="* ]]; then
								expansion_status=${line/"SYNOLOGY-EBOX-MIB::eboxPower."$id" = INTEGER: "/}
								#1 = The power supplies well || 2 = The power supplies badly || 3 = The power is not connected
							fi
						done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.105)
						
						post_url=$post_url"$measurement,nas_name=$nas_name,expansion_ID=$expansion_ID expanion_model=$expanion_model,expansion_status=$expansion_status
			"
					done
				else
					echo "No Expansion Unit is Attached or Active, Expansion unit logging will be skipped"
				fi

				if [ $system_temp -ge $max_CPU0 ]; then
					send_mail "$log_file_location/${0##*/}_system_temp_last_message_sent.txt" "Warning the temperature of the system CPU on $nas_name has exceeded $max_CPU0 Degrees C / $max_CPU0_f Degrees F. The Temperature is currently $system_temp degrees" "WARNING - $nas_name CPU exceeded $max_CPU0 Degrees C / $max_CPU0_f Degrees F" "$log_file_location/${0##*/}_email_contents.txt" "System Temperature High" $email_interval $use_mail_plus_server
				fi
			else
				echo "Skipping system capture"
			fi
			
			#########################################
			# GETTING MEMORY STATS
			#########################################
			
			if [ $capture_memory -eq 1 ]
			then
				
				measurement="synology_memory"
				
				#Various Memory stats for common Memory OID 
				while IFS= read -r line; do
				
					if [[ $line == UCD-SNMP-MIB::memTotalReal.0* ]]; then
						mem_total=${line/"UCD-SNMP-MIB::memTotalReal.0 = INTEGER: "/}
						mem_total=${mem_total/" kB"/}
				
					elif [[ $line == UCD-SNMP-MIB::memAvailReal.0* ]]; then
						mem_avail_real=${line/"UCD-SNMP-MIB::memAvailReal.0 = INTEGER: "/}
						mem_avail_real=${mem_avail_real/" kB"/}
				
					elif [[ $line == UCD-SNMP-MIB::memBuffer.0* ]]; then
						mem_buffer=${line/"UCD-SNMP-MIB::memBuffer.0 = INTEGER: "/}
						mem_buffer=${mem_buffer/" kB"/}
				
					elif [[ $line == UCD-SNMP-MIB::memCached.0* ]]; then
						mem_cached=${line/"UCD-SNMP-MIB::memCached.0 = INTEGER: "/}
						mem_cached=${mem_cached/" kB"/}
					
					elif [[ $line == UCD-SNMP-MIB::memTotalFree.0* ]]; then
						mem_free=${line/"UCD-SNMP-MIB::memTotalFree.0 = INTEGER: "/}
						mem_free=${mem_free/" kB"/}
				
					fi
					
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.4.1.2021.4) #Parent OID for UCD-SNMP-MIB Memory stats
			
				post_url=$post_url"$measurement,nas_name=$nas_name mem_total=$mem_total,mem_avail_real=$mem_avail_real,mem_buffer=$mem_buffer,mem_cached=$mem_cached,mem_free=$mem_free
		"
			else
				echo "Skipping memory capture"
			fi
			
			#########################################
			# GETTING CPU USAGE
			#########################################
			
			if [ $capture_cpu -eq 1 ]
			then
				
				measurement="synology_cpu"
				usage_idle=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 UCD-SNMP-MIB::ssCpuIdle.0 -Oqv)
				
				ssCpuUser=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 UCD-SNMP-MIB::ssCpuUser.0 -Oqv)
				
				ssCpuSystem=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 UCD-SNMP-MIB::ssCpuSystem.0 -Oqv)
				
				cpu_usage=$(($ssCpuUser + $ssCpuSystem))
				
				post_url=$post_url"$measurement,nas_name=$nas_name usage_idle=$usage_idle,ssCpuUser=$ssCpuUser,ssCpuSystem=$ssCpuSystem,cpu_usage=$cpu_usage
		"
			else
				echo "Skipping CPU capture"
			fi
			
			#########################################
			# GETTING VOLUME information based upon the SYNOLOGY-RAID-MIB it is basically the summarized version of what information we want.
			#########################################
			
			if [ $capture_volume -eq 1 ]
			then
				measurement="synology_volume"
				
				while IFS= read -r line; do
					
					if [[ $line =~ "/volume"+([0-9]$) ]]; then
						id=${line/"HOST-RESOURCES-MIB::hrStorageDescr."/}; id=${id%" = STRING:"*}
						vol_name=${line#*STRING: }
						
						# Allocation units for volume in bytes (typically 4096)
						vol_blocksize=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 HOST-RESOURCES-MIB::hrStorageAllocationUnits.$id -Ovq | awk {'print $1'})
						
						# Total Volume Size is size before being multiplied by allocation units
						vol_totalsize=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 HOST-RESOURCES-MIB::hrStorageSize.$id -Oqv)
						
						# Volume Usage
						vol_used=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 HOST-RESOURCES-MIB::hrStorageUsed.$id -Oqv)
						
						# Need to actually convert the sizes provided by their allocation unit, leaving in bytes format
						# Calculation to TB is =(vol_totalsize*vol_blocksize)/1024/1024/1024/1024
						vol_totalsize=$(($vol_totalsize * $vol_blocksize))
						vol_used=$(($vol_used * $vol_blocksize))
						post_url=$post_url"$measurement,nas_name=$nas_name,volume=$vol_name vol_totalsize=$vol_totalsize,vol_used=$vol_used
		"
					fi
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.2.1.25.2.3.1.3)

				#########################################
				#GETTING Volume IO STATS
				#########################################
				
				volume_info=()
				
				while IFS= read -r line; do
						id=${line/"SYNOLOGY-SPACEIO-MIB::spaceIODevice."/}; id=${id%" = STRING:"*}
						volume_path=${line#*STRING: };
						volume_info+=([$id]=$volume_path)
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-SPACEIO-MIB::spaceIODevice)
				
				for id in "${!volume_info[@]}"
				do
					volume_path=""${volume_info[$id]}
					
					while IFS= read -r line; do
						if [[ "$line" == "SYNOLOGY-SPACEIO-MIB::spaceIONReadX.$id ="* ]]; then
							volume_reads=${line/"SYNOLOGY-SPACEIO-MIB::spaceIONReadX."$id" = Counter64: "/};
						
						elif [[ "$line" == "SYNOLOGY-SPACEIO-MIB::spaceIONWrittenX.$id ="* ]]; then
							volume_writes=${line/"SYNOLOGY-SPACEIO-MIB::spaceIONWrittenX."$id" = Counter64: "/}
						
						elif [[ "$line" == "SYNOLOGY-SPACEIO-MIB::spaceIOLA.$id ="* ]]; then
							volume_load=${line/"SYNOLOGY-SPACEIO-MIB::spaceIOLA."$id" = INTEGER: "/}
						fi
					done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.4.1.6574.102)
					
					post_url=$post_url"$measurement,nas_name=$nas_name,volume_path=$volume_path volume_reads=$volume_reads,volume_writes=$volume_writes,volume_load=$volume_load
		"
				done
			else
				echo "Skipping volume capture"
			fi
			
			#########################################
			#GETTING RAID INFO
			#########################################
			
			if [ $capture_raid -eq 1 ]
			then
				measurement="synology_raid"
					
				raid_info=()
				
				while IFS= read -r line; do
					
					id=${line/"SYNOLOGY-RAID-MIB::raidName."/}; id=${id%" = STRING:"*}
					raid_name=${line#*STRING: };raid_name=${raid_name// /};raid_name=${raid_name//\"}
					raid_info+=([$id]=$raid_name)

				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-RAID-MIB::raidName)
				
				for id in "${!raid_info[@]}"
				do
				
					while IFS= read -r line; do
					
						raid_name=${raid_info[$id]}
					
						if [[ "$line" == "SYNOLOGY-RAID-MIB::raidStatus.$id ="* ]]; then
							raid_status=${line/"SYNOLOGY-RAID-MIB::raidStatus."$id" = INTEGER: "/}
							#1=Normal
							#2=Repairing
							#3=Migrating
							#4=Expanding
							#5=Deleting
							#6=Creating
							#7=RaidSyncing
							#8=RaidParityChecking
							#9=RaidAssembling
							#10=Canceling
							#11=Degrade
							#12=Crashed
							#13=DataScrubbing
							#14=RaidDeploying
							#15=RaidUnDeploying
							#16=RaidMountCache
							#17=RaidUnmountCache
							#18=RaidExpandingUnfinishedSHR
							#19=RaidConvertSHRToPool
							#20=RaidMigrateSHR1ToSHR2
							#21=RaidUnknownStatus

							if [ $raid_status -eq 2 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Repairing\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 3 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Migrating\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 4 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Expanding\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 5 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Deleting\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 11 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Degraded\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 12 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Crashed\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 15 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Un-Deploying\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 18 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Expanding Unfinished SHR\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 19 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Convert SHR To Pool\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 20 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Migrate SHR1 To SHR2\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							elif [ $raid_status -eq 21 ]; then
								send_mail "$log_file_location/${0##*/}_raid_status_last_message_sent_$raid_name.txt" "Warning the status of $raid_name on $nas_name is reporting as \"Unknown Status\"" "$raid_name Status Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Raid Status Alert" $email_interval $use_mail_plus_server
							fi
							
						elif [[ "$line" == "SYNOLOGY-RAID-MIB::raidFreeSize.$id ="* ]]; then
							raid_free_size=${line/"SYNOLOGY-RAID-MIB::raidFreeSize."$id" = Counter64: "/}
						
						elif [[ "$line" == "SYNOLOGY-RAID-MIB::raidTotalSize.$id ="* ]]; then
							raid_total_size=${line/"SYNOLOGY-RAID-MIB::raidTotalSize."$id" = Counter64: "/}
						fi
						
						/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
						if [ "$?" -eq "0" ]; then
							echo "DSM is below version 7.0 skipping capturing raidHotspareCnt"
						else
							if [[ "$line" == "SYNOLOGY-RAID-MIB::raidHotspareCnt.$id ="* ]]; then
								raidHotspareCnt=${line/"SYNOLOGY-RAID-MIB::raidHotspareCnt."$id" = INTEGER: "/}
							fi
						fi
				
					done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.4.1.6574.3.1.1)
				
					/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
					if [ "$?" -eq "0" ]; then
						#version is DSM6
						post_url=$post_url"$measurement,nas_name=$nas_name,raid_name=$raid_name raid_status=$raid_status,raid_free_size=$raid_free_size,raid_total_size=$raid_total_size
		"
					else
						#version is DSM7
						post_url=$post_url"$measurement,nas_name=$nas_name,raid_name=$raid_name raid_status=$raid_status,raid_free_size=$raid_free_size,raid_total_size=$raid_total_size,raidHotspareCnt=$raidHotspareCnt
		"
					fi
				done
			else
				echo "Skipping RAID capture"
			fi
			
			#########################################
			#GETTING DISK INFO
			#########################################
			
			if [ $capture_disk -eq 1 ]
			then
				measurement="synology_disk"
				
				disk_info=()
				
				while IFS= read -r line; do
					
					id=${line/"SYNOLOGY-DISK-MIB::diskID."/}; id=${id%" = STRING:"*}
					disk_name=${line#*STRING: }; disk_name=${disk_name// /};disk_name=${disk_name//\"}
					disk_info+=([$id]=$disk_name)
				
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-DISK-MIB::diskID)
				
				for id in "${!disk_info[@]}"
				do
					while IFS= read -r line; do
					
					disk_name=${disk_info[$id]}
					
					if [[ "$line" == "SYNOLOGY-DISK-MIB::diskModel.$id ="* ]]; then
						disk_model=${line/"SYNOLOGY-DISK-MIB::diskModel."$id" = STRING: "/}; disk_model=${disk_model// /}
					
					elif [[ "$line" == "SYNOLOGY-DISK-MIB::diskType.$id ="* ]]; then
						disk_type=${line/"SYNOLOGY-DISK-MIB::diskType."$id" = STRING: "/}
					
					elif [[ "$line" == "SYNOLOGY-DISK-MIB::diskStatus.$id ="* ]]; then
						disk_status=${line/"SYNOLOGY-DISK-MIB::diskStatus."$id" = INTEGER: "/}
						#1=The disk is functioning normally
						#2=The disk has system partitions but no data
						#3=The disk is not partitioned
						#4=Partitions on the disk are damaged
						#5=The disk is damaged/crashed
						if [ $disk_status -eq 2 ]; then
							send_mail "$log_file_location/${0##*/}_Disk_Status_last_message_sent_$disk_name.txt" "Warning the state of $disk_name on $nas_name is reporting as \"The disk has system partitions but no data\"" "$disk_name State Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Status Alert" $email_interval $use_mail_plus_server
						elif [ $disk_status -eq 3 ]; then
							send_mail "$log_file_location/${0##*/}_Disk_Status_last_message_sent_$disk_name.txt" "Warning the state of $disk_name on $nas_name is reporting as \"The disk is not partitioned\"" "$disk_name State Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Status Alert" $email_interval $use_mail_plus_server
						elif [ $disk_status -eq 4 ]; then
							send_mail "$log_file_location/${0##*/}_Disk_Status_last_message_sent_$disk_name.txt" "Warning the state of $disk_name on $nas_name is reporting as \"Partitions on the disk are damaged\"" "$disk_name State Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Status Alert" $email_interval $use_mail_plus_server
						elif [ $disk_status -eq 5 ]; then
							send_mail "$log_file_location/${0##*/}_Disk_Status_last_message_sent_$disk_name.txt" "Warning the state of $disk_name on $nas_name is reporting as \"The disk is damaged/crashed\"" "$disk_name State Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Status Alert" $email_interval $use_mail_plus_server
						fi
					
					elif [[ "$line" == "SYNOLOGY-DISK-MIB::diskTemperature.$id ="* ]]; then
						disk_temp=${line/"SYNOLOGY-DISK-MIB::diskTemperature."$id" = INTEGER: "/}
					fi
					
					#depending on version of DSM, we may or may not collect additional data
					/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
					if [ "$?" -eq "0" ]; then
						echo "DSM is below version 7.0 skipping capturing disk_role, disk_retry, disk_BadSector, disk_IdentifyFail, disk_RemainLife, diskHealthStatus"
					else
						if [[ "$line" == "SYNOLOGY-DISK-MIB::diskRole.$id ="* ]]; then
							disk_role=${line/"SYNOLOGY-DISK-MIB::diskRole."$id" = STRING: "/}
							#"data" = Used by storage pool
							#"hotspare" = Assigned as a hot spare disk
							#"ssd_cache" = Used by SSD Cache
							#"none" = Not used by storage pool, nor hot spare, nor SSD Cache
							#"unknown" = Some error occurred
						
						elif [[ "$line" == "SYNOLOGY-DISK-MIB::diskRetry.$id ="* ]]; then
							disk_retry=${line/"SYNOLOGY-DISK-MIB::diskRetry."$id" = INTEGER: "/}
						
						elif [[ "$line" == "SYNOLOGY-DISK-MIB::diskBadSector.$id ="* ]]; then
							disk_BadSector=${line/"SYNOLOGY-DISK-MIB::diskBadSector."$id" = INTEGER: "/}
						
						elif [[ "$line" == "SYNOLOGY-DISK-MIB::diskIdentifyFail.$id ="* ]]; then
							disk_IdentifyFail=${line/"SYNOLOGY-DISK-MIB::diskIdentifyFail."$id" = INTEGER: "/}
						
						elif [[ "$line" == "SYNOLOGY-DISK-MIB::diskRemainLife.$id ="* ]]; then
							disk_RemainLife=${line/"SYNOLOGY-DISK-MIB::diskRemainLife."$id" = INTEGER: "/}
						
						fi
						
						#depending on version of DSM, we may or may not collect additional data
						/usr/bin/dpkg --compare-versions "7.1" gt "$DSMVersion"
						if [ "$?" -eq "0" ]; then
							echo "DSM is below version 7.1 skipping capturing \"diskHealthStatus\"" 
						else
							#this OID is supported only on 7.1 and higher
							if [[ "$line" == "SYNOLOGY-DISK-MIB::diskHealthStatus.$id ="* ]]; then
								diskHealthStatus=${line/"SYNOLOGY-DISK-MIB::diskHealthStatus."$id" = INTEGER: "/}
								#Normal(1) The disk health status is normal.
								#Warning(2) The disk health status is warning.
								#Critical(3) The disk health status is critical.
								#Failing(4) The disk health status is failing.
								if [ $diskHealthStatus -eq 2 ]; then
									send_mail "$log_file_location/${0##*/}_Disk_Status_last_message_sent_$disk_name.txt" "Warning the state of $disk_name on $nas_name is reporting as \"The disk health status is warning\"" "$disk_name State Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Status Alert" $email_interval $use_mail_plus_server
								elif [ $diskHealthStatus -eq 3 ]; then
									send_mail "$log_file_location/${0##*/}_Disk_Status_last_message_sent_$disk_name.txt" "Warning the state of $disk_name on $nas_name is reporting as \"The disk health status is critical\"" "$disk_name State Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Status Alert" $email_interval $use_mail_plus_server
								elif [ $diskHealthStatus -eq 4 ]; then
									send_mail "$log_file_location/${0##*/}_Disk_Status_last_message_sent_$disk_name.txt" "Warning the state of $disk_name on $nas_name is reporting as \"The disk health status is failing\"" "$disk_name State Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Status Alert" $email_interval $use_mail_plus_server
								fi
							fi
						fi
					fi
					
					done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.4.1.6574.2.1.1)
					
					/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
					if [ "$?" -eq "0" ]; then
						#if this is DSM6, only post DSM6 related data
						post_url=$post_url"$measurement,nas_name=$nas_name,disk_name=$disk_name disk_model=$disk_model,disk_type=$disk_type,disk_temp=$disk_temp,disk_status=$disk_status
		"
					else
					#if this is DSM7, only post DSM7 related data
						post_url=$post_url"$measurement,nas_name=$nas_name,disk_name=$disk_name disk_model=$disk_model,disk_type=$disk_type,disk_temp=$disk_temp,disk_status=$disk_status,disk_role=$disk_role,disk_retry=$disk_retry,disk_BadSector=$disk_BadSector,disk_IdentifyFail=$disk_IdentifyFail,disk_RemainLife=$disk_RemainLife
		"						
					fi
					/usr/bin/dpkg --compare-versions "7.1" gt "$DSMVersion"
					if [ "$?" -eq "0" ]; then
						dsm_type="Synology (DSM 7.0)" #version is DSM7.0, do nothing extra
					else
						post_url=$post_url"$measurement,nas_name=$nas_name,disk_name=$disk_name diskHealthStatus=$diskHealthStatus
		"
					fi
		
					#check that none of the disks are too hot. if a disk is too hot, send an email warning that the disk is over heating
					if [ $disk_temp -ge $max_disk_temp ]; then
						send_mail "$log_file_location/${0##*/}_Disk_Temp_last_message_sent_$disk_name.txt" "Warning the temperature of $disk_name on $nas_name has exceeded $max_disk_temp Degrees C / $max_disk_temp_f Degrees F. The current Temperature is $disk_temp degrees C" "$disk_name Temperature Warning on $nas_name" "$log_file_location/${0##*/}_email_contents.txt" "Disk Temp Alert" $email_interval $use_mail_plus_server
					fi
				done
				
				#########################################
				#GETTING Disk IO STATS
				#########################################
				
				disk_info=()
				
				while IFS= read -r line; do
						id=${line/"SYNOLOGY-STORAGEIO-MIB::storageIODevice."/}; id=${id%" = STRING:"*}
						disk_path=${line#*STRING: };
						disk_info+=([$id]=$disk_path)
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-STORAGEIO-MIB::storageIODevice)
				
				for id in "${!disk_info[@]}"
				do
					disk_path="/dev/"${disk_info[$id]}
					
					while IFS= read -r line; do
						if [[ "$line" == "SYNOLOGY-STORAGEIO-MIB::storageIONReadX.$id ="* ]]; then
							disk_reads=${line/"SYNOLOGY-STORAGEIO-MIB::storageIONReadX."$id" = Counter64: "/};
						
						elif [[ "$line" == "SYNOLOGY-STORAGEIO-MIB::storageIONWrittenX.$id ="* ]]; then
							disk_writes=${line/"SYNOLOGY-STORAGEIO-MIB::storageIONWrittenX."$id" = Counter64: "/}
						
						elif [[ "$line" == "SYNOLOGY-STORAGEIO-MIB::storageIOLA.$id ="* ]]; then
							disk_load=${line/"SYNOLOGY-STORAGEIO-MIB::storageIOLA."$id" = INTEGER: "/}
						
						elif [[ "$line" == "SYNOLOGY-STORAGEIO-MIB::storageIODeviceSerial.$id ="* ]]; then
							disk_serial=${line/"SYNOLOGY-STORAGEIO-MIB::storageIODeviceSerial."$id" = STRING: "/}
						fi
					done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.4.1.6574.101)
					
					post_url=$post_url"$measurement,nas_name=$nas_name,disk_path=$disk_path disk_reads=$disk_reads,disk_writes=$disk_writes,disk_load=$disk_load,disk_serial=\"$disk_serial\"
		"
				done
			else
				echo "Skipping Disk capture"
			fi
			
			#########################################
			#GETTING UPS STATUS
			#########################################
			
			if [ $capture_ups -eq 1 ]
			then
				measurement="synology_ups"
				
				#UPS Battery charge level
				ups_battery_charge=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-UPS-MIB::upsBatteryChargeValue.0 -Oqv  2>&1)
				
				if [[ $ups_battery_charge == "No Such Instance currently exists at this OID"* ]]; then
					echo "No UPS connected, UPS collection will be skipped"
				else
					ups_battery_charge=${ups_battery_charge%\.*}
					
					#UPS Load
					ups_load=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-UPS-MIB::upsInfoLoadValue.0 -Oqv);ups_load=${ups_load%\.*}
					
					#UPS State (OL is online, OL CHRG is plugged in but charging, OL DISCHRG is on battery")
					ups_status=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-UPS-MIB::upsInfoStatus.0 -Oqv); ups_status=${ups_status//\"}
					
					if [[ $ups_status == "OL" ]];
						then
							ups_status=1
					elif [[ $ups_status == "OL CHRG" ]];
						then
							ups_status=2
					elif [[ $ups_status == "OL DISCHRG" ]];
						then
							ups_status=3
					elif [[ $ups_status == "FSD OL" ]];
						then
							ups_status=4
					elif [[ $ups_status == "FSD OB LB" ]];
						then
							ups_status=5
					elif [[ $ups_status == "OB" ]];
						then
							ups_status=6
					fi
					
					#Battery Runtime
					ups_battery_runtime=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-UPS-MIB::upsBatteryRuntimeValue.0 -Oqv | awk {'print $1'})
					
					post_url=$post_url"$measurement,nas_name=$nas_name,ups_group=\"NAS\" ups_status=$ups_status,ups_load=$ups_load,ups_battery_runtime=$ups_battery_runtime,ups_battery_charge=$ups_battery_charge
			"
				fi
			else
				echo "Skipping UPS capture"
			fi
			
			#########################################
			#GETTING NETWORK STATS
			#########################################
			
			if [ $capture_network -eq 1 ]
			then
				measurement="synology_network"
				
				network_info=()
				
				while IFS= read -r line; do
				
						id=${line/"IF-MIB::ifName."/}; id=${id%" = STRING:"*}
						interface_name=${line#*STRING: };
						network_info+=([$id]=$interface_name)
				
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 IF-MIB::ifName | grep -E 'eth*|bond*')
				
				for id in "${!network_info[@]}"
				do
					interface_name=${network_info[$id]}
					
					while IFS= read -r line; do
						if [[ $line =~ "IF-MIB::ifHCInOctets.$id =" ]]; then
							bytes_recv=${line/"IF-MIB::ifHCInOctets."$id" = Counter64: "/};
						
						elif [[ $line =~ "IF-MIB::ifHCOutOctets.$id =" ]]; then
							bytes_sent=${line/"IF-MIB::ifHCOutOctets."$id" = Counter64: "/};
						fi
				
					done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 1.3.6.1.2.1.31.1.1.1)
					
					post_url=$post_url"$measurement,nas_name=$nas_name,interface_name=$interface_name bytes_recv=$bytes_recv,bytes_sent=$bytes_sent
		"	
				done
				
			else
				echo "Skipping Network capture"
			fi
			
			#GETTING GPU INFORMATION
			if [ $GPU_installed -eq 1 ]; then
				if [ $capture_GPU -eq 1 ]; then
					
					measurement="synology_gpu"
					
					SS_restart=0
					
					#The percentage of GPU time spent on processing user space in last 1 second
					gpuUtilization=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuUtilization.0 -Ovt)
					
					#The percentage of GPU memory usage in last 1 second
					gpuMemoryUtilization=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryUtilization.0 -Ovt)
					
					#The amount of currently free GPU memory in kb
					gpuMemoryFree=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryFree.0 -Ovt)
					
					#The amount of currently used GPU memory in kb
					gpuMemoryUsed=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryUsed.0 -Ovt)
					
					#The total physical GPU memory size
					gpuMemoryTotal=$(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryTotal.0 -Ovt)
					
					#GPU Temperature
					gpuTemperature=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader)
					
					#GPU FAN Speed
					gpuFanSpeed=$(nvidia-smi --query-gpu=fan.speed --format=csv,noheader)
					
					secondString=""
					gpuUtilization=${gpuUtilization//\INTEGER: /$secondString} #filtering out the "INTEGER: " part of the string
					gpuUtilization=${gpuUtilization//\ %/$secondString} #filtering out the "%" part of the string, so now we have just a number and nothing else
					
					if [ $debug -eq 1 ]; then
						echo "gpuUtilization is $gpuUtilization"
						echo "gpuTemperature is $gpuTemperature"
					fi
					
					if [ $gpuUtilization -lt $SS_restart_GPU_usage_threshold ]; then
						if [ $gpuTemperature -lt $SS_restart_GPU_temp_threshold ]; then
							echo "Synology Surveillance Station appears to not be utilizing the GPU"
							
							#track how long the GPU has been running at low usage and if it stays this way for too long ($SS_restart_delay_minuets minutes), only then restart SS
							current_time=$( date +%s )
							if [ -r "$SS_Station_restart_tracking" ]; then
								read email_time < "$SS_Station_restart_tracking"
								time_diff=$((( $current_time - $email_time ) / 60 ))
							else 
								echo "$current_time" > "$SS_Station_restart_tracking"
								time_diff=0
							fi
							
							if [ $time_diff -ge $SS_restart_delay_minuets ]; then # has it been more than $SS_restart_delay_minuets minutes where the GPU usage is low?
								status=$(/usr/syno/bin/synopkg is_onoff "SurveillanceStation")
								if [ "$status" = "package SurveillanceStation is turned on" ]; then
									if [ $enable_SS_restart -eq 1 ]; then
										echo "Automatic Restarting of Synology Surveillance Station is enabled, proceeding with restart....."
										echo "Stopping Synology Surveillance Station...."
										if [ $debug -eq 1 ]; then
											echo "Debug Mode - Shutting down Package SurveillanceStation"
										else
											/usr/syno/bin/synopkg stop "SurveillanceStation"
										fi
										sleep 1
										
										#confirm that the package was actually stopped 
										status=$(/usr/syno/bin/synopkg is_onoff "SurveillanceStation")
										if [ "$status" = "package SurveillanceStation is turned on" ]; then
											echo "$current_time" > "$SS_Station_restart_tracking"
											time_diff=0
											send_mail "$log_file_location/${0##*/}_Surveillance_last_message_sent.txt" "ALERT! - Synology Surveillance Station Appeared to no longer be utilizing the GPU. Automatic restart of Synology Surveillance Station was enabled and was unable to shutdown Surveillance Station." "Subject: $nas_name Synology Surveillance Station Low GPU Usage - Synology Surveillance Station Shutdown FAILED" "$log_file_location/${0##*/}_email_contents.txt" "Surveillance Station Error" 0 $use_mail_plus_server
										else
											echo -e "\n\nSynology Surveillance Station successfully shutdown\n\n"
											echo "Restarting Synology Surveillance Station...."
											if [ $debug -eq 1 ]; then
												echo "Debug Mode - Starting Package SurveillanceStation"
											else
												/usr/syno/bin/synopkg start "SurveillanceStation"
											fi
											sleep 1
											status=$(/usr/syno/bin/synopkg is_onoff "SurveillanceStation")
											if [ "$status" = "package SurveillanceStation is turned on" ]; then
												echo "$current_time" > "$SS_Station_restart_tracking"
												time_diff=0
												send_mail "$log_file_location/${0##*/}_Surveillance_last_message_sent.txt" "ALERT! - Synology Surveillance Station Appeared to no longer be utilizing the GPU. Automatic restart of Synology Surveillance Station was enabled and was successfully restarted." "$nas_name Synology Surveillance Station Low GPU Usage - Synology Surveillance Station Restarted" "$log_file_location/${0##*/}_email_contents.txt" "Surveillance Station Error" 0 $use_mail_plus_server
											else
												echo -e "\n\nSynology Surveillance Station was shutdown but FAILED to restart\n\n"
												echo "$current_time" > $SS_Station_restart_tracking
												time_diff=0
												send_mail "$log_file_location/${0##*/}_Surveillance_last_message_sent.txt" "ALERT! - Synology Surveillance Station Appeared to no longer be utilizing the GPU. Automatic restart of Synology Surveillance Station was enabled and was NOT successfully restarted." "$nas_name Synology Surveillance Station Low GPU Usage - Synology Surveillance Station Restart FAILED" "$log_file_location/${0##*/}_email_contents.txt" "Surveillance Station Error" 0 $use_mail_plus_server
											fi
										fi
									else
										if [ $time_diff -ge $email_interval ]; then
											#automatic restart is not enabled, so at least send a notification email 
											echo "$current_time" > "$SS_Station_restart_tracking"
											time_diff=0
											send_mail "$log_file_location/${0##*/}_Surveillance_last_message_sent.txt" "ALERT! - Synology Surveillance Station Appears to no longer be utilizing the GPU. Note, automatic restart of Synology Surveillance Station is not enabled. Manually check the status of Synology Surveillance Station." "$nas_name Synology Surveillance Station Low GPU Usage" "$log_file_location/${0##*/}_email_contents.txt" "Surveillance Station Error" 0 $use_mail_plus_server
										else
											echo -e "\nNote, automatic restart of Synology Surveillance Station is not enabled. Manually check the status of Synology Surveillance Station.\n\nAnother Email will be sent in $(( $email_interval - $time_diff )) Minuets"
										fi
									fi
								else
									echo "Synology Surveillance Station is not running, skipping restart checks"
								fi
							else
								echo "Only $time_diff minuets have passed since the GPU load and temperature were reported too low. In $(( $SS_restart_delay_minuets - $time_diff )) Minutes SurveillanceStation auto restart processes will initiate"
							fi
						fi
					else
						if [ -r "$SS_Station_restart_tracking" ]; then
							rm "$SS_Station_restart_tracking"
						fi
					fi
					
					
					#System details to post
					post_url=$post_url"$measurement,nas_name=$nas_name gpu_utilization=$gpuUtilization,gpuMemoryUtilization=$gpuMemoryUtilization,gpuMemoryFree=$gpuMemoryFree,gpuMemoryUsed=$gpuMemoryUsed,gpuMemoryTotal=$gpuMemoryTotal,gpuTemperature=$gpuTemperature,gpuFanSpeed=$gpuFanSpeed
			"
			
					post_url=${post_url//\INTEGER: /$secondString}
					post_url=${post_url//\ %/$secondString}

					if [ $gpuTemperature -ge $max_GPU ]; then
						send_mail "$log_file_location/${0##*/}_GPU_temperature_last_message_sent.txt" "Warning the temperature of the NVR GPU on $nas_name has exceeded $max_GPU Degrees C / $max_GPU_f Degrees F. The Temperature is currently $gpuTemperature degrees" "$nas_name GPU Temperature Warning" "$log_file_location/${0##*/}_email_contents.txt" "GPU Temperature Alert" $email_interval $use_mail_plus_server
					fi
				else
					echo "Skipping GPU capture"
				fi
			else
				echo "Skipping GPU capture, GPU not installed"
			fi
			
			#########################################
			# GETTING SYNOLOGY SERVICES USAGE
			#########################################
			
			if [ $capture_synology_services -eq 1 ]; then
				
				measurement="synology_services"
				service_name=();
				service_users=();
								
				while IFS= read -r line; do
				
					name=${line#*STRING: \"} #removes the beginning of the line STRING: "
					service_name+=( ${name%?} ); #adds to an array and removes the last " from the result
				
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.6.1.1.2)
				
				while IFS= read -r line; do
				
					users=${line#*INTEGER: }
					service_users+=( $users );
				
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.6.1.1.3)
				
				post_url=$post_url"$measurement,nas_name=$nas_name "
				
				for (( counter=0; counter<${#service_name[@]}; counter++ )); do
					if [ $counter -eq 0 ]; then
						post_url=$post_url"${service_name[$counter]}=${service_users[$counter]}"
					else
						post_url=$post_url",${service_name[$counter]}=${service_users[$counter]}"
					fi
				done
				post_url=$post_url"
				"
			else
				echo "Skipping Synology Services capture"
			fi
			
			#########################################
			#GETTING Synology FlashCache STATS
			#########################################
			if [ $capture_FlashCache -eq 1 ]; then
				measurement="synology_FlashCache"
				disk_info=();
				unsupported_OID=0
				
				while IFS= read -r line; do
					if [[ $line == "SYNOLOGY-FLASHCACHE-MIB::flashCacheSpaceDev = No Such Instance currently exists at this OID"* ]]; then
						unsupported_OID=1 #the flash cache might not be installed or configured, if it is off, then this IOD will fail to collect data
					else
						id=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheSpaceDev."/}; id=${id%" = STRING:"*}
						cache_volume_mount=${line#*STRING: };
						cache_volume_mount=${cache_volume_mount#*/dev/vg$id/}
						disk_info+=([$id]=$cache_volume_mount)
					fi
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-FLASHCACHE-MIB::flashCacheSpaceDev)
				
				if [ $unsupported_OID -eq 0 ]; then
					for id in "${!disk_info[@]}"
					do
						cache_volume_mount=${disk_info[$id]}
						
						while IFS= read -r line; do
							if [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheDiskRead.$id ="* ]]; then
								disk_reads=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheDiskRead."$id" = Counter64: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheDiskWrite.$id ="* ]]; then
								disk_writes=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheDiskWrite."$id" = Counter64: "/}
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheReadHits.$id ="* ]]; then
								ReadHits=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheReadHits."$id" = Counter64: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheWriteHits.$id ="* ]]; then
								WriteHits=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheWriteHits."$id" = Counter64: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheTotalRead.$id ="* ]]; then
								TotalRead=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheTotalRead."$id" = Counter64: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheTotalWrite.$id ="* ]]; then
								TotalWrite=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheTotalWrite."$id" = Counter64: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheReadHitRate.$id ="* ]]; then
								ReadHitRate=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheReadHitRate."$id" = INTEGER: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheWriteHitRate.$id ="* ]]; then
								WriteHitRate=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheWriteHitRate."$id" = INTEGER: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheReadSeqSkip.$id ="* ]]; then
								ReadSeqSkip=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheReadSeqSkip."$id" = Counter64: "/};
							
							elif [[ "$line" == "SYNOLOGY-FLASHCACHE-MIB::flashCacheWriteSeqSkip.$id ="* ]]; then
								WriteSeqSkip=${line/"SYNOLOGY-FLASHCACHE-MIB::flashCacheWriteSeqSkip."$id" = Counter64: "/};
							fi
													
						done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.103)
						
						post_url=$post_url"$measurement,nas_name=$nas_name,cache_volume_mount=$cache_volume_mount disk_reads=$disk_reads,disk_writes=$disk_writes,ReadHits=$ReadHits,WriteHits=$WriteHits,TotalRead=$TotalRead,TotalWrite=$TotalWrite,ReadHitRate=$ReadHitRate,WriteHitRate=$WriteHitRate,ReadSeqSkip=$ReadSeqSkip,WriteSeqSkip=$WriteSeqSkip
			"
					done
				else
					echo "Flash Cache is not enabled or supported. Ensure Flash SSDs are installed in the system and Cache volumes have been created in storage manager"
				fi
			else
				echo "Skipping FlashCache capture"
			fi
			
			#########################################
			#GETTING iSCSI LUN INFO
			#########################################
			
			if [ $capture_iSCSI_LUN -eq 1 ]
			then
				measurement="synology_iSCSI_LUN"
				unsupported_OID=0
				disk_info=()
				
				while IFS= read -r line; do
				
					if [[ $line == "SYNOLOGY-ISCSILUN-MIB::iSCSILUNName = No Such Instance currently exists at this OID"* ]]; then
						unsupported_OID=1 #the iSCSI service might not have an active LUN, if it is not active/configured, then this IOD will fail to collect data
					else
					
						id=${line/"SYNOLOGY-ISCSILUN-MIB::iSCSILUNName."/}; id=${id%" = STRING:"*}
						disk_name=${line#*STRING: }; disk_name=${disk_name// /};disk_name=${disk_name//\"}
						disk_info+=([$id]=$disk_name)
					fi
				
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-ISCSILUN-MIB::iSCSILUNName)
				
				if [ $unsupported_OID -eq 0 ]; then
					for id in "${!disk_info[@]}"
					do
						disk_name=${disk_info[$id]}
						while IFS= read -r line; do
						
							if [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.4.$id ="* ]]; then
								ThroughputReadHigh=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.4."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.5.$id ="* ]]; then
								ThroughputReadLow=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.5."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.6.$id ="* ]]; then
								ThroughputWriteHigh=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.6."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.7.$id ="* ]]; then
								ThroughputWriteLow=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.7."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.8.$id ="* ]]; then
								IopsRead=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.8."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.9.$id ="* ]]; then
								IopsWrite=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.9."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.10.$id ="* ]]; then
								DiskLatencyRead=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.10."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.11.$id ="* ]]; then
								DiskLatencyWrite=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.11."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.12.$id ="* ]]; then
								NetworkLatencyTx=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.12."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.13.$id ="* ]]; then
								NetworkLatencyRx=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.13."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.14.$id ="* ]]; then
								IoSizeRead=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.14."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.15.$id ="* ]]; then
								IoSizeWrite=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.15."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.16.$id ="* ]]; then
								QueueDepth=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.16."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.17.$id ="* ]]; then
								Type=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.17."$id" = "/}
							fi
							
							
							/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
							if [ "$?" -eq "0" ]; then
								echo "DSM is below version 7.0 skipping capturing DiskLatencyAvg, ThinProvisionVolFreeMBs"
							else
								if [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.18.$id ="* ]]; then
									DiskLatencyAvg=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.18."$id" = INTEGER: "/}
								
								elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.104.1.1.19.$id ="* ]]; then
									ThinProvisionVolFreeMBs=${line/"SYNOLOGY-SYSTEM-MIB::synology.104.1.1.19."$id" = INTEGER: "/}
								fi
							fi
						
						done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.104)
						
						/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
						if [ "$?" -eq "0" ]; then
							post_url=$post_url"$measurement,nas_name=$nas_name,iSCSI_lun=$disk_name ThroughputReadHigh=$ThroughputReadHigh,ThroughputReadLow=$ThroughputReadLow,ThroughputWriteHigh=$ThroughputWriteHigh,ThroughputWriteLow=$ThroughputWriteLow,IopsRead=$IopsRead,IopsWrite=$IopsWrite,DiskLatencyRead=$DiskLatencyRead,DiskLatencyWrite=$DiskLatencyWrite,NetworkLatencyTx=$NetworkLatencyTx,NetworkLatencyRx=$NetworkLatencyRx,IoSizeRead=$IoSizeRead,IoSizeWrite=$IoSizeWrite,QueueDepth=$QueueDepth,Type=$Type
			"
						else
							post_url=$post_url"$measurement,nas_name=$nas_name,iSCSI_lun=$disk_name ThroughputReadHigh=$ThroughputReadHigh,ThroughputReadLow=$ThroughputReadLow,ThroughputWriteHigh=$ThroughputWriteHigh,ThroughputWriteLow=$ThroughputWriteLow,IopsRead=$IopsRead,IopsWrite=$IopsWrite,DiskLatencyRead=$DiskLatencyRead,DiskLatencyWrite=$DiskLatencyWrite,NetworkLatencyTx=$NetworkLatencyTx,NetworkLatencyRx=$NetworkLatencyRx,IoSizeRead=$IoSizeRead,IoSizeWrite=$IoSizeWrite,QueueDepth=$QueueDepth,Type=$Type,DiskLatencyAvg=$DiskLatencyAvg,ThinProvisionVolFreeMBs=$ThinProvisionVolFreeMBs
			"
						fi
					done
				else
					echo "iSCSI is not enabled or supported and will be skipped. Go to \"San Manager\" and verify at least one LUN exists and is active"
				fi
			else
				echo "Skipping iSCSI LUN capture"
			fi
			
			#########################################
			# GETTING SHA STATS
			#########################################
			
			if [ $capture_SHA -eq 1 ]
			then
				
				measurement="synology_SHA"
				unsupported_OID=0
				
				while IFS= read -r line; do
					
					if [[ $line == "SYNOLOGY-SHA-MIB::synologyHA = No Such Object available on this agent at this OID"* ]]; then
						unsupported_OID=1 #the SHA service can be turned on or off, if it is off, then this IOD will fail to collect data
					else
				
						if [[ $line == SYNOLOGY-SHA-MIB::activeNodeName.0* ]]; then
							activeNodeName=${line/"SYNOLOGY-SHA-MIB::activeNodeName.0 = STRING: "/}
					
						elif [[ $line == SYNOLOGY-SHA-MIB::passiveNodeName.0* ]]; then
							passiveNodeName=${line/"SYNOLOGY-SHA-MIB::passiveNodeName.0 = STRING: "/}
					
						elif [[ $line == SYNOLOGY-SHA-MIB::clusterAutoFailover.0* ]]; then
							#Whether cluster can failover once something went wrong   true (1)  false (2)
							clusterAutoFailover=${line/"SYNOLOGY-SHA-MIB::clusterAutoFailover.0 = INTEGER: "/}
					
						elif [[ $line == SYNOLOGY-SHA-MIB::clusterName.0* ]]; then
							clusterName=${line/"SYNOLOGY-SHA-MIB::clusterName.0 = STRING: "/}
						
						elif [[ $line == SYNOLOGY-SHA-MIB::clusterStatus.0* ]]; then
							clusterStatus=${line/"SYNOLOGY-SHA-MIB::clusterStatus.0 = INTEGER: "/}
							#normal (0) The High-Availability cluster is healthy 
							#warning (1) The High-Availability cluster has something went wrong. Action should be taken to resume High-Availability feature. Please refer to High-Availability Manager for more details.
							#critical (2) The High-Availability cluster is in danger, and should be resolved as soon as possible. Please refer to High-Availability Manager for more details.
							#upgrading (3) The High-Availability cluster is upgrading.
							#processing (4) The High-Availability cluster is undergoing some operation. 
							if [[ $clusterStatus != 0 ]]; then
								clusterStatus_text=""
								if [[ $clusterStatus == 1 ]]; then
									clusterStatus_text="The High-Availability cluster has something went wrong. Action should be taken to resume High-Availability feature. Please refer to High-Availability Manager for more details."
								elif [[ $clusterStatus == 2 ]]; then
									clusterStatus_text="The High-Availability cluster is in danger, and should be resolved as soon as possible. Please refer to High-Availability Manager for more details."
								elif [[ $clusterStatus == 3 ]]; then
									clusterStatus_text="The High-Availability cluster is upgrading."
								elif [[ $clusterStatus == 4 ]]; then
									clusterStatus_text="The High-Availability cluster is undergoing some operation."
								fi
								send_mail "$log_file_location/${0##*/}_SHA_last_message_sent.txt" "$clusterStatus_text" "ALERT - $nas_name High Availability Notification" "$log_file_location/${0##*/}_email_contents.txt" "SHA Alert" $email_interval $use_mail_plus_server
							fi
						elif [[ $line == SYNOLOGY-SHA-MIB::heartbeatStatus.0* ]]; then
							heartbeatStatus=${line/"SYNOLOGY-SHA-MIB::heartbeatStatus.0 = INTEGER: "/}
							#normal (0) The heartbeat connection is normal. 
							#abnormal (1) Some information about heartbeat is not available. 
							#disconnected (2) The High-Availability cluster loses connection to passive server through heartbeat interface, or it is currently in split-brain mode.
							#empty (3) The High-Availability cluster has no passive server. 
						elif [[ $line == SYNOLOGY-SHA-MIB::heartbeatTxRate.0* ]]; then
							heartbeatTxRate=${line/"SYNOLOGY-SHA-MIB::heartbeatTxRate.0 = INTEGER: "/} #Transfer speed of heartbeat in kilo-byte-per-second
						elif [[ $line == SYNOLOGY-SHA-MIB::heartbeatLatency.0* ]]; then
							heartbeatLatency=${line/"SYNOLOGY-SHA-MIB::heartbeatLatency.0 = INTEGER: "/} #Heartbeat latency in microseconds (10^-6 seconds)
						fi
					fi
						
				done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.106)
				
				if [ $unsupported_OID -eq 0 ]; then
					post_url=$post_url"$measurement,nas_name=$nas_name activeNodeName=$activeNodeName,passiveNodeName=$passiveNodeName,clusterAutoFailover=$clusterAutoFailover,clusterName=$clusterName,clusterStatus=$clusterStatus,heartbeatStatus=$heartbeatStatus,heartbeatTxRate=$heartbeatTxRate,heartbeatLatency=$heartbeatLatency
			"
				else
					echo "SHA is not enabled or supported and will be skipped"
				fi
			else
				echo "Skipping SHA capture"
			fi
		
			#########################################
			#GETTING NFS INFO
			#########################################
			/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
			if [ "$?" -eq "0" ]; then
				echo "DSM is below version 7.0 skipping capturing NFS as that is not available below DSM v7"
			else
				#NFS capture is only available on DSM 7.0 and higher
				if [ $capture_NFS -eq 1 ]
				then
					measurement="synology_NFS"
					unsupported_OID=0
					
					nsf_info=()
					
					while IFS= read -r line; do
					
						if [[ $line == "SYNOLOGY-NFS-MIB::nfsName = No Such Instance currently exists at this OID"* ]]; then
							unsupported_OID=1 #the NFS service can be turned on or off, if it is off, then this IOD will fail to collect data
						else
							id=${line/"SYNOLOGY-NFS-MIB::nfsName."/}; id=${id%" = STRING:"*}
							nfs_name=${line#*STRING: }; nfs_name=${nfs_name// /};nfs_name=${nfs_name//\"}
							nsf_info+=([$id]=$nfs_name)
						fi
					
					done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.107.1.1.2)
					if [ $unsupported_OID -eq 0 ]; then
			
						for id in "${!nsf_info[@]}"
						do
							nfs_name=${nsf_info[$id]}
							while IFS= read -r line; do
							
							if [[ "$line" == "SYNOLOGY-NFS-MIB::nfsTotalMaxLatency.$id ="* ]]; then
								TotalMaxLatency=${line/"SYNOLOGY-NFS-MIB::nfsTotalMaxLatency."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-NFS-MIB::nfsReadMaxLatency.$id ="* ]]; then
								ReadMaxLatency=${line/"SYNOLOGY-NFS-MIB::nfsReadMaxLatency."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-NFS-MIB::nfsWriteMaxLatency.$id ="* ]]; then
								WriteMaxLatency=${line/"SYNOLOGY-NFS-MIB::nfsWriteMaxLatency."$id" = INTEGER: "/}
							
							elif [[ "$line" == "SYNOLOGY-NFS-MIB::nfsTotalOPS.$id ="* ]]; then
								TotalOPS=${line/"SYNOLOGY-NFS-MIB::nfsTotalOPS."$id" = Counter64: "/}
							
							elif [[ "$line" == "SYNOLOGY-NFS-MIB::nfsReadOPS.$id ="* ]]; then
								ReadOPS=${line/"SYNOLOGY-NFS-MIB::nfsReadOPS."$id" = Counter64: "/}
							
							elif [[ "$line" == "SYNOLOGY-NFS-MIB::nfsWriteOPS.$id ="* ]]; then
								WriteOPS=${line/"SYNOLOGY-NFS-MIB::nfsWriteOPS."$id" = Counter64: "/}
							fi
							
							done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.107)
								post_url=$post_url"$measurement,nas_name=$nas_name,nfs_name=$nfs_name TotalMaxLatency=$TotalMaxLatency,ReadMaxLatency=$ReadMaxLatency,WriteMaxLatency=$WriteMaxLatency,TotalOPS=$TotalOPS,ReadOPS=$ReadOPS,WriteOPS=$WriteOPS
				"
						done		
					else
						echo "NFS Capture is not enabled or supported and will be skipped. Go to Control Panel --> File Services --> NFS and verify the service is active"
					fi
				else
					echo "Skipping NFS capture"
				fi
			fi
		
			#########################################
			#GETTING iSCSI Target INFO
			#########################################
			/usr/bin/dpkg --compare-versions "7.0" gt "$DSMVersion"
			if [ "$?" -eq "0" ]; then
				echo "DSM is below version 7.0 skipping capturing iSCSI_Target as that is not available below DSM v7"
			else
				#iSCSI Target capture is only available on DSM 7.0 and higher
				if [ $capture_iSCSI_Target -eq 1 ]; then
					measurement="synology_iSCSI_Target"
					unsupported_OID=0
					secondString=""
					
					iSCSI_info=()
					
					while IFS= read -r line; do
					
						if [[ $line == "SYNOLOGY-SYSTEM-MIB::synology.110.2 = No Such Instance currently exists at this OID"* ]]; then
							unsupported_OID=1 #the iSCSI Target service can be turned on or off, if it is off, then this IOD will fail to collect data
						else
							id=${line/"SYNOLOGY-SYSTEM-MIB::synology.110.2."/}; id=${id%" = STRING:"*}
							target_name=${line#*STRING: }; target_name=${target_name// /};target_name=${target_name//\"}
							iSCSI_info+=([$id]=$target_name)
						fi
					
					done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 SYNOLOGY-SYSTEM-MIB::synology.110.2)
					if [ $unsupported_OID -eq 0 ]; then
			
						for id in "${!iSCSI_info[@]}"
						do
							target_name=${iSCSI_info[$id]}
							while IFS= read -r line; do
							
							if [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.110.3.$id ="* ]]; then
								TargetIQN=${line/"SYNOLOGY-SYSTEM-MIB::synology.110.3."$id" = STRING: "/}
								TargetIQN=${TargetIQN//\"/$secondString} #getting rid of the quotes
							
							elif [[ "$line" == "SYNOLOGY-SYSTEM-MIB::synology.110.4.$id ="* ]]; then
								TargetConnectionStatus=${line/"SYNOLOGY-SYSTEM-MIB::synology.110.4."$id" = "/}
							fi
							
							done < <(snmpwalk -v3 -l authPriv -u "$nas_snmp_user" -a $snmp_auth_protocol -A "$snmp_authPass1" -x $snmp_privacy_protocol -X "$snmp_privPass2" $nas_url:161 .1.3.6.1.4.1.6574.110)
								post_url=$post_url"$measurement,nas_name=$nas_name,target_name=$target_name TargetIQN=\"$TargetIQN\",TargetConnectionStatus=$TargetConnectionStatus
				"
						done		
					else
						echo "iSCSI Target Capture is not enabled or supported and will be skipped."
					fi
				else
					echo "Skipping iSCSI Target capture"
				fi
			fi

			#########################################
			#Post to influxdb
			#########################################
	
			curl -XPOST "$influx_http_type://$influxdb_host:$influxdb_port/api/v2/write?bucket=$influxdb_name&org=$influxdb_org" -H "Authorization: Token $influxdb_pass" --data-raw "$post_url"
			
			if [ $debug -eq 1 ]; then
				echo "$post_url"
			fi
			
			let i=i+1
			
			echo -e "Capture #$i complete\n"
			
			#Sleeping for capture interval unless its last capture then we don't sleep
			if (( $i < $total_executions)); then
				sleep $(( $capture_interval - $capture_interval_adjustment))
			fi
			
		done
	else
		echo "script is disabled"
	fi
else
	if [[ "$email_address" == "" || "$from_email_address" == "" ]];then
		echo -e "\n\nNo email address information is configured, Cannot send an email indicating script \"${0##*/}\" config file is missing and script will not run"
	else
		send_mail "$SS_Station_restart_tracking" "Warning NAS \"$nas_name_error\" SNMP Monitoring Failed for script \"${0##*/}\" - Configuration file is missing" "Warning NAS \"$nas_name_error\" SNMP Monitoring Failed for script \"${0##*/}\" - Configuration file is missing" "$log_file_location/${0##*/}_email_contents.txt" "Config File Missing Alert" 60 $use_mail_plus_server
	fi
	exit 1
fi
