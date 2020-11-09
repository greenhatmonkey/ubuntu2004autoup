#!/bin/bash


# include path in filename: /etc/apt/apt.conf.d/50unattended-upgrades.backup-gh
filename="/etc/apt/apt.conf.d/50unattended-upgrades"

function user_sudo_root()
{
if [[ $EUID -ne 0 ]]; then
	printf "This script is designed to be run by root\n"
	printf "Use: sudo\n"
	exit 1
fi
}

function setup_ssmtp()
{
echo "Do you have a ssmtp account setup to send emails from this container?"
echo "'yes all done = y', 'no i would like to setup = n', 'skip email setup please = s'"
printf "Please select (s/n/y):>"
read ssmtpSetup
if [ "$ssmtpSetup" == "s" ]; then 
    echo "do not select the email option later"
elif [ "$ssmtpSetup" == "y" ]; then
    echo "well done you"
elif [ "$ssmtpSetup" == "n" ]; then  
    quick_ssmtp_sum="94b92de3070aa64d518e5193371eed73"
    wget https://github.com/greenhatmonkey/ssmtp_configs/blob/master/quick_lxc_ssmtp.sh?raw=true
    downloaded_quick_ssmtp_sum="$(md5sum quick_lxc_ssmtp.sh?raw=true | awk '{print $1}')"
    if [ $downloaded_quick_ssmtp_sum == $quick_ssmtp_sum ]; then
        echo "checks out"
        mv quick_lxc_ssmtp.sh?raw=true ssmtp-setup.sh   
        bash ssmtp-setup.sh
    else
        echo "does not check out"
        printf "looking for $quick_ssmtp_sum but found $downloaded_quick_ssmtp_sum\n"
        read -r -p $"Press anykey to end script!"
		exit 1
    fi
else
    echo "Please select only 's,y,n'"
    setup_ssmtp
fi
}


##---------------------------------------------------
## backup 50unattended-upgrades incase we rerun script
function backup_doc()
{
        #script requires default config
        # backup and restore if script run twice
        if [ -f "${filename}-backup-gh" ]; then
                # backup exists, restore backup
                cp "${filename}-backup-gh" $filename
        elif [ ! -f "${filename}-backup-gh" ]; then
                #backup does not exist, create backup
                cp $filename ${filename}-backup-gh
        fi
}

##------------------------------------------------------
## uncomment updates

function uncomment_updates()
{
sed -i 's/\/\/ * "\${distro_id}\:\${distro_codename}-updates";/\t"\${distro_id}\:\${distro_codename}-updates";/g' $filename
}

##-----------------------------------------------------
## email alerts option

function email_option()
{
echo "Do you want to receive emails to alert you when an update as been done? (y/n)"
read email_op

if [ "$email_op" == "y" ]; then
    email_address
elif [ "$email_op" == "n" ]; then
    echo "ok no email alerts setup"
else
    echo "only enter 'y' or 'n'"
fi 
}

##------------------------------------------------------
## take an email address

function email_address()
{
echo "what email address would you like the email sent to:"
read email_add_send
echo "the email address you entered is:" $email_add_send "Is this correct? (y/n)"
read confirm_email_add
if [ $confirm_email_add == "y" ]; then
    sed -i "s/\/\/Unattended-Upgrade\:\:Mail \"\";/Unattended-Upgrade\:\:Mail \"$email_add_send\";/g" $filename
    email_alerts
elif [ $confirm_email_add == "n" ]; then 
    	email_address
else
    	echo "please only enter 'y' or 'n'"
    	email_address
fi
}

##-----------------------------------------------------
## when to receive email alerts

function email_alerts()
{
echo "When would you like to receive emails about updates?"
printf "\t1. always\n\t2. only-on-error\n\t3. on-change\nPlease enter 1, 2 or 3:>"
read email_when_option
if [ $email_when_option == "1" ]; then
    sed -i "s/\/\/Unattended-Upgrade\:\:MailReport \"on-change\"/Unattended-Upgrade\:\:MailReport \"always\"/g" $filename
elif [ $email_when_option == "2" ]; then
    sed -i "s/\/\/Unattended-Upgrade\:\:MailReport \"on-change\"/Unattended-Upgrade\:\:MailReport \"only-on-error\"/g" $filename
elif [ $email_when_option == "3" ]; then
    sed -i "s/\/\/Unattended-Upgrade\:\:MailReport \"on-change\"/Unattended-Upgrade\:\:MailReport \"on-change\"/g" $filename
else 
    echo "please only enter 1, 2 or 3! (1/2/3)"
    email_alerts
fi

check_apticron

}

##-----------------------------------------------------
## enable auto reboot

function auto_reboot()
{
	echo "would you like to enable automatic reboots? you can select time of reboot (2am)"
	printf "(y/n)"
	read reboot_option
	if [ $reboot_option == "y" ]; then
		sed -i "s/\/\/Unattended-Upgrade\:\:Automatic-Reboot \"false\";/\/\/Unattended-Upgrade\:\:Automatic-Reboot \"true\";/g" $filename
		auto_reboot_time
	elif [ $reboot_option == "n" ]; then
		echo "no auto reboot"
	fi
}

##--------------------------------------------------------
## select time for auto reboots

function auto_reboot_time()
{
echo "Please select a reboot time!"
printf "Make sure your syntax is 24hour time! separated by a colon! Syntax: 'hh:mm'  Example: '02:00'"
printf "\nPlease enter:>"
read reboot_time
printf "you entered \"$reboot_time\"\nEnter 'y' to continue or 'n' to try again(n/y):>"
read confirm_reboot_time
if [ $confirm_reboot_time == "y" ]; then
	printf "Unattended-Upgrade::Automatic-Reboot-Time \"$reboot_time\";\n" >> $filename
elif [ $confirm_reboot_time == "n" ]; then
	auto_reboot_time
fi

}

##--------------------------------------------------------------
### need to check user selected email alerts before we run check_apticron
### included in email_alerts function.
function check_apticron()
{
	if [ ! -d /etc/apticron ]; then
		# if directory /etc/apticron does not exist - install apticron
		echo "we are going to install apticron"
		echo "you will be prompted to config"
		echo "select OPTION"
		sudo apt update && sudo apt install apticron -y
	fi

	if [ -d /etc/apticron && ! -f /etc/apticron/apticron.conf ]; then
		touch /etc/apticron/apticron.conf
		printf "EMAIL=\"$email_add_send\"\n" >> /etc/apticron/apticron.conf
	fi

}

##----------------------------------------------------------------
## check the 20auto-upgrades files

function 20auto_upgrades()
{
# its hard to tell what defaults are in the file /etc/apt/apt.conf.d/20auto-upgrades
# so will include checks before we include these lines

update_pack_list="APT::Periodic::Update-Package-Lists"
upgrade_period="APT::Periodic::Unattended-Upgrade"
check_update=$(cat /etc/apt/apt.conf.d/20auto-upgrades | grep "$upgrade_period")
check_pack=$(cat /etc/apt/apt.conf.d/20auto-upgrades | grep "$update_pack_list")

# check if Unattended-upgrade is in file
if [ -z "$check_update" ]; then
	printf "its not there: $check_update\n"
	echo "APT::Periodic::Unattended-Upgrade \"1\";" >> /etc/apt/apt.conf.d/20auto-upgrades
else
	printf "its already there: $check_update\n"
fi

# check if update-package-lists is in file
if [ -z "$check_pack" ]; then
	printf "its not there: $check_pack\n"
	echo "APT::Periodic::Update-Package-Lists \"1\";" >> /etc/apt/apt.conf.d/20auto-upgrades
else
	printf "its already there: $check_pack\n" 
fi

}

##----------------------------------------------------------------
## First run

function first_run_update()
{
	unattended-upgrades -d
	echo "if you picked email alerts, check your email"
	echo "you can see upgrade logs at"
	echo "/var/log/unattended-upgrades/unattended-upgrades-dpkg.log"
	echo "/var/log/unattended-upgrades/unattended-upgrades.log"
}

##---------------------------------------------------------------
## Script Modules Functions to run.

user_sudo_root # will check user root or used sudo
setup_ssmtp # will ask if ssmtp email setup to send mail
backup_doc	# will backup file 
uncomment_updates #
email_option # ask if user wants to setup email alerts.
# email_address # take a email address # called by "email_option"
# email_alerts # when to receive email alerts # called by "email_address"
auto_reboot # would you like to auto reboot
# auto_reboot_time # select time for reboot # called by "auto_reboot"
# check_apticron # check apticron installed; if not; install # called by "email_alerts"
20auto_upgrades # will check entries are in 20auto_upgrades
first_run_update # will run unattended-upgrades with debug mode


