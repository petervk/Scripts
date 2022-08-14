#!/bin/bash

########## CONFIGURATIONS ##########
# Host on which qBittorrent runs
qbt_host="http://10.0.0.100"
# Port -> the same port that is inside qBittorrent option -> Web UI -> Web User Interface
qbt_port="8081"
# Username to access to Web UI
qbt_username="admin"
# Password to access to Web UI
qbt_password="adminadmin"

# If true (lowercase) the script will inject trackers inside private torrent too (not a good idea)
ignore_private=false

# Configure here your trackers list
declare -a live_trackers_list_urls=(
	"https://newtrackon.com/api/stable"
	"https://trackerslist.com/best.txt"
	"https://trackerslist.com/http.txt"
	"https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt"
    )

jq_executable="$(command -v jq)"
curl_executable="$(command -v curl)"
auto_tor_grab=0
test_in_progress=0
applytheforce=0

if [[ -z $jq_executable ]]; then
	echo -e "\n\e[0;91;1mFail on jq. Aborting.\n\e[0m"
	echo "You can find it here: https://stedolan.github.io/jq/"
	echo "Or you can install it with -> sudo apt install jq"
	exit 1
fi

if [[ -z $curl_executable ]]; then
	echo -e "\n\e[0;91;1mFail on curl. Aborting.\n\e[0m"
	echo "You can install it with -> sudo apt install curl"
	exit 2
fi

########## FUNCTIONS ##########
generate_trackers_list () {
	for j in "${live_trackers_list_urls[@]}"; do
		tmp_trackers_list+=$($curl_executable -sS $j)
		tmp_trackers_list+=$'\n'
	done

	trackers_list=$(echo "$tmp_trackers_list" | awk '{for (i=1;i<=NF;i++) if (!a[$i]++) printf("%s%s",$i,FS)}{printf("\n")}' | xargs | tr ' ' '\n')
	if [[ $? -ne 0 ]]; then
		echo "I can't download the list, I'll use a static one"
cat >"${trackers_list}" <<'EOL'
udp://tracker.coppersurfer.tk:6969/announce
http://tracker.internetwarriors.net:1337/announce
udp://tracker.internetwarriors.net:1337/announce
udp://tracker.opentrackr.org:1337/announce
udp://9.rarbg.to:2710/announce
udp://exodus.desync.com:6969/announce
udp://explodie.org:6969/announce
http://explodie.org:6969/announce
udp://public.popcorn-tracker.org:6969/announce
udp://tracker.vanitycore.co:6969/announce
http://tracker.vanitycore.co:6969/announce
udp://tracker1.itzmx.com:8080/announce
http://tracker1.itzmx.com:8080/announce
udp://ipv4.tracker.harry.lu:80/announce
udp://tracker.torrent.eu.org:451/announce
udp://tracker.tiny-vps.com:6969/announce
udp://tracker.port443.xyz:6969/announce
udp://open.stealth.si:80/announce
udp://open.demonii.si:1337/announce
udp://denis.stalker.upeer.me:6969/announce
udp://bt.xxx-tracker.com:2710/announce
http://tracker.port443.xyz:6969/announce
udp://tracker2.itzmx.com:6961/announce
udp://retracker.lanta-net.ru:2710/announce
http://tracker2.itzmx.com:6961/announce
http://tracker4.itzmx.com:2710/announce
http://tracker3.itzmx.com:6961/announce
http://tracker.city9x.com:2710/announce
http://torrent.nwps.ws:80/announce
http://retracker.telecom.by:80/announce
http://open.acgnxtracker.com:80/announce
wss://ltrackr.iamhansen.xyz:443/announce
udp://zephir.monocul.us:6969/announce
udp://tracker.toss.li:6969/announce
http://opentracker.xyz:80/announce
http://open.trackerlist.xyz:80/announce
udp://tracker.swateam.org.uk:2710/announce
udp://tracker.kamigami.org:2710/announce
udp://tracker.iamhansen.xyz:2000/announce
udp://tracker.ds.is:6969/announce
udp://pubt.in:2710/announce
https://tracker.fastdownload.xyz:443/announce
https://opentracker.xyz:443/announce
http://tracker.torrentyorg.pl:80/announce
http://t.nyaatracker.com:80/announce
http://open.acgtracker.com:1096/announce
wss://tracker.openwebtorrent.com:443/announce
wss://tracker.fastcast.nz:443/announce
wss://tracker.btorrent.xyz:443/announce
udp://tracker.justseed.it:1337/announce
udp://thetracker.org:80/announce
udp://packages.crunchbangplusplus.org:6969/announce
https://1337.abcvg.info:443/announce
http://tracker.tfile.me:80/announce.php
http://tracker.tfile.me:80/announce
http://tracker.tfile.co:80/announce
http://retracker.mgts.by:80/announce
http://peersteers.org:80/announce
http://fxtt.ru:80/announce
EOL
	fi
	number_of_trackers_in_list=$(echo "$trackers_list" | wc -l)
}

inject_trackers () {
	start=1
	while read tracker; do
		if [ -n "$tracker" ]; then
			echo -ne "\e[0;36;1m$start/$number_of_trackers_in_list - Adding tracker $tracker\e[0;36m"
			echo "$qbt_cookie" | $curl_executable --silent --fail --show-error \
					--cookie - \
					--request POST "${qbt_host}:${qbt_port}/api/v2/torrents/addTrackers" --data "hash=$1" --data "urls=$tracker"

			if [ $? -eq 0 ]; then
				echo -e " -> \e[32mSuccess! "
			else
				echo -e " - \e[31m< Failed > "
			fi
		fi
		start=$((start+1))
	done <<< "$trackers_list"
	echo "Done!"
}

get_torrent_list () {
	get_cookie
	torrent_list=$(echo "$qbt_cookie" | $curl_executable --silent --fail --show-error \
		--cookie - \
		--request GET "${qbt_host}:${qbt_port}/api/v2/torrents/info")
}

get_cookie () {
	qbt_cookie=$($curl_executable --silent --fail --show-error \
		--header "Referer: ${qbt_host}:${qbt_port}" \
		--cookie-jar - \
		--request GET "${qbt_host}:${qbt_port}/api/v2/auth/login?username=${qbt_username}&password=${qbt_password}")
}

hash_check() {
	case $1 in
		( *[!0-9A-Fa-f]* | "" ) return 1 ;;
		( * )
			case ${#1} in
				( 32 | 40 ) return 0 ;;
				( * )       return 1 ;;
			esac
	esac
}

wait() {
	w=$1
	echo "I'll wait ${w}s to be sure ..."
	while [ $w -gt 0 ]; do
		echo -ne "$w\033[0K\r"
		sleep 1
		w=$((w-1))
	done
}
########## FUNCTIONS ##########

if [ "$1" == "--force" ]; then
	applytheforce=1
	shift
fi

if [[ -n "${sonarr_download_id}" ]] || [[ -n "${radarr_download_id}" ]] || [[ -n "${lidarr_download_id}" ]] || [[ -n "${readarr_download_id}" ]]; then
	wait 5
	if [[ -n "${sonarr_download_id}" ]]; then
		echo "Sonarr varialbe found -> $sonarr_download_id"
		hash=$(echo "$sonarr_download_id" | awk '{print tolower($0)}')
	fi

	if [[ -n "${radarr_download_id}" ]]; then
		echo "Radarr varialbe found -> $radarr_download_id"
		hash=$(echo "$radarr_download_id" | awk '{print tolower($0)}')
	fi

	if [[ -n "${lidarr_download_id}" ]]; then
		echo "Lidarr varialbe found -> $lidarr_download_id"
		hash=$(echo "$lidarr_download_id" | awk '{print tolower($0)}')
	fi

	if [[ -n "${readarr_download_id}" ]]; then
		echo "Readarr varialbe found -> $readarr_download_id"
		hash=$(echo "$readarr_download_id" | awk '{print tolower($0)}')
	fi

	hash_check "${hash}"
	if [[ $? -ne 0 ]]; then
		echo "The download is not for a torrent client, I'll exit"
		exit 3
	fi
	auto_tor_grab="1"
fi

if [[ $sonarr_eventtype == "Test" ]] || [[ $radarr_eventtype == "Test" ]] || [[ $lidarr_eventtype == "Test" ]] || [[ $readarr_eventtype == "Test" ]]; then
	echo "Test in progress..."
	test_in_progress=1
fi

if [ $test_in_progress -eq 1 ]; then
	echo "Good-bye!"
elif [ $auto_tor_grab -eq 0 ]; then # manual run
	get_torrent_list

	if [ $? -ne 0 ]; then
		echo -e "\n\e[0;91;1mFail on qBittorrent. Aborting.\n\e[0m"
		exit 4
	fi

	if [ $# -eq 0 ]; then
		echo -e "\n\e[31mThis script expects one or more parameters\e[0m"
		echo -e "\e[0;36m${0##*/} \t\t- list current torrents "
		echo -e "${0##*/} \$s1 \$s2...\t- add trackers to first torrent with part of name \$s1 and \$s2"
		echo -e "${0##*/} .\t\t- add trackers to all torrents"
		echo -e "Names are case insensitive "
		echo -e "\n\e[0;32;1mCurrent torrents:\e[0;32m"
		echo "$torrent_list" | $jq_executable --raw-output '.[] .name'
		exit 5
	fi

	while [ $# -ne 0 ]; do
		tor_to_search="$1"

		if [ "$tor_to_search" = "." ]; then
			torrent_name_check=1
			torrent_name_list=$(echo "$torrent_list" | $jq_executable --raw-output '.[] .name')
		else
			torrent_name_list=$(echo "$torrent_list" | $jq_executable --raw-output --arg tosearch "$tor_to_search" '.[] | select(.name|test("\($tosearch)";"i")) .name')

			if [ -n "$torrent_name_list" ]; then # not empty
				torrent_name_check=1
				echo -e "\n\e[0;32;1mI found the following torrent:\e[0;32m"
				echo "$torrent_name_list"
			else
				torrent_name_check=0
			fi
		fi

		if [ $torrent_name_check -eq 0 ]; then
			echo -e "\e[0;31;1mI didn't find a torrent with the text: \e[21m$1\e[0m"
			shift
			continue
		else
			while read -r single_found; do
				tor_name_array+=("$single_found")
				hash=$(echo "$torrent_list" | $jq_executable --raw-output --arg tosearch "$single_found" '.[] | select(.name == "\($tosearch)") | .hash')
				tor_hash_array+=("$hash")
				tor_trackers_list=$(echo "$torrent_list" | $jq_executable --raw-output --arg tosearch "$hash" '.[] | select(.hash == "\($tosearch)") | .magnet_uri')
				tor_trackers_array+=("$tor_trackers_list")
			done <<< "$torrent_name_list"
		fi
		shift
	done

	if [ ${#tor_name_array[@]} -gt 0 ]; then
		for i in "${!tor_name_array[@]}"; do
			echo -ne "\n\e[0;1;4;32mFor the Torrent: \e[0;4;32m"
			echo "${tor_name_array[$i]}"

			if [[ $ignore_private == true ]] || [ $applytheforce -eq 1 ]; then # Inject anyway the trackers inside any torrent
				if [ $applytheforce -eq 1 ]; then
					echo -e "\e[0m\e[33mApplytheforce active, I'll inject trackers anyway\e[0m"
				else
					echo -e "\e[0m\e[33mignore_private set to true or applytheforce active, I'll inject trackers anyway\e[0m"
				fi
				generate_trackers_list
				inject_trackers ${tor_hash_array[$i]}
			else
				private_check=$(echo "$qbt_cookie" | $curl_executable --silent --fail --show-error --cookie - --request GET "${qbt_host}:${qbt_port}/api/v2/torrents/trackers?hash=$(echo "$torrent_list" | $jq_executable --raw-output --arg tosearch "${tor_name_array[$i]}" '.[] | select(.name == "\($tosearch)") | .hash')" | $jq_executable --raw-output '.[0] | .msg | contains("private")')

				if [[ $private_check == true ]]; then
					private_tracker_name=$(echo "$qbt_cookie" | $curl_executable --silent --fail --show-error --cookie - --request GET "${qbt_host}:${qbt_port}/api/v2/torrents/trackers?hash=$(echo "$torrent_list" | $jq_executable --raw-output --arg tosearch "${tor_name_array[$i]}" '.[] | select(.name == "\($tosearch)") | .hash')" | $jq_executable --raw-output '.[3] | .url' | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/')
					echo -e "\e[31m< Private tracker found \e[0m\e[33m-> $private_tracker_name <- \e[0m\e[31mI'll not add any extra tracker >\e[0m"
				else
					echo -e "\e[0m\e[33mThe torrent is not private, I'll inject trackers on it\e[0m"
					generate_trackers_list
					inject_trackers ${tor_hash_array[$i]}
				fi
			fi
		done
	else
		echo "No torrents found, exiting"
	fi
else # auto_tor_grab active, so some *Arr
	wait 5
	get_torrent_list

	private_check=$(echo "$qbt_cookie" | $curl_executable --silent --fail --show-error --cookie - --request GET "${qbt_host}:${qbt_port}/api/v2/torrents/trackers?hash=$hash" | $jq_executable --raw-output '.[0] | .msg | contains("private")')

	if [[ $private_check == true ]]; then
		private_tracker_name=$(echo "$qbt_cookie" | $curl_executable --silent --fail --show-error --cookie - --request GET "${qbt_host}:${qbt_port}/api/v2/torrents/trackers?hash=$hash" | $jq_executable --raw-output '.[3] | .url' | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/')
		echo -e "\e[31m< Private tracker found \e[0m\e[33m-> $private_tracker_name <- \e[0m\e[31mI'll not add any extra tracker >\e[0m"
	else
		echo -e "\e[0m\e[33mThe torrent is not private, I'll inject trackers on it\e[0m"
		generate_trackers_list
		inject_trackers $hash
	fi
fi