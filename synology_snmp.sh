#!/bin/bash
#version 2.3 dated 9/8/2022
#By Brian Wallace

#based on the script found here by user kernelkaribou
#https://github.com/kernelkaribou/synology-monitoring

#This script pulls various information from the Synology NAS

#this script is not required if using data collectors like telegraf however it allows different control of the data collection and this supports additional logging from DVA unit NVidia graphics cards that cannot be collected through telegraf as it is pulled not from SNMP but from the NVidia drivers directly. 

#this script supports automatic email notifications if the system temperatures, or HDDs are too hot

#This script works in conjunction with a PHP powered web-based administration control panel to configure all of the script settings

#***************************************************
#Dependencies:
#***************************************************
#1.) this script is designed to be executed every 60 seconds
#2.) this script requires the installation of synology MailPlus server package in package center in order to send emails. 
	#the mail plus server must be properly configured to relay received messages to another email account. 
	#this is required as the "sendmail" command is not installed by default on synology DSM but is installed with Mail Plus Server
#3.) RAMDISK
	#NOTE: to reduce disk IOPS activity, it is recommended to create a RAMDISK for the temp files this script uses
	#to do so, create a scheduled task on boot up in Synology Task Scheduler to add the following line

		#mount -t tmpfs -o size=1% ramdisk $notification_file_location

		#where "$notification_file_location" is the location you want the files stored and is a variable configured below

#4.) this script only supports SNMP V3. This is because lower versions are less secure 
	#SNMP must be enabled on the host NAS for the script to gather the NAS NAME
	#the snmp settings for the NAS can all be entered into the web administration page
#5.) This script can be run through synology Task Scheduler. However it has been observed that running large scripts like this as frequently as every 60 seconds causes the synoschedtask system application to use large amounts of resources and causes the script to execute slowly
	#details of this issue can be seen here:
	#https://www.reddit.com/r/synology/comments/kv7ufq/high_disk_usage_on_disk_1_caused_by_syno_task/
	#to fix this it is recommend to directly edit the crontab at /etc/crontab
	
	#this can be accomplished using vi /etc/crontab
	
	#add the following line: 
	#	*	*	*	*	*	root	$path_to_file/$filename
	#details on crontab can be found here: https://man7.org/linux/man-pages/man5/crontab.5.html
#6.) This script only supports InfluxdB version 2. as version 1.x is no longer supported, it is recommended to upgrade to version 2 anyways


#########################################
#variable initialization
#########################################
#email_logging_file_location="/volume1/web/logging/notifications/logging_variable2.txt"
#lock_file_location="/volume1/web/logging/notifications/synology_snmp2.lock"
#config_file_location="/volume1/web/config/config_files/config_files_local/system_config2.txt"
#log_file_location="/volume1/web/logging/notifications"
debug=0
disk_messge_tracker=();
MinDSMVersion=7.0


#for my personal use as i have multiple synology systems, these lines can be deleted by other users and the 4x lines above can be un-commented
######################################################################################
sever_type=1 #1=server2, 2=serverNVR, 3=serverplex

if [[ $sever_type == 1 ]]; then
	email_logging_file_location="/volume1/web/logging/notifications/logging_variable2.txt"
	lock_file_location="/volume1/web/logging/notifications/synology_snmp.lock"
	config_file_location="/volume1/web/config/config_files/config_files_local/system_config2.txt"
	log_file_location="/volume1/web/logging/notifications"
fi

if [[ $sever_type == 2 ]]; then
	email_logging_file_location="/volume1/web/logging/notifications/logging_variable2.txt"
	lock_file_location="/volume1/web/logging/notifications/synology_snmp.lock"
	config_file_location="/volume1/web/logging/system_config_NVR2.txt"
	log_file_location="/volume1/web/logging/notifications"
fi

if [[ $sever_type == 3 ]]; then
	email_logging_file_location="/volume1/web/logging/notifications/logging_variable2.txt"
	lock_file_location="/volume1/web/logging/notifications/synology_snmp.lock"
	config_file_location="/volume1/web/config/config_files/config_files_local/system_config2.txt"
	log_file_location="/volume1/web/logging/notifications"
fi

######################################################################################


#########################################
#Script Start
#########################################

#this function is used to send notification emails if any of the installed disk drive's temperatures are above the setting controlled in the web-interface
function disk_temp_email(){
	if [ $disk_temp -ge $max_disk_temp ]
	then
		if [ ${disk_messge_tracker[$id]} -ge $email_interval ]
		then
		echo "the email has not been sent in over $email_interval minutes, re-sending email"
			local mailbody="Warning the temperature of $disk_name on $nas_name has exceeded $max_disk_temp Degrees C / $max_disk_temp_f Degrees F. The current Temperature is $disk_temp"
			echo "from: $from_email_address " > $log_file_location/disk_email.txt
			echo "to: $email_address " >> $log_file_location/disk_email.txt
			echo "subject: $disk_name Temperature Warning on $nas_name" >> $log_file_location/disk_email.txt
			echo "" >> $log_file_location/disk_email.txt
			echo $mailbody >> $log_file_location/disk_email.txt
			cat $log_file_location/disk_email.txt | sendmail -t
			disk_messge_tracker[$id]=0
		fi
	fi
}

#create a lock file in the ramdisk directory to prevent more than one instance of this script from executing at once
if ! mkdir $lock_file_location; then
	echo "Failed to acquire lock.\n" >&2
	exit 1
fi
trap 'rm -rf $lock_file_location' EXIT #remove the lockdir on exit


#reading in variables from configuration file. this configuration file is edited using a web administration page. or the file can be edited directly. 
#If the file does not yet exist, opening the web administration page will create a file with default settings
if [ -r "$config_file_location" ]; then
	#file is available and readable 
	read input_read < $config_file_location
	explode=(`echo $input_read | sed 's/,/\n/g'`) #explode on the comma separating the variables
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
	influx_http_type="http" #set to "http" or "https" based on your influxDB version
	influxdb_org="home"
	
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
		echo "capture_networkis $capture_network"
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
	fi


	if [ $script_enable -eq 1 ]
	then
		#confirm that the synology SNMP settings were configured otherwise exit script
		if [ "$nas_snmp_user" = "" ];then
			echo "Synology NAS Username is BLANK, please configure the SNMP settings"
			exit
		else
			if [ "$snmp_authPass1" = "" ];then
				echo "Synology NAS Authentication Password is BLANK, please configure the SNMP settings"
				exit
			else
				if [ "$snmp_privPass2" = "" ];then
					echo "Synology NAS Privacy Password is BLANK, please configure the SNMP settings"
					exit
				else
					if [ $debug -eq 1 ];then
						echo "Synology SNTP settings are not Blank"
					fi
				fi
			fi
		fi
			
		#verify MailPlus Server package is installed and running as the "sendmail" command is not installed in synology by default. the MailPlus Server package is required
		install_check=$(/usr/syno/bin/synopkg list | grep MailPlus-Server)

		if [ "$install_check" = "" ];then
			echo "WARNING!  ----   MailPlus Server NOT is installed, cannot send email notifications"
			sendmail_installed=0
		else
			#"MailPlus Server is installed, verify it is running and not stopped"
			status=$(/usr/syno/bin/synopkg is_onoff "MailPlus-Server")
			if [ "$status" = "package MailPlus-Server is turned on" ]; then
				sendmail_installed=1
				if [ $debug -eq 1 ];then
					echo "MailPlus Server is installed and running"
				fi
			else
				sendmail_installed=0
				echo "WARNING!  ----   MailPlus Server NOT is running, cannot send email notifications"
			fi
		fi
		
		#confirm that the synology NVidia drivers are actually installed. If they are not installed, set the correct flag
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
		
		#reading in variables from previous script executions. we track how many script executions have occurred.
		#This is used to when the last email notification has been sent to control when repeat messages are sent. 
		#we track this for each installed drive and the CPU individually as each can require email notifications independently. 
		
		if [ -r "$email_logging_file_location" ]; then
			#file is available and readable 
			read input_read < $email_logging_file_location #determine how many minutes it has been since the last email has been sent
			explode=(`echo $input_read | sed 's/,/\n/g'`)
			
			for (( counter=0; counter<$number_drives_in_system; counter++ ))
			do
				if [ "${explode[$counter]}" = "" ]; then
					echo "reading previous drive email tracking data failed, exiting script, suggest deleting file \"$email_logging_file_location\" and running script again to re-create file"
					exit
				else
					disk_messge_tracker+=( ${explode[$counter]} );
					if [ $debug -eq 1 ]; then
						echo "disk_messge_tracker id $counter is equal to: ${disk_messge_tracker[$counter]}"
					fi
				fi
			done

			if [ "${explode[$counter]}" = "" ]; then
				echo "reading previous CPU email tracking data failed, exiting script, suggest deleting file \"$email_logging_file_location\" and running script again to re-create file"
				exit
			else
				CPU_message_tracker=${explode[$counter]}
				if [ $debug -eq 1 ]; then
					echo "CPU_message_tracker is equal to $CPU_message_tracker"
				fi
			fi
			let counter=counter+1
			if [ $GPU_installed -eq 1 ];then
				if [ "${explode[$counter]}" = "" ]; then
					echo "reading previous GPU email tracking data failed, exiting script, suggest deleting file \"$email_logging_file_location\" and running script again to re-create file"
					exit
				else
					GPU_message_tracker=${explode[$counter]}
					if [ $debug -eq 1 ]; then
						echo "GPU_message_tracker is equal to $GPU_message_tracker"
					fi
				fi
			fi
			
		else
			#file is not available so let's make a new file with default values file
			echo "$email_logging_file_location is not available, writing default values"
			#write zeros for all of the installed dries
			for (( counter=0; counter<$number_drives_in_system; counter++ ))
			do
				if [ $counter -eq 0 ];then
					echo -n "0" > $email_logging_file_location
				else
					echo -n ",0" >> $email_logging_file_location
				fi
				disk_messge_tracker+=( 0 );
			done
			
			echo -n ",0" >> $email_logging_file_location #write CPU logging variable
			CPU_message_tracker=0
			
			if [ $GPU_installed -eq 1 ];then
				echo -n ",0" >> $email_logging_file_location #write GPU logging variable
				GPU_message_tracker=0
			fi
			echo "$email_logging_file_location created with default values. Re-run the script. "
			exit
		fi
		
		#determine DSM version to ensure as different DSM versions support different OIDs
		DSMVersion=$(                   cat /etc.defaults/VERSION | grep -i 'productversion=' | cut -d"\"" -f 2)

		# Getting NAS hostname from NAS, and capturing error output in the event we get an error during the SNMP_walk
		nas_name=$(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SNMPv2-MIB::sysName.0 -Ovqt 2>&1)

		#since $nas_name is the first time we have performed a SNMP request, let's make sure we did not receive any errors that could be caused by things like bad passwords, bad username, incorrect auth or privacy types etc
		#if we receive an error now, then something is wrong with the SNMP settings and this script will not be able to function so we should exit out of it. 
		#the five main error are
		#1 - too short of a password
			#Error: passphrase chosen is below the length requirements of the USM (min=8).
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
			echo "warning, the SNMP Auth password and or the Privacy password supplied is below the minimum 8 characters required. Exiting Script"
			exit 1
		fi
		
		if [[ "$nas_name" == "Timeout:"* ]]; then #will search for the second error type
			echo "The SNMP target did not respond. This could be the result of a bad SNMP privacy password, the wrong IP address, the wrong port, or SNMP services not being enabled on the target device"
			echo "Exiting Script"
			exit 1
		fi
		
		if [[ "$nas_name" == "snmpwalk: Unknown user name"* ]]; then #will search for the third error type
			echo "warning, The supplied username is incorrect. Exiting Script"
			exit 1
		fi
		
		if [[ "$nas_name" == "snmpwalk: Authentication failure (incorrect password, community or key)"* ]]; then #will search for the fourth error type
			echo "The Authentication protocol or password is incorrect. Exiting Script"
			exit 1
		fi
		
		if [[ "$nas_name" == "" ]]; then #will search for the fifth error type
			echo "Something is wrong with the SNMP settings, the results returned a blank/empty value. Exiting Script"
			exit 1
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
				system_uptime=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 HOST-RESOURCES-MIB::hrSystemUptime.0 -Ovt`
				
				#System Status,  1 is on line, 0 is failed/off line
				system_status=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-SYSTEM-MIB::systemStatus.0 -Oqv`
				
				#Fan status1 is on line, 0 is failed/off line
				system_fan_status=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-SYSTEM-MIB::systemFanStatus.0 -Oqv`
				
				cpu_Fan_Status=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-SYSTEM-MIB::cpuFanStatus.0 -Oqv`
				
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
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.4.1.6574.1.5) #Parent OID for SYNOLOGY-SYSTEM-MIB
				
				# synology NAS Temperature
				system_temp=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.4.1.6574.1.2 -Oqv`
				
				#System details to post
				post_url=$post_url"$measurement,nas_name=$nas_name uptime=$system_uptime,system_status=$system_status,fan_status=$system_fan_status,model=$model,serial_number=$serial,upgrade_status=$upgrade,dsm_version=$version,system_temp=$system_temp,cpu_Fan_Status=$cpu_Fan_Status
		"
				#capturing expansion unit details
				expansion_info=()
				while IFS= read -r line; do
					if [[ $line == SYNOLOGY-EBOX-MIB::eboxIndex* ]]; then
						id=${line/"SYNOLOGY-EBOX-MIB::eboxIndex."/}; id=${id%" = INTEGER:"*}
						expansion_ID=${line#*INTEGER: };
						expansion_info+=([$id]=$expansion_ID)
					fi
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 .1.3.6.1.4.1.6574.105)
				
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
					done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 .1.3.6.1.4.1.6574.105)
					
					post_url=$post_url"$measurement,nas_name=$nas_name,expansion_ID=$expansion_ID expanion_model=$expanion_model,expansion_status=$expansion_status
		"
				done
				
				if [ $system_temp -ge $max_CPU0 ]
				then
				#echo the disk temp has been exceeded
					if [ $CPU_message_tracker -ge $email_interval ]
					then
					#echo the email has not been sent in over $email_interval minutes, re-sending email
						if [ $sendmail_installed -eq 1 ];then
							mailbody="Warning the temperature ($system_temp C) of the system CPU on $nas_name has exceeded $max_CPU0 Degrees C / $max_CPU0_f Degrees F "
							echo "from: $from_email_address " > $log_file_location/system_contents.txt
							echo "to: $email_address " >> $log_file_location/system_contents.txt
							echo "subject: $nas_name CPU Temperature Warning " >> $log_file_location/system_contents.txt
							echo "" >> $log_file_location/system_contents.txt
							echo $mailbody >> $log_file_location/system_contents.txt
							cat $log_file_location/system_contents.txt | sendmail -t
							CPU_message_tracker=0
						else
							echo "WARNING - Could not send Email Notification that the system temperature is too high. The temperature ($system_temp C) of the system CPU on $nas_name has exceeded $max_CPU0 Degrees C / $max_CPU0_f Degrees F"
						fi
					fi
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
					
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.4.1.2021.4) #Parent OID for UCD-SNMP-MIB Memory stats
			
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
				usage_idle=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 UCD-SNMP-MIB::ssCpuIdle.0 -Oqv`
				
				ssCpuUser=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 UCD-SNMP-MIB::ssCpuUser.0 -Oqv`
				
				ssCpuSystem=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 UCD-SNMP-MIB::ssCpuSystem.0 -Oqv`
				
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
						vol_blocksize=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 HOST-RESOURCES-MIB::hrStorageAllocationUnits.$id -Ovq | awk {'print $1'}`
						
						# Total Volume Size is size before being multiplied by allocation units
						vol_totalsize=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 HOST-RESOURCES-MIB::hrStorageSize.$id -Oqv`
						
						# Volume Usage
						vol_used=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 HOST-RESOURCES-MIB::hrStorageUsed.$id -Oqv`
						
						# Need to actually convert the sizes provided by their allocation unit, leaving in bytes format
						# Calculation to TB is =(vol_totalsize*vol_blocksize)/1024/1024/1024/1024
						vol_totalsize=$(($vol_totalsize * $vol_blocksize))
						vol_used=$(($vol_used * $vol_blocksize))
						post_url=$post_url"$measurement,nas_name=$nas_name,volume=$vol_name vol_totalsize=$vol_totalsize,vol_used=$vol_used
		"
					fi
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.2.1.25.2.3.1.3)

				#########################################
				#GETTING Volume IO STATS
				#########################################
				
				volume_info=()
				
				while IFS= read -r line; do
						id=${line/"SYNOLOGY-SPACEIO-MIB::spaceIODevice."/}; id=${id%" = STRING:"*}
						volume_path=${line#*STRING: };
						volume_info+=([$id]=$volume_path)
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-SPACEIO-MIB::spaceIODevice)
				
				for id in "${!volume_info[@]}"
				do
					volume_path=""${volume_info[$id]}
					
					while IFS= read -r line; do
						if [[ "$line" == "SYNOLOGY-SPACEIO-MIB::spaceIONReadX.$id ="* ]]; then
							volume_reads=${line/"SYNOLOGY-SPACEIO-MIB::spaceIONReadX."$id" = Counter64: "/};
						fi
				
						if [[ "$line" == "SYNOLOGY-SPACEIO-MIB::spaceIONWrittenX.$id ="* ]]; then
							volume_writes=${line/"SYNOLOGY-SPACEIO-MIB::spaceIONWrittenX."$id" = Counter64: "/}
						fi
				
						if [[ "$line" == "SYNOLOGY-SPACEIO-MIB::spaceIOLA.$id ="* ]]; then
							volume_load=${line/"SYNOLOGY-SPACEIO-MIB::spaceIOLA."$id" = INTEGER: "/}
						fi
					done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.4.1.6574.102)
					
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

				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-RAID-MIB::raidName)
				
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
						fi
					
						if [[ "$line" == "SYNOLOGY-RAID-MIB::raidFreeSize.$id ="* ]]; then
							raid_free_size=${line/"SYNOLOGY-RAID-MIB::raidFreeSize."$id" = Counter64: "/}
						fi
					
						if [[ "$line" == "SYNOLOGY-RAID-MIB::raidTotalSize.$id ="* ]]; then
							raid_total_size=${line/"SYNOLOGY-RAID-MIB::raidTotalSize."$id" = Counter64: "/}
						fi
						
						/usr/bin/dpkg --compare-versions "$MinDSMVersion" gt "$DSMVersion"
						if [ "$?" -eq "0" ]; then
							dsm_type="Synology (DSM 6)" #version is DSM6, do nothing extra
						else
							dsm_type="Synology (DSM 7)" #version is DSM7, collect extra information
							if [[ "$line" == "SYNOLOGY-RAID-MIB::raidHotspareCnt.$id ="* ]]; then
								raidHotspareCnt=${line/"SYNOLOGY-RAID-MIB::raidHotspareCnt."$id" = INTEGER: "/}
							fi
						fi
				
					done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.4.1.6574.3.1.1)
				
					/usr/bin/dpkg --compare-versions "$MinDSMVersion" gt "$DSMVersion"
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
				
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-DISK-MIB::diskID)
				
				for id in "${!disk_info[@]}"
				do
					while IFS= read -r line; do
					
					disk_name=${disk_info[$id]}
					
					if [[ "$line" == "SYNOLOGY-DISK-MIB::diskModel.$id ="* ]]; then
						disk_model=${line/"SYNOLOGY-DISK-MIB::diskModel."$id" = STRING: "/}; disk_model=${disk_model// /}
					fi
					
					if [[ "$line" == "SYNOLOGY-DISK-MIB::diskType.$id ="* ]]; then
						disk_type=${line/"SYNOLOGY-DISK-MIB::diskType."$id" = STRING: "/}
					fi
					
					if [[ "$line" == "SYNOLOGY-DISK-MIB::diskStatus.$id ="* ]]; then
						disk_status=${line/"SYNOLOGY-DISK-MIB::diskStatus."$id" = INTEGER: "/}
						#1=The disk is functioning normally
						#2=The disk has system partitions but no data
						#3=The disk is not partitioned
						#4=Partitions on the disk are damaged
						#5=The disk is damaged/crashed
					fi
				
					if [[ "$line" == "SYNOLOGY-DISK-MIB::diskTemperature.$id ="* ]]; then
						disk_temp=${line/"SYNOLOGY-DISK-MIB::diskTemperature."$id" = INTEGER: "/}
					fi
					
					#depending on version of DSM, we may or may not collect additional data
					MinDSMVersion=7.0
					/usr/bin/dpkg --compare-versions "$MinDSMVersion" gt "$DSMVersion"
					if [ "$?" -eq "0" ]; then
						dsm_type="Synology (DSM 6)" #version is DSM6, do nothing extra
					else
						dsm_type="Synology (DSM 7)"
						if [[ "$line" == "SYNOLOGY-DISK-MIB::diskRole.$id ="* ]]; then
							disk_role=${line/"SYNOLOGY-DISK-MIB::diskRole."$id" = STRING: "/}
							#"data" = Used by storage pool
							#"hotspare" = Assigned as a hot spare disk
							#"ssd_cache" = Used by SSD Cache
							#"none" = Not used by storage pool, nor hot spare, nor SSD Cache
							#"unknown" = Some error occurred
						fi
						
						if [[ "$line" == "SYNOLOGY-DISK-MIB::diskRetry.$id ="* ]]; then
							disk_retry=${line/"SYNOLOGY-DISK-MIB::diskRetry."$id" = INTEGER: "/}
						fi
						
						if [[ "$line" == "SYNOLOGY-DISK-MIB::diskBadSector.$id ="* ]]; then
							disk_BadSector=${line/"SYNOLOGY-DISK-MIB::diskBadSector."$id" = INTEGER: "/}
						fi
						
						if [[ "$line" == "SYNOLOGY-DISK-MIB::diskIdentifyFail.$id ="* ]]; then
							disk_IdentifyFail=${line/"SYNOLOGY-DISK-MIB::diskIdentifyFail."$id" = INTEGER: "/}
						fi
						
						if [[ "$line" == "SYNOLOGY-DISK-MIB::diskRemainLife.$id ="* ]]; then
							disk_RemainLife=${line/"SYNOLOGY-DISK-MIB::diskRemainLife."$id" = INTEGER: "/}
						fi
						
					fi
					
					done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.4.1.6574.2.1.1)
					
					MinDSMVersion=7.0
					/usr/bin/dpkg --compare-versions "$MinDSMVersion" gt "$DSMVersion"
					if [ "$?" -eq "0" ]; then
						#if this is DSM6, only post DSM6 related data
						post_url=$post_url"$measurement,nas_name=$nas_name,disk_name=$disk_name disk_model=$disk_model,disk_type=$disk_type,disk_temp=$disk_temp,disk_status=$disk_status
		"
					else
					#if this is DSM7, only post DSM7 related data
						post_url=$post_url"$measurement,nas_name=$nas_name,disk_name=$disk_name disk_model=$disk_model,disk_type=$disk_type,disk_temp=$disk_temp,disk_status=$disk_status,disk_role=$disk_role,disk_retry=$disk_retry,disk_BadSector=$disk_BadSector,disk_IdentifyFail=$disk_IdentifyFail,disk_RemainLife=$disk_RemainLife
		"						
					fi
				
					#check that none of the disks are too hot. if a disk is too hot, send an email warning that the disk is over heating
					
					if [ $sendmail_installed -eq 1 ]; then
						disk_temp_email
					else
						echo "WARNING - Could not send email notification that the drive temperature is too high. the temperature of $disk_name on $server_name has exceeded $max_disk_temp Degrees C / $max_disk_temp_F Degrees F. The current Temperature is $disk_temp"
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
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-STORAGEIO-MIB::storageIODevice)
				
				for id in "${!disk_info[@]}"
				do
					disk_path="/dev/"${disk_info[$id]}
					
					while IFS= read -r line; do
						if [[ "$line" == "SYNOLOGY-STORAGEIO-MIB::storageIONReadX.$id ="* ]]; then
							disk_reads=${line/"SYNOLOGY-STORAGEIO-MIB::storageIONReadX."$id" = Counter64: "/};
						fi
				
						if [[ "$line" == "SYNOLOGY-STORAGEIO-MIB::storageIONWrittenX.$id ="* ]]; then
							disk_writes=${line/"SYNOLOGY-STORAGEIO-MIB::storageIONWrittenX."$id" = Counter64: "/}
						fi
				
						if [[ "$line" == "SYNOLOGY-STORAGEIO-MIB::storageIOLA.$id ="* ]]; then
							disk_load=${line/"SYNOLOGY-STORAGEIO-MIB::storageIOLA."$id" = INTEGER: "/}
						fi
					done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.4.1.6574.101)
					
					post_url=$post_url"$measurement,nas_name=$nas_name,disk_path=$disk_path disk_reads=$disk_reads,disk_writes=$disk_writes,disk_load=$disk_load
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
				ups_battery_charge=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-UPS-MIB::upsBatteryChargeValue.0 -Oqv`; ups_battery_charge=${ups_battery_charge%\.*}
				
				#UPS Load
				ups_load=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-UPS-MIB::upsInfoLoadValue.0 -Oqv`;ups_load=${ups_load%\.*}
				
				#UPS State (OL is online, OL CHRG is plugged in but charging, OL DISCHRG is on battery")
				ups_status=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-UPS-MIB::upsInfoStatus.0 -Oqv`; ups_status=${ups_status//\"}
				
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
				ups_battery_runtime=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-UPS-MIB::upsBatteryRuntimeValue.0 -Oqv | awk {'print $1'}`
				
				post_url=$post_url"$measurement,nas_name=$nas_name,ups_group=\"NAS\" ups_status=$ups_status,ups_load=$ups_load,ups_battery_runtime=$ups_battery_runtime,ups_battery_charge=$ups_battery_charge
		"
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
				
				done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 IF-MIB::ifName | grep -E 'eth*|bond*')
				
				for id in "${!network_info[@]}"
				do
					interface_name=${network_info[$id]}
					
					while IFS= read -r line; do
						if [[ $line =~ "IF-MIB::ifHCInOctets.$id =" ]]; then
							bytes_recv=${line/"IF-MIB::ifHCInOctets."$id" = Counter64: "/};
						fi
				
						if [[ $line =~ "IF-MIB::ifHCOutOctets.$id =" ]]; then
							bytes_sent=${line/"IF-MIB::ifHCOutOctets."$id" = Counter64: "/};
						fi
				
					done < <(snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 1.3.6.1.2.1.31.1.1.1)
					
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
					
					#The percentage of GPU time spent on processing user space in last 1 second
					gpuUtilization=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuUtilization.0 -Ovt`
					
					#The percentage of GPU memory usage in last 1 second
					gpuMemoryUtilization=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryUtilization.0 -Ovt`
					
					#The amount of currently free GPU memory in kb
					gpuMemoryFree=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryFree.0 -Ovt`
					
					#The amount of currently used GPU memory in kb
					gpuMemoryUsed=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryUsed.0 -Ovt`
					
					#The total physical GPU memory size
					gpuMemoryTotal=`snmpwalk -v3 -l authPriv -u $nas_snmp_user -a $snmp_auth_protocol -A $snmp_authPass1 -x $snmp_privacy_protocol -X $snmp_privPass2 $nas_url:161 SYNOLOGY-GPUINFO-MIB::gpuMemoryTotal.0 -Ovt`
					
					#GPU Temperature
					gpuTemperature=`nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader`
					
					#GPU FAN Speed
					gpuFanSpeed=`nvidia-smi --query-gpu=fan.speed --format=csv,noheader`
					
					
					#System details to post
					post_url=$post_url"$measurement,nas_name=$nas_name gpu_utilization=$gpuUtilization,gpuMemoryUtilization=$gpuMemoryUtilization,gpuMemoryFree=$gpuMemoryFree,gpuMemoryUsed=$gpuMemoryUsed,gpuMemoryTotal=$gpuMemoryTotal,gpuTemperature=$gpuTemperature,gpuFanSpeed=$gpuFanSpeed
			"
					secondString=""
					post_url=${post_url//\INTEGER: /$secondString}
					secondString=""
					post_url=${post_url//\ %/$secondString}

					if [ $sendmail_installed -eq 1 ]; then
						if [ $gpuTemperature -ge $max_GPU ]
						then
						#echo the disk temp has been exceeded
							if [ $GPU_message_tracker -ge $email_interval ]
							then
							#echo the email has not been sent in over 1 hour, re-sending email
								mailbody="Warning the temperature of the NVR GPU on Server NVR has exceeded $max_GPU Degrees C / $max_GPU_f Degrees F "
								echo "from: $from_email_address " > $log_file_location/GPU0_contents.txt
								echo "to: $email_address " >> $log_file_location/GPU0_contents.txt
								echo "subject: Server_NVR GPU Temperature Warning " >> $log_file_location/GPU0_contents.txt
								echo "" >> $log_file_location/GPU0_contents.txt
								echo $mailbody >> $log_file_location/GPU0_contents.txt
								cat $log_file_location/GPU0_contents.txt | sendmail -t
								GPU_message_tracker=0
							fi
						fi
					else
						echo "WARNING - could not send email notification that the GPU is overheating. the temperature of the NVR GPU on Server NVR has exceeded $max_GPU Degrees C / $max_GPU_f Degrees F"
					fi
				else
					echo "Skipping GPU capture"
				fi
			else
				echo "Skipping GPU capture, GPU not installed"
			fi

			#########################################
			#Post to influxdb
			#########################################
	
			curl -XPOST "$influx_http_type://$influxdb_host:$influxdb_port/api/v2/write?bucket=$influxdb_name&org=$influxdb_org" -H "Authorization: Token $influxdb_pass" --data-raw "$post_url"
			
			if [ $debug -eq 1 ]; then
				echo "$post_url"
			fi
			
			let i=i+1
			
			echo "Capture #$i complete"
			
			#Sleeping for capture interval unless its last capture then we don't sleep
			if (( $i < $total_executions)); then
				sleep $(( $capture_interval -6))
			else
				#increment each disk counter by one to keep track of "minutes elapsed" since this script is expected to execute every minute 
				
				for (( counter=0; counter<$number_drives_in_system; counter++ ))
				do
					let disk_messge_tracker[$counter]=disk_messge_tracker[$counter]+1
					if [ $counter -eq 0 ];then
						echo -n "${disk_messge_tracker[$counter]}" > $email_logging_file_location
					else
						echo -n ",${disk_messge_tracker[$counter]}" >> $email_logging_file_location
					fi
				done
			
				let CPU_message_tracker=CPU_message_tracker+1
				echo -n ",$CPU_message_tracker" >> $email_logging_file_location #write CPU logging variable
			
				if [ $GPU_installed -eq 1 ];then
					let GPU_message_tracker=GPU_message_tracker+1
					echo -n ",$GPU_message_tracker" >> $email_logging_file_location #write GPU logging variable
				fi
			fi
			
		done
	else
		echo "script is disabled"
	fi
else
	echo "Configuration file unavailable"
fi
