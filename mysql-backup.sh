#!/bin/bash
#
# mysql-backup.sh 
#
# This script generates a backup set of databases; each database table is
# stored in its own file, and all files are datestamped. Configuration 
# options are at the head of this file.
#
# Written by Pete Favelle, pete@fsquared.co.uk
# Copright 2015 F2 Limited <www.fsquared.co.uk>
#
# This script is released under the MIT License. See the LICENSE file.

# START OF CONFIGURATION

# MySQL Server connection - USER and PASS are a minimum, HOST and PORT are
#                           only required if your config is non-standard.
MYSQL_USER=
MYSQL_PASS=
MYSQL_HOST=
MYSQL_PORT=

# Backup destination - each database will be saved to a subdirectory of this
BACKUP_DIR=/var/mysql-backup/databases

# Database lists - if an include list is provided, ONLY those databases
#                  named will be backed up. If an exclude list is provided
#                  (without an include list), the ALL databases apart from
#                  those named are backed up. 
#                  If both lists are left empty, ALL databases are included.
DB_EXCLUDE="information_schema performance_schema"
DB_INCLUDE=

# Retention rules - the ?DAY values MUST be set, and indicate which day of 
#                   the week / month / year gets retained. 
#                   the ?RET values are optional except for DRET which MUST
#                   be set, and indicate how many days / weeks / months /
#                   years are retained. If unset, all such files are kept.
BACKUP_WDAY=1
BACKUP_MDAY=1
BACKUP_YDAY=1
BACKUP_DRET=7
BACKUP_WRET=4
BACKUP_MRET=12
BACKUP_YRET=

# Verbosity level - 0 means no output; 1 will give action logs and 2 will
#                   output details of each check
LOG_LEVEL=2

# END OF CONFIGURATION -- DO NOT EDIT BEYOND THIS LINE!

# Some helper functions

# abend; used to error out of the script, with an appropriate message;
#        expects two arguments, an error code and message.
abend() {
	# Check / parse the arguments
	if [[ -z ${1} || -z ${2} ]]
	then
		abend_err=1
		abend_msg="Invalid arguments passed to abend"
	else
		abend_err=${1}
		abend_msg=${2}
	fi	

	# Output the error message, and terminate the script
	echo "FATAL ERROR ${abend_err} - ${abend_msg}"
	exit ${abend_err}
}

# log; used to output logging information, depending on the log level;
#      expects two arguments, the log level and message.
log() {
	# Check the arguments have been provided
	if [[ -z ${1} || -z ${2} ]]
	then
		abend 2 "Invalid arguments passed to log function"
	fi

	# And determine if the message is wanted at our log level
	if [[ ${LOG_LEVEL} -ge ${1} ]]
	then
		echo ${2}
	fi
}

# Now into processing; log the start of our work
log 1 "MySQL Backup started `date`"

# Check that all the required parameters have been filled in!
log 1 "Checking that all parameters are valid"
if [[ -z ${MYSQL_USER} ]]
then
	abend 11 "MYSQL_USER must be defined"
fi
if [[ -z ${MYSQL_PASS} ]]
then
	abend 12 "MYSQL_PASS must be defined"
fi
if [[ -z ${BACKUP_WDAY} ]]
then
	abend 13 "BACKUP_WDAY must be defined"
fi
if [[ -z ${BACKUP_MDAY} ]]
then
	abend 14 "BACKUP_MDAY must be defined"
fi
if [[ -z ${BACKUP_YDAY} ]]
then
	abend 15 "BACKUP_YDAY must be defined"
fi
if [[ -z ${BACKUP_DRET} ]]
then
	abend 16 "BACKUP_DRET must be defined"
fi

# First up, build the mysql options line we'll use for everything
MYSQL_OPTS=""
if [[ ! -z ${MYSQL_HOST} ]]
then
  MYSQL_OPTS="${MYSQL_OPTS} -h${MYSQL_HOST}"
fi
if [[ ! -z ${MYSQL_PORT} ]]
then
  MYSQL_OPTS="${MYSQL_OPTS} -P${MYSQL_PORT}"
fi
log 2 "Using MySQL options : ${MYSQL_OPTS}"
MYSQL_OPTS="-u${MYSQL_USER} -p${MYSQL_PASS} ${MYSQL_OPTS}"

# We'll also need some other pseudo-constants
DSTAMP=`date +%Y-%m-%d`

# So, build a list of datbases to work with
log 1 "Fetching database list"
DB_LIST=`mysql ${MYSQL_OPTS} -BNse "show databases"`

# Work through these databases, applying the include or exclude list
for DB_NAME in ${DB_LIST}
do
	# Process include list first
	DB_TARGET=
	if [[ ! -z ${DB_INCLUDE} ]]
	then
		if [[ ${DB_INCLUDE} =~ ${DB_NAME} ]]
		then
			DB_TARGET=${DB_NAME}
		fi
	elif [[ ! -z ${DB_EXCLUDE} ]]
	then
		if [[ ! ${DB_EXCLUDE} =~ ${DB_NAME} ]]
		then
			DB_TARGET=${DB_NAME}
		fi
	else
		DB_TARGET=${DB_NAME}
	fi

	# So, if the target isn't blank we want to back up this database
	if [[ -z ${DB_TARGET} ]]
	then
		log 2 "Skipping ${DB_NAME}"
	else
		log 1 "Backing up ${DB_TARGET}"

		# Ensure we have the dump directory
		mkdir -p ${BACKUP_DIR}/${DB_TARGET} && cd ${BACKUP_DIR}/${DB_TARGET}

		# Build a list of tables in the database
		TAB_LIST=`mysql ${MYSQL_OPTS} ${DB_TARGET} -BNse "show tables"`

		# And dump each of those tables, datestamped
		for TAB_NAME in ${TAB_LIST}
		do
			log 2 "Dumping table ${TAB_NAME}"
			mysqldump ${MYSQL_OPTS} ${DB_TARGET} ${TAB_NAME} > ${DSTAMP}.${TAB_NAME}.sql
		done
	fi
done
log 1 "Backup phase complete"

# So, the backup element has completed - on to the backup set cleaning!

# Firstly, clear down daily files older than BACKUP_DRET days; any that
# fall on a BACKUP_WDAY day, rename to weekly files
log 1 "Cleaning up old backup files"
DAILY_THRESHOLD=`date --date="${BACKUP_DRET} days ago" +"%F"`
log 2 "Removing daily files prior to ${DAILY_THRESHOLD}"

for DAILY_FILE in `find ${BACKUP_DIR} -name '????-??-??.*.sql' -print`
do
	# Extract the date from the filename
	FILE_DATE=`basename ${DAILY_FILE} | cut -d. -f1`
	FILE_NAME=`basename ${DAILY_FILE} | cut -d. -f2-`

	# So, if it's before the threshold then it's for deletion
	if [[ ${FILE_DATE} < ${DAILY_THRESHOLD} ]]
	then
		# If it's a potential weekly file, move it
		if [[ `date --date=${FILE_DATE} +"%-u"` -eq ${BACKUP_WDAY} ]]
		then
			# Formulate a suitable filename
			WEEKLY_FILE=`dirname ${DAILY_FILE}`/`date --date=${FILE_DATE} +"%YW%W"`.${FILE_NAME}
			cp -fa ${DAILY_FILE} ${WEEKLY_FILE}
			log 2 "Saving daily file ${DAILY_FILE} as weekly ${WEEKLY_FILE}"
		fi

		# Same if it's a monthly file
		if [[ `date --date=${FILE_DATE} +"%-d"` -eq ${BACKUP_MDAY} ]]
		then
			# Formulate a suitable filename
			MONTHLY_FILE=`dirname ${DAILY_FILE}`/`date --date=${FILE_DATE} +"%Y-%m"`.${FILE_NAME}
			cp -fa ${DAILY_FILE} ${MONTHLY_FILE}
			log 2 "Saving daily file ${DAILY_FILE} as monthly ${MONTHLY_FILE}"
		fi

		# And lastly, the yearly check
		if [[ `date --date=${FILE_DATE} +"%-j"` -eq ${BACKUP_YDAY} ]]
		then
			# Formulate a suitable filename
			YEARLY_FILE=`dirname ${DAILY_FILE}`/`date --date=${FILE_DATE} +"%Y"`.${FILE_NAME}
			cp -fa ${DAILY_FILE} ${YEARLY_FILE}
			log 2 "Saving daily file ${DAILY_FILE} as yearly ${YEARLY_FILE}"
		fi

		# So finally, we can delete it!
		log 2 "Removing old daily file ${DAILY_FILE}"
		rm ${DAILY_FILE}
	fi
done

# Simpler cleardown for the weekly files, if required
if [[ ! -z ${BACKUP_WRET} ]]
then
	WEEKLY_THRESHOLD=`date --date="${BACKUP_WRET} weeks ago" +"%YW%W"`
	log 2 "Removing weekly files prior to ${WEEKLY_THRESHOLD}"
	for WEEKLY_FILE in `find ${BACKUP_DIR} -name '????W??.*.sql' -print`
	do
		# Extract the date from the filename
		FILE_DATE=`basename ${WEEKLY_FILE} | cut -d. -f1`

		# So, if it's before the threshold then it's for deletion
		if [[ ${FILE_DATE} < ${WEEKLY_THRESHOLD} ]]
		then
			# No complicated archiving, just delete it
			log 2 "Removing old weekly file ${WEEKLY_FILE}"
			rm ${WEEKLY_FILE}
		fi
	done
fi

# Ditto, the monthly ones
if [[ ! -z ${BACKUP_MRET} ]]
then
	MONTHLY_THRESHOLD=`date --date="${BACKUP_MRET} months ago" +"%Y-%m"`
	log 2 "Removing monthly files prior to ${MONTHLY_THRESHOLD}"
	for MONTHLY_FILE in `find ${BACKUP_DIR} -name '????-??.*.sql' -print`
	do
		# Extract the date from the filename
		FILE_DATE=`basename ${MONTHLY_FILE} | cut -d. -f1`

		# So, if it's before the threshold then it's for deletion
		if [[ ${FILE_DATE} < ${MONTHLY_THRESHOLD} ]]
		then
			# No complicated archiving, just delete it
			log 2 "Removing old monthly file ${MONTHLY_FILE}"
			rm ${MONTHLY_FILE}
		fi
	done
fi

# And lastly, the yearlies.
if [[ ! -z ${BACKUP_YRET} ]]
then
	YEARLY_THRESHOLD=`date --date="${BACKUP_YRET} years ago" +"%Y"`
	log 2 "Removing yearly files prior to ${YEARLY_THRESHOLD}"
	for YEARLY_FILE in `find ${BACKUP_DIR} -name '????.*.sql' -print`
	do
		# Extract the date from the filename
		FILE_DATE=`basename ${YEARLY_FILE} | cut -d. -f1`

		# So, if it's before the threshold then it's for deletion
		if [[ ${FILE_DATE} < ${YEARLY_THRESHOLD} ]]
		then
			# No complicated archiving, just delete it
			log 2 "Removing old yearly file ${YEARLY_FILE}"
			rm ${YEARLY_FILE}
		fi
	done
fi

log 1 "Housekeeping phase complete"
log 1 "Script ends"
