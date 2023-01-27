#!/bin/bash

self_file="$0"
self_source_url="https://raw.githubusercontent.com/koter84/HomeAssistant_Blueprints_Update/main/blueprints_update.sh"

# defaults
_do_update="false"
_debug="false"

# print debug function
function _blueprint_update_debug
{
	if [ "${_debug}" == "true" ]
	then
		echo "$@"
	fi
}

# print info function
function _blueprint_update_info
{
	echo "$@"
}

# fix url encodings
function _fix_url
{
	echo "$1" | sed \
		-e s/' '/'%20'/g
}

# create a persistant notification
function _persistent_notification_create
{
	local notification_id="$1"
	local notification_message="$2"

	if [ "${_blueprints_update_notify}" == "true" ]
	then
		curl --silent -X POST -H "Authorization: Bearer ${_blueprints_update_token}" -H "Content-Type: application/json" -d "{ \"notification_id\": \"blueprints_update:${notification_id}\", \"title\": \"Blueprints Update\", \"message\": \"${notification_message}\" }" "${_blueprints_update_server}/api/services/persistent_notification/create" >/dev/null
	else
		_blueprint_update_info "notifications not enabled"
	fi
}

# dismiss a persistant notification
function _persistent_notification_dismiss
{
	local notification_id="$1"

	if [ "${_blueprints_update_notify}" == "true" ]
	then
		curl --silent -X POST -H "Authorization: Bearer ${_blueprints_update_token}" -H "Content-Type: application/json" -d "{ \"notification_id\": \"blueprints_update:${notification_id}\" }" "${_blueprints_update_server}/api/services/persistent_notification/dismiss" >/dev/null
	else
		_blueprint_update_info "notifications not enabled"
	fi
}

# create a temp file for downloading
_tempfile=$(mktemp -t blueprints_update.XXXXXX)

# set options
options=$(getopt -a -l "help,debug,file:,update" -o "hdf:u" -- "$@")
eval set -- "$options"
while true
do
	case "$1" in
		-h|--help)
			echo "for help, look at the source..."
			exit 0
			;;
		-d|--debug)
			_debug="true"
			;;
		-f|--file)
			shift
			_file="$1"
			;;
		-u|--update)
			_do_update="true"
			;;
		--)
			shift
			break;;
	esac
	shift
	sleep 1
done

# start message
_blueprint_update_info "> ${self_file}"

# get config
if [ -f ${self_file}."conf" ]
then
	_blueprint_update_debug "-! load config [${self_file}.conf]"
	. ${self_file}."conf"

	_blueprints_update_notify="true"
	if [ "${_blueprints_update_server}" == "" ]
	then
		_blueprint_update_info "config file found, but _blueprints_update_server is not set"
		_blueprints_update_notify="false"
	fi
	if [ "${_blueprints_update_token}" == "" ]
	then
		_blueprint_update_info "config file found, but _blueprints_update_token is not set"
		_blueprints_update_notify="false"
	fi

	if [ "${_blueprints_update_auto_update,,}" == "true" ]
	then
		_do_update="true"
	fi
fi

# check for self-updates
if [ "${_file}" == "" ] || [ "${_file}" == "self" ]
then
	file="self"
	curl -s -o "${_tempfile}" "$(_fix_url "${self_source_url}")"
	curl_result=$?
	if [ "${curl_result}" != "0" ]
	then
		_blueprint_update_info "! something went wrong while downloading, exiting..."
		_blueprint_update_info
		exit
	fi
	self_diff=$(diff "${self_file}" "${_tempfile}")
	if [ "${self_diff}" == "" ]
	then
		_blueprint_update_info "-> self up-2-date"
		_persistent_notification_dismiss "${file}"
	else
		if [ "${_do_update}" == "true" ]
		then
			cp "${_tempfile}" "${self_file}"
			chmod +x "${self_file}"
			_blueprint_update_info "-! self updated!"
			if [ "${_blueprints_update_auto_update,,}" == "true" ]
			then
				_persistent_notification_create "${file}:no-auto-dismiss" "Updated ${file}"
			else
				_persistent_notification_create "${file}" "Updated ${file}"
			fi
			exit
		else
			_blueprint_update_info "-! self changed!"
			_persistent_notification_create "${file}" "Update available for ${file}\n\nupdate command:\n$0 --update --file ${file}"
		fi
	fi
	_blueprint_update_info
fi

# find the blueprints dir
if [ -d /config/blueprints/ ]
then
	cd /config/blueprints/
elif [ -d $(dirname "$0")/../config/blueprints/ ]
then
	cd $(dirname "$0")/../config/blueprints/
else
	_blueprint_update_info "-! no blueprints dir found"
	exit 1
fi

# check for blueprints updates
find . -type f -name "*.yaml" -print0 | while read -d $'\0' file
do
	# single file...
	if [ "${_file}" != "" ]
	then
		if [ "${_file}" != "${file}" ]
		then
			continue
		fi
	fi

	_blueprint_update_info "> ${file}"

	# get source url from file
	blueprint_source_url=$(grep source_url "${file}" | sed -e s/' *source_url: '// -e s/'"'//g -e s/"'"//g)
	_blueprint_update_debug "-> source_url: ${blueprint_source_url}"

	# check for a value in source_url
	if [ "${blueprint_source_url}" == "" ]
	then
		_blueprint_update_info "-! no source_url in file"
		_blueprint_update_info
		continue
	fi

	# fix source if it's regular github
	if [ "$(echo "${blueprint_source_url}" | grep 'https://github.com/')" != "" ]
	then
		_blueprint_update_debug "-! fix github url to raw"
		blueprint_source_url=$(echo "${blueprint_source_url}" | sed -e s/'https:\/\/github.com\/'/'https:\/\/raw.githubusercontent.com\/'/ -e s/'\/blob\/'/'\/'/)
		_blueprint_update_debug "-> fixed source_url: ${blueprint_source_url}"
	fi

	# fix source if it's github gist
	if [ "$(echo "${blueprint_source_url}" | grep 'https://gist.github.com/')" != "" ]
	then
		_blueprint_update_debug "-! fix github gist url to raw"

		# check for #filename in url
		if [ "$(echo "${blueprint_source_url}" | grep '#')" != "" ]
		then
			_blueprint_update_debug "-> remove #filename from the end of the url"
			blueprint_source_url="$(echo "${blueprint_source_url}" | sed s/'#.*'//)"
			_blueprint_update_debug "-> fixed source_url: ${blueprint_source_url}"
		fi

		blueprint_source_url=$(echo "${blueprint_source_url}" | sed -e s/'https:\/\/gist.github.com\/'/'https:\/\/gist.githubusercontent.com\/'/ -e s/"\$"/"\/raw\/$(basename "${file}")"/)
		_blueprint_update_debug "-> fixed source_url: ${blueprint_source_url}"
	fi

	# home assistant community blueprint exchange works a bit differently
	if [ "$(echo "${blueprint_source_url}" | grep 'https://community.home-assistant.io/')" != "" ]
	then
		_blueprint_update_debug "-! home assistant community blueprint exchange"

		# check if the url ends in .json		
		if [ "$(echo "${blueprint_source_url}" | grep '\.json$')" == "" ]
		then
			# add .json to the url
			blueprint_source_url+=".json"
			_blueprint_update_debug "-> fixed source_url: ${blueprint_source_url}"
		fi

		_blueprint_update_debug "-> download blueprint"
		curl -s -o "${_tempfile}" "$(_fix_url "${blueprint_source_url}")"
		curl_result=$?
		if [ "${curl_result}" != "0" ]
		then
			_blueprint_update_info "-! something went wrong while downloading, exiting..."
			_blueprint_update_info
			exit
		fi

		# find code block with lang-yaml or lang-auto
		if [ "$(cat "${_tempfile}" | jq -r '.post_stream.posts[0].cooked' | grep '<code class=\"lang-yaml\">')" != "" ]
		then
			_blueprint_update_debug "-> found a lang-yaml code-block"

			_blueprint_update_debug "-> extracting the blueprint"
			code="$(cat "${_tempfile}" | jq '.post_stream.posts[0].cooked' | sed -e s/'.*<code class=\\\"lang-yaml\\\">'/''/ -e s/'<\/code>.*'/''/)"

			_blueprint_update_debug "-> saving the blueprint in the temp file"
			echo -e "${code}" > "${_tempfile}"

			#cat "${_tempfile}"
		elif [ "$(cat "${_tempfile}" | jq -r '.post_stream.posts[0].cooked' | grep '<code class=\"lang-auto\">')" != "" ]
		then
			_blueprint_update_debug "-> found a lang-auto code-block"

			_blueprint_update_debug "-> extracting the blueprint"
			code="$(cat "${_tempfile}" | jq '.post_stream.posts[0].cooked' | sed -e s/'.*<code class=\\\"lang-auto\\\">'/''/ -e s/'<\/code>.*'/''/)"

			_blueprint_update_debug "-> saving the blueprint in the temp file"
			echo -e "${code}" > "${_tempfile}"

			#cat "${_tempfile}"
		else
			_blueprint_update_info "-! couldn't find a lang-yaml or lang-auto code-block, skipping..."
			_blueprint_update_info
			continue
		fi
	else
		# check filename is the same
		if [ "$(basename "${file}")" != "$(basename "${blueprint_source_url}")" ]
		then
			_blueprint_update_info "-! non-matching filename"
			_blueprint_update_debug "-! [$(basename "${file}")] != [$(basename "${blueprint_source_url}")]"
			_blueprint_update_info
			#continue
		fi

		_blueprint_update_debug "-> download blueprint"
		curl -s -o "${_tempfile}" "$(_fix_url "${blueprint_source_url}")"
		curl_result=$?
		if [ "${curl_result}" != "0" ]
		then
			_blueprint_update_info "-! something went wrong while downloading, exiting..."
			_blueprint_update_info
			exit
		fi
	fi

	# check for source_url in the new source file
	new_blueprint_source_url=$(grep source_url "${_tempfile}" | sed -e s/' *source_url: '// -e s/'"'//g -e s/"'"//g)
	if [ "${new_blueprint_source_url}" == "" ]
	then
		_blueprint_update_debug "-! re-insert source_url"
		sed -i "s;blueprint:;blueprint:\n  source_url: '${blueprint_source_url}';" "${_tempfile}"
	fi

	_blueprint_update_debug "-> compare blueprints"
	blueprint_diff=$(diff "${file}" "${_tempfile}")
	if [ "${blueprint_diff}" == "" ]
	then
		_blueprint_update_info "-> blueprint up-2-date"
		_persistent_notification_dismiss "${file}"
	else
		if [ "${_do_update}" == "true" ]
		then
			cp "${_tempfile}" "${file}"
			need_reload="1"
			_blueprint_update_info "-! blueprint updated!"
			if [ "${_blueprints_update_auto_update,,}" == "true" ]
			then
				_persistent_notification_create "${file}:no-auto-dismiss" "Updated ${file}"
			else
				_persistent_notification_create "${file}" "Updated ${file}"
			fi
		else
			_blueprint_update_info "-! blueprint changed!"
			_persistent_notification_create "${file}" "Update available for ${file}\n\nupdate command:\n$0 --update --file ${file}"
			if [ "${_debug}" == "true" ]
			then
				_blueprint_update_debug "-! diff:"
				diff "${file}" "${_tempfile}"
			fi
		fi
	fi

	_blueprint_update_info
done

if [ "${need_reload}" == "1" ]
then
	_blueprint_update_info "! there were updates, you should reload home assistant !"
fi

if [ -f "${_tempfile}" ]
then
	rm "${_tempfile}"
fi
