#!/bin/bash

self_file="$0"
self_source_url="https://gist.githubusercontent.com/koter84/86790850aa63354bda56d041de31dc70/raw/blueprints_update.sh"

# defaults
_do_update="false"
_debug="false"

# create a temp file for downloading
_tempfile=$(mktemp -t blueprints_update.XXXXXX)

# set options
options=$(getopt -a -l "help,debug,update" -o "hdu" -- "$@")
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

# check for self-updates
_blueprint_update_info "> ${self_file}"
wget -q -O "${_tempfile}" "${self_source_url}"
wget_result=$?
if [ "${wget_result}" != "0" ]
then
	_blueprint_update_info "! something went wrong while downloading, exiting..."
	_blueprint_update_info
	exit
fi
self_diff=$(diff "${self_file}" "${_tempfile}")
if [ "${self_diff}" == "" ]
then
	_blueprint_update_info "-> self up-2-date"
else
	if [ "${_do_update}" == "true" ]
	then
		cp "${_tempfile}" "${self_file}"
		chmod +x "${self_file}"
		_blueprint_update_info "-! self updated!"
	else
		_blueprint_update_info "-! self changed!"
	fi
fi
_blueprint_update_info

# check for blueprints updates
cd /config/blueprints/
find . -type f -name "*.yaml" -print0 | while read -d $'\0' file
do
	_blueprint_update_info "> ${file}"

	# get source url from file
	blueprint_source_url=$(grep source_url "${file}" | sed s/' *source_url: '//)
	_blueprint_update_debug "-> source_url: ${blueprint_source_url}"

	# check for a value in source_url
	if [ "${blueprint_source_url}" == "" ]
	then
		_blueprint_update_info "-! no source_url in file"
		_blueprint_update_info
		continue
	fi

	# check for custom source_url (the source_url doesn't exist in the source file)
	custom_source_url=""
	if [ "$(echo "${blueprint_source_url}" | grep '^custom-')" != "" ]
	then
		_blueprint_update_debug "-! remove custom- from source_url"
		sed -i s/'source_url: custom-'/'source_url: '/ "${file}"
		blueprint_source_url="$(echo "${blueprint_source_url}" | sed s/'^custom-'//)"
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
		blueprint_source_url=$(echo "${blueprint_source_url}" | sed -e s/'https:\/\/gist.github.com\/'/'https:\/\/gist.githubusercontent.com\/'/ -e s/"\$"/"\/raw\/$(basename "${file}")"/)
		_blueprint_update_debug "-> fixed source_url: ${blueprint_source_url}"
	fi

	# home assistant community blueprint exchange works a bit differently
	if [ "$(echo "${blueprint_source_url}" | grep 'https://community.home-assistant.io/')" != "" ]
	then
		_blueprint_update_debug "-! home assistant community blueprint exchange"
		# add .json and then extract the code block from the json...
		blueprint_source_url+=".json"
		_blueprint_update_debug "-> fixed source_url: ${blueprint_source_url}"

		_blueprint_update_debug "-> download blueprint"
		wget -q -O "${_tempfile}" "${blueprint_source_url}"
		wget_result=$?
		if [ "${wget_result}" != "0" ]
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

			cat "${_tempfile}"
		elif [ "$(cat "${_tempfile}" | jq -r '.post_stream.posts[0].cooked' | grep '<code class=\"lang-auto\">')" != "" ]
		then
			_blueprint_update_debug "-> found a lang-auto code-block"

			_blueprint_update_debug "-> extracting the blueprint"
			code="$(cat "${_tempfile}" | jq '.post_stream.posts[0].cooked' | sed -e s/'.*<code class=\\\"lang-auto\\\">'/''/ -e s/'<\/code>.*'/''/)"

			_blueprint_update_debug "-> saving the blueprint in the temp file"
			echo -e "${code}" > "${_tempfile}"

			cat "${_tempfile}"
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
		wget -q -O "${_tempfile}" "${blueprint_source_url}"
		wget_result=$?
		if [ "${wget_result}" != "0" ]
		then
			_blueprint_update_info "-! something went wrong while downloading, exiting..."
			_blueprint_update_info
			exit
		fi
	fi

	# check for source_url in the new source file
	new_blueprint_source_url=$(grep source_url "${_tempfile}" | sed s/' *source_url: '//)
	if [ "${new_blueprint_source_url}" == "" ]
	then
		_blueprint_update_debug "-! re-insert source_url"
		sed -i "s;blueprint:;blueprint:\n  source_url: ${custom_source_url};" "${_tempfile}"
	fi

	_blueprint_update_debug "-> compare blueprints"
	blueprint_diff=$(diff "${file}" "${_tempfile}")
	if [ "${blueprint_diff}" == "" ]
	then
		_blueprint_update_info "-> blueprint up-2-date"
	else
		if [ "${_do_update}" == "true" ]
		then
			cp "${_tempfile}" "${file}"
			need_reload="1"
			_blueprint_update_info "-! blueprint updated!"
		else
			_blueprint_update_info "-! blueprint changed!"
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