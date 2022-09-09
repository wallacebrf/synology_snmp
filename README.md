<div id="top"></div>
<!--
*** comments....
-->



<!-- PROJECT LOGO -->
<br />

<h3 align="center">Synology SNMP data Logging to InfluxDB version 2</h3>

  <p align="center">
    This project is comprised of a shell script that runs once per minute collecting data from DSM and placing it into InfluxDB version 2. 
    <br />
    <a href="https://github.com/wallacebrf/synology_snmp"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/wallacebrf/synology_snmp/issues">Report Bug</a>
    ·
    <a href="https://github.com/wallacebrf/synology_snmp/issues">Request Feature</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#About_the_project_Details">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Road map</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
### About_the_project_Details

<img src="https://raw.githubusercontent.com/wallacebrf/synology_snmp/main/single_server_1.png" alt="1313">
<img src="https://raw.githubusercontent.com/wallacebrf/synology_snmp/main/single_server_2.png" alt="1313">
<img src="https://raw.githubusercontent.com/wallacebrf/synology_snmp/main/single_server_3.png" alt="1313">
<img src="https://raw.githubusercontent.com/wallacebrf/synology_snmp/main/single_server_4.png" alt="1313">
<img src="https://raw.githubusercontent.com/wallacebrf/synology_snmp/main/single_server_5.png" alt="1313">

The script gathers different SNMP based details from a Synology NAS using SNMP version 3 (much more secure than version 2) such as the following and saves them to InfluxDb version 2:

1. System: System Uptime, System Status, System Fan Status, Model Name, Serial Number, Upgrade Available, DSM Version, System Temp. If an Expansion unit (DX517 etc) is installed, it will gather Expansion Model, Expansion Status

2. Memory: Total Memory, Real Memory Available, Buffer Memory Used, Cached Memory Used, Memory Free

3. CPU: CPU Usage Idle

4. Volume: Volume Name, Volume Total Size, Volume Used Size

5. RAID: RAID Name, RAID Status, RAID Free Size, RAID Total Size. For DSM specifically, added the "Hot Spare Count" 

6. Disk: Disk Name, Disk Model, Disk Type, Disk Status, Disk Temperature. For DSM Specifically, added Disk Role, Smart DATA (Disk Retry Count, Bad Sector Count, Disk Remaining Life)

7. UPS: UPS Battery Charge, UPS Load, UPS Status, UPS Battery Runtime

8. Network: Interface Name, Bytes Received, Bytes Sent 

9. GPU - If this is a DVA (Deep Video Analysis) system like the DVA3219 or DVA3221: GPU usage, GPU Temperature, GPU Memory Usage, GPU Fan Speed

Some items like system, GPU, CPU, and disk temperatures can send alert email notifications based on configurable set-points. 

<p align="right">(<a href="#top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

This project is written around a Synology NAS and their DSM specific SNMP OIDs and MIBs. 

### Prerequisites

1. this script is designed to be executed every 60 seconds
2. this script requires the installation of Synology MailPlus server package in package center in order to send emails. If it is not installed, the script will still work it just will not be able to send emails. 
	#the mail plus server must be properly configured to relay received messages to another email account. 
3. RAMDISK
	#NOTE: to reduce disk IOPS activity, it is recommended to create a RAMDISK for the temp files this script uses
	#to do so, create a scheduled task on boot up in Synology Task Scheduler to add the following line

		#mount -t tmpfs -o size=1% ramdisk $notification_file_location

	where "$notification_file_location" is the location you want the files stored and is a variable configured below

4. this script only supports SNMP V3. This is because lower versions are less secure 
	#SNMP must be enabled on the host NAS for the script to gather the NAS NAME
	#the SNMP settings for the NAS can all be entered into the web administration page
5. This script can be run through Synology Task Scheduler. However it has been observed that running large scripts like this as frequently as every 60 seconds causes the synoschedtask system application to use large amounts of resources and causes the script to execute slowly
	#details of this issue can be seen here:
	#https://www.reddit.com/r/synology/comments/kv7ufq/high_disk_usage_on_disk_1_caused_by_syno_task/
	#to fix this it is recommend to directly edit the crontab at /etc/crontab
	
	#this can be accomplished using vi /etc/crontab
	
	#add the following line: 
	```	*	*	*	*	*	root	$path_to_file/$filename```
	#details on crontab can be found here: https://man7.org/linux/man-pages/man5/crontab.5.html
6. This project requires a PHP server to be installed and configured to allow the web-administrative page to be available. 


### Installation

Note: this assumes InfluxDB version 2 and Grafana are already installed and properly configured.

1. Create the following directories on the NAS

```
1. %PHP_Server_Root%/config
2. %PHP_Server_Root%/logging
3. %PHP_Server_Root%/logging/notifications
```

note: ```%PHP_Server_Root%``` is what ever shred folder location the PHP web server root directory is configured to be.

2. Place the ```functions.php``` file in the root of the PHP web server running on the NAS

3. Place the ```synology_snmp.sh``` file in the ```/logging``` directory

4. Place the ```server2_config.php``` file in the ```/config``` directory

5. Create a scheduled task on boot up in Synology Task Scheduler to add the following line

		#mount -t tmpfs -o size=1% ramdisk $notification_file_location

		#where "$notification_file_location" is the location created above ```%PHP_Server_Root%/logging/notifications```

### Configuration "synology_snmp.sh"

1. Open the ```synology_snmp.sh``` file in a text editor. 
2. the script contains the following configuration variables
```
email_logging_file_location="/volume1/web/logging/notifications/logging_variable2.txt"
lock_file_location="/volume1/web/logging/notifications/synology_snmp2.lock"
config_file_location="/volume1/web/config/config_files/config_files_local/system_config2.txt"
log_file_location="/volume1/web/logging/notifications"
```

for the variables above, ensure the "/volume1/web" is the correct location for the root of the PHP web server, correct as required

3. delete the lines between ```#for my personal use as i have multiple Synology systems, these lines can be deleted by other users``` and ```#Script Start``` as those are for my personal use as i use this script for several units that have slightly different configurations	

4. find the lines
```
influx_http_type="http" #set to "http" or "https" based on your influxDB version
influxdb_org="home"
``` 

Ensure the organization matches your configuration and ensure the http type matches how your system is configured

### Configuration "server2_config.php"

1. Open the ```server2_config.php``` file in a text editor
2. the script contains the following configuration variables
```
$form_submit_location="index.php?page=6&config_page=server2_snmp";
$config_file="/volume1/web/config/config_files/config_files_local/system_config2.txt";
$page_title="Server2 Logging Configuration Settings";
```

ENSURE THE VALUES FOR ```$config_file``` ARE THE SAME AS THAT CONFIGURED IN [Configuration "synology_snmp.sh"] FOR THE VARIABLE ```config_file_location```

the ```form_submit_location``` can either be set to the name of the "server2_config.php" file itself, or if the "server2_config.php" file is embedded in another PHP file using an "include_once" then the location should be to that php file

the variable ```page_title``` controls the title of the page when viewing it in a browser. 


### Configuration of required settings

<img src="https://github.com/wallacebrf/synology_snmp/blob/main/config_1.png" alt="1313">
<img src="https://github.com/wallacebrf/synology_snmp/blob/main/config_2.png" alt="1314">

1. now that the files are where they need to be, using a browser go to the "server2_config.php" page. when the page loads for the first time, it will automatically create a "system_config2.txt" in the config directory. the values will all be default values and must be configured. 
2. ensure the script is enabled
3. configure maximum CPU, disk, and GPU temperatures (In F, not C)
4. configure email settings, the destination email address, the from email address, and the frequency in which notification emails will be re-sent if the issue still persists
5. check what types of data is to be collected from the NAS
6. enter the details for influxDB.
--> for InfluxDB 2, the "database" will be the randomly generated string identifying the data bucket, for example "a6878dc5c298c712"
--> for InfluxDB 2, the "User Name of Influx DB" can be left as the default value
--> for InfluxDB 2, the "Password" is the API access key / Authorization Token. 
7. on the NAS, go to Control Panel --> Terminal & SNMP --> SNMP and configure the SNMP version 3 settings. 
8. configure the SNMP settings for the Synology NAS. these settings must match the settings the NAS has been configured to use. 


### Configuration of crontab


This script can be run through Synology Task Scheduler. However it has been observed that running large scripts like this as frequently as every 60 seconds causes the synoschedtask system application to use large amounts of resources and causes the script to execute slowly
	#details of this issue can be seen here:
	#https://www.reddit.com/r/synology/comments/kv7ufq/high_disk_usage_on_disk_1_caused_by_syno_task/
	#to fix this it is recommend to directly edit the crontab at /etc/crontab
	
	#this can be accomplished using vi /etc/crontab
	
	#add the following line: 
	```	*	*	*	*	*	root	$path_to_file/$filename```
	#details on crontab can be found here: https://man7.org/linux/man-pages/man5/crontab.5.html


### Grafana Dashboards


Two dashboard JSON files are available. The entire dashboard is written around the new FLUX language which is more powerful and simpler to use. One used when monitoring a single Synology Unit. The other is for monitoring multiple Synology Units on a single dashboard. The current version supplied here shows the data for three different Synology units

the Dashboard requires the use of an add-on plug in from
https://grafana.com/grafana/plugins/mxswat-separator-panel/

there are three different items in the JSON that will need to be adjusted to match your installation. the first the bucket it is drawing data from. edit this to match your bucket name
```
from(bucket: \"Test/autogen\")
```

next, edit the name of the Synology NAS as reported by the script. the "Server_NVR" items are included "mixed into" the "Server2" items to demonstrate things like GPU usage, GPU VRAM usage, and GPU fan speed. if theSynology system is not a DVA unit with a graphics card, these "Server_NVR" items can be deleted. 

```
r[\"nas_name\"] == \"Server2\")
r[\"nas_name\"] == \"Server_NVR\")
```


<p align="right">(<a href="#top">back to top</a>)</p>



<!-- CONTRIBUTING -->
## Contributing

based on the script found here by user kernelkaribou
https://github.com/kernelkaribou/synology-monitoring

<p align="right">(<a href="#top">back to top</a>)</p>



<!-- LICENSE -->
## License

This is free to use code, use as you wish

<p align="right">(<a href="#top">back to top</a>)</p>



<!-- CONTACT -->
## Contact

Your Name - Brian Wallace - wallacebrf@hotmail.com

Project Link: [https://github.com/wallacebrf/synology_snmp)

<p align="right">(<a href="#top">back to top</a>)</p>



<!-- ACKNOWLEDGMENTS -->
## Acknowledgments


<p align="right">(<a href="#top">back to top</a>)</p>
