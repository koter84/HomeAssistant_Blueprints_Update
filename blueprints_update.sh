#!/bin/bash

self_file="$0"
self_source_url="https://raw.githubusercontent.com/koter84/HomeAssistant_Blueprints_Update/main/blueprints_update.sh"

# defaults
_do_update="false"
_debug="false"
_check_blacklist="false"

# print debug function
function _blueprint_update_debug
{
	if [ "${_debug}" == "true" ]
	then
		_blueprint_update_info "$@"
	fi
}

# print info function
function _blueprint_update_info
{
	if [ "${_debug}" == "true" ]
	then
		echo "$(date +"%Y-%m-%d %H:%M:%S") | $@"
	else
		echo "$@"
	fi
}

# print newline
function _blueprint_update_newline
{
	echo ""
}

function _blueprint_blacklist_check
{
	file_found=false
	for element in "${_blueprints_update_blacklist[@]}"; do
	  if [[ "$element" == "$@" ]]; then
	    file_found=true
	    break
	  fi
	done

	if [[ "$file_found" == true ]]; then
	  echo "true"
	else
	  echo "false"
	fi
}

# fix url encodings
function _fix_url
{
	echo "$1" | sed \
		-e 's/%/%25/g' \
		-e 's/ /%20/g' \
		-e 's/!/%21/g' \
		-e 's/"/%22/g' \
		-e "s/'/%27/g" \
		-e 's/#/%23/g' \
		-e 's/(/%28/g' \
		-e 's/)/%29/g' \
		-e 's/+/%2b/g' \
		-e 's/,/%2c/g' \
		-e 's/;/%3b/g' \
		-e 's/?/%3f/g' \
		-e 's/@/%40/g' \
		-e 's/\$/%24/g' \
		-e 's/\&/%26/g' \
		-e 's/\*/%2a/g' \
		-e 's/\[/%5b/g' \
		-e 's/\\/%5c/g' \
		-e 's/\]/%5d/g' \
		-e 's/\^/%5e/g' \
		-e 's/`/%60/g' \
		-e 's/{/%7b/g' \
		-e 's/|/%7c/g' \
		-e 's/}/%7d/g' \
		-e 's/~/%7e/g'
}

# download a file
function _file_download
{
	local file="$1"
	local source_url="$2"

	_blueprint_update_debug "-> download blueprint"
	curl -s -o "${file}" "$(_fix_url "${source_url}")"
	curl_result=$?
	if [ "${curl_result}" != "0" ]
	then
		_blueprint_update_info "! something went wrong while downloading, exiting..."
		_blueprint_update_newline
		exit
	fi
}

# create a persistant notification
function _persistent_notification_create
{
	local notification_id="$1"
	local notification_message="$2"

	if [ "${_blueprints_update_notify}" == "true" ]
	then
		_blueprint_update_debug "notification create: [${notification_id}] [${notification_message}]"
		curl ${_blueprints_update_curl_options} -X POST -H "Authorization: Bearer ${_blueprints_update_token}" -H "Content-Type: application/json" -d "{ \"notification_id\": \"bu:${notification_id}\", \"title\": \"Blueprints Update\", \"message\": \"${notification_message}\" }" "${_blueprints_update_server}/api/services/persistent_notification/create" >/dev/null
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
		_blueprint_update_debug "notification dismiss: [${notification_id}]"
		curl ${_blueprints_update_curl_options} -X POST -H "Authorization: Bearer ${_blueprints_update_token}" -H "Content-Type: application/json" -d "{ \"notification_id\": \"bu:${notification_id}\" }" "${_blueprints_update_server}/api/services/persistent_notification/dismiss" >/dev/null
	else
		_blueprint_update_info "notifications not enabled"
	fi
}

# create a temp file for downloading, and clean-up on exit
_tempfile=$(mktemp -t blueprints_update.XXXXXX)
function clean_tempfile
{
	if [ -f "${_tempfile}" ]
	then
		rm "${_tempfile}"
	fi
}
trap clean_tempfile EXIT

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

 	if [ "${_blueprints_update_curl_options}" == "" ]
	then
		_blueprints_update_curl_options="--silent"
	fi

	if [ "${_blueprints_update_auto_update,,}" == "true" ]
	then
		_do_update="true"
	fi

	if [ "${_blueprints_update_blacklist}" != "" ]; 
	then
		_blueprint_update_info "blacklist found, check blacklist is enabled"
		_check_blacklist="true"
	fi
fi

# check for self-updates
if [ "${_file}" == "" ] || [ "${_file}" == "self" ]
then
	file="self"
	_file_download "${_tempfile}" "${self_source_url}"
	self_diff=$(diff "${self_file}" "${_tempfile}")
	if [ "${self_diff}" == "" ]
	then
		_blueprint_update_info "-> self up-2-date"
		_persistent_notification_dismiss "$(basename "${file}")"
	else
		if [ "${_do_update}" == "true" ]
		then
			cp "${_tempfile}" "${self_file}"
			chmod +x "${self_file}"
			_blueprint_update_info "-! self updated!"
			if [ "${_blueprints_update_auto_update,,}" == "true" ]
			then
				_persistent_notification_create "no-dismiss:$(basename "${file}")" "Updated $(basename "${file}")"
			else
				_persistent_notification_create "$(basename "${file}")" "Updated $(basename "${file}")"
			fi
			exit
		else
			_blueprint_update_info "-! self changed!"
			_persistent_notification_create "$(basename "${file}")" "Update available for $(basename "${file}")\n\nupdate command:\n$0 --update --file '${file}'"
		fi
	fi
	_blueprint_update_newline
fi

# find the blueprints dir
if [ -d /config/blueprints/ ]
then
	cd /config/blueprints/
elif [ -d $(dirname "$0")/../config/blueprints/ ]
then
	cd $(dirname "$0")/../config/blueprints/
elif [ -d /usr/share/hassio/homeassistant/blueprints/ ]
then
	cd /usr/share/hassio/homeassistant/blueprints/
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

	if [ _check_blacklist ]
	then
		file_found=$(_blueprint_blacklist_check "${file}")
		if [ ${file_found} == "true" ]
		then
			_blueprint_update_info "-> blueprint found in blacklist skipping"
			_blueprint_update_newline
			continue
		fi
	fi

	# get source url from file
	blueprint_source_url=$(grep '^ *source_url: ' "${file}" | sed -e s/'^ *source_url: '// -e s/'"'//g -e s/"'"//g)
	_blueprint_update_debug "-> source_url: ${blueprint_source_url}"

	# check for a value in source_url
	if [ "${blueprint_source_url}" == "" ]
	then
		_blueprint_update_info "-! no source_url in file"
		_blueprint_update_newline
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

		# download the file
		_file_download "${_tempfile}" "${blueprint_source_url}"

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
			_blueprint_update_newline
			continue
		fi
	else
		# check filename is the same
		if [ "$(basename "${file}")" != "$(basename "${blueprint_source_url}")" ]
		then
			_blueprint_update_info "-! non-matching filename"
			_blueprint_update_debug "-! [$(basename "${file}")] != [$(basename "${blueprint_source_url}")]"
			_blueprint_update_newline
			#continue
		fi

		# download the file
		_file_download "${_tempfile}" "${blueprint_source_url}"
	fi

	# check for source_url in the new source file
	new_blueprint_source_url=$(grep '^ *source_url: ' "${_tempfile}" | sed -e s/'^ *source_url: '// -e s/'"'//g -e s/"'"//g)
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
				_persistent_notification_create "no-dismiss:$(basename "${file}")" "Updated $(basename "${file}")"
			else
				_persistent_notification_create "$(basename "${file}")" "Updated $(basename "${file}")"
			fi
		else
			_blueprint_update_info "-! blueprint changed!"
			_persistent_notification_create "$(basename "${file}")" "Update available for $(basename "${file}")\n\nupdate command:\n$0 --update --file '${file}'"
			if [ "${_debug}" == "true" ]
			then
				_blueprint_update_debug "-! diff:"
				diff "${file}" "${_tempfile}"
			fi
		fi
	fi

	_blueprint_update_newline
done

if [ "${need_reload}" == "1" ]
then
	_blueprint_update_info "! there were updates, you should reload home assistant !"
fi
