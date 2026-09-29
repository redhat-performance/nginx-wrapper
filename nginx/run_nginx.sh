#!/bin/bash
#
#                         License
#
#=================================================
# Copyright (C) June 4, 2026  David Valin dvalin@redhat.com
#=================================================
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# This script automates the execution of nginx.  It will determine the
# set of default run parameters based on the system configuration.
#

#=================================================
nginx_version="v1.00"
version=1.00
test_name=nginx
#=================================================
results_file="results_${test_name}.csv"
arguments="$@"
script_dir=$(realpath $(dirname $0))
pcpdir=""
tag_name=4.2.0

connections=1,2,4,8,16,32,64
run_cns=""
threads=""
run_time=60

exit_out()
{
	echo $1
	exit $2
}

if [ -z "$NGINX_WRAPPER_REEXEC" ]; then
	log_file=$(mktemp /tmp/nginx.XXXXXX.out)
	trap 'rm -f "$log_file"' EXIT INT TERM
	NGINX_WRAPPER_REEXEC=1 "$0" "$@" &> "$log_file"
	rtc=$?
	cat "$log_file"
	exit $rtc
fi

curdir=$(dirname $(realpath $0))
if [[ $0 == "./"* ]]; then
	chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
	if [[ $chars == 1 ]]; then
		run_dir=`pwd`
	else
		run_dir=`echo $0 | cut -d'/' -f 1-${chars} | cut -d'.' -f2-`
		run_dir="${curdir}${run_dir}"
	fi
elif [[ $0 != "/"* ]]; then
	dir=`echo $0 | rev | cut -d'/' -f2- | rev`
	run_dir="${curdir}/${dir}"
else
	chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
	run_dir=`echo $0 | cut -d'/' -f 1-${chars}`
	if [[ $run_dir != "/"* ]]; then
		run_dir=${curdir}/${run_dir}
	fi
fi
cd $run_dir
rm -f *csv *data

show_usage=0

TOOLS_BIN="$HOME/test_tools"
export TOOLS_BIN

usage()
{
	echo "Usage $1:"
	echo add usage
	source $TOOLS_BIN/general_setup --usage
	exit $E_USAGE
}


attempt_tools_generic()
{
	method="$1"
        if [[ ! -d "$TOOLS_BIN" ]]; then
               $method ${tools_git}/archive/refs/heads/main.zip
                if [[ $? -eq 0 ]]; then
                        unzip -q main.zip
                        mv test_tools-wrappers-main ${TOOLS_BIN}
                        rm main.zip
                fi
        fi
}

attempt_tools_git()
{
        if [[ ! -d "$TOOLS_BIN" ]]; then
                git clone $tools_git "$TOOLS_BIN"
                if [ $? -ne 0 ]; then
                        exit_out "Error: pulling git $tools_git failed." 101
                fi
        fi
}

install_test_tools()
{
	#
	# Clone the repo that contains the common code and tools
	#
	tools_git=https://github.com/redhat-performance/test_tools-wrappers
	found=0
	for arg in "$@"; do
		if [ $found -eq 1 ]; then
			tools_git=$arg
			found=0
		fi
		if [[ $arg == "--tools_git" ]]; then
			found=1
		fi

		#
		# We do the usage check here, as we do not want to be calling
		# the common parsers then checking for usage here.  Doing so will
		# result in the script exiting with out giving the test options.
		#
		if [[ $arg == "--usage" ]]; then
			show_usage=1
		fi
	done

	#
	# Check to see if the test tools directory exists.  If it does, we do not need to
	# clone the repo.
	#
	attempt_tools_generic "wget"
	attempt_tools_generic "curl -L -O "
	attempt_tools_git

	if [ $show_usage -eq 1 ]; then
		usage $1
	fi
}

install_test_tools "$@"

#
# Variables set by general setup.
#
# TOOLS_BIN: points to the tool directory
# to_home_root: home directory
# to_configuration: configuration information
# to_times_to_run: number of times to run the test
# to_run_label: Label for the run
# to_user: User on the test system running the test
# to_sys_type: for results info, basically aws, azure or local
# to_sysname: name of the system
# to_tuned_setting: tuned setting
#

pushd $curdir 2> /dev/null
source "$TOOLS_BIN/general_setup" "$@"
popd 2> /dev/null
# Gather hardware information
$TOOLS_BIN/gather_data ${curdir}

execute_nginx()
{
	out_file=nginx_iter_${1}

	run_threads=$(echo $threads | sed "s/,/ /g")
	run_cns=$(echo $connections | sed "s/,/ /g")
	for cns in $run_cns;
	do
		for th in $run_threads;
		do
			if [[ $cns -lt $th ]]; then
				continue
			fi
			start_time=$(retrieve_time_stamp)
			if [[ $to_use_pcp -eq 1 ]]; then
				start_pcp_subset 
				results2pcp_add_value "numthreads:${th}"
				results2pcp_add_value "iteration:${2}"
				results2pcp_add_value_commit
			fi
			wrk -t${th} -c${cns} -d${run_time}s http://localhost/ > nginx_results_${1}_iter_${th}_threads_${cns}_cns.data
			
			if [[ $to_use_pcp -eq 1 ]]; then
				rsec=$(grep -h "Requests/sec:" nginx_results_${1}_iter_${th}_threads_${cns}_cns.data | cut -d: -f 2 | sed "s/ //g" | cut -d'.' -f 1)
				if [[  "$rsec"  =~ ^[0-9]+$ ]]; then
					results2pcp_multiple "RPS:${rsec}"
				else
					echo Did not find rsec in nginx_results_${1}_iter_${th}_threads_${cns}_cns.data
				fi
				sleep 5
				reset_pcp_om
				stop_pcp_subset 
			fi
			end_time=$(retrieve_time_stamp)
			echo start_time: $start_time >> nginx_results_${1}_iter_${th}_threads_${cns}_cns.data
			echo end_time: $end_time >> nginx_results_${1}_iter_${th}_threads_${cns}_cns.data
		done
	done
}

create_summary_file()
{
	$TOOLS_BIN/test_header_info --front_matter --results_file $results_file --host $to_configuration --sys_type $to_sys_type --tuned $to_tuned_setting --results_version $nginx_version --test_name $test_name --field_header "# connections,requests/sec,KB/sec"

	#
	# Create results summary file, max results for each # connections.
	#
	for cns in $run_cns;
	do
		rsec_total=0
		tfsec_total=0
		for file in $(ls nginx_results_*threads_${cns}_cns.data);
		do
			if [[ $file == "" ]]; then
				continue
			fi
			rsec=$(grep "Requests/sec:" $file | cut -d: -f 2 | sed "s/ //g" | cut -d'.' -f 1)
			let "rsec_total=${rsec_total}+${rsec}"
			tfsec_info=$(grep "Transfer/sec" $file | cut -d: -f2-)
			unit=$(echo $tfsec_info | tr -cd '[:alpha:]' )
			unit=${unit:0:1}
			value=$(echo $tfsec_info | tr -dc '0-9\.')
			tval=$(${TOOLS_BIN}/convert_val --from_unit $unit --value $value --to_unit K | sed "s/K//g")
			let "tfsec_total=${tfsec_total}+${tval}"
		done
		rsec_avg=$(echo ${rsec_total}/$to_times_to_run | bc)
		tfsec_avg=$(echo ${tfsec_total}/$to_times_to_run | bc)
		time_file=$(grep "Requests/sec:" nginx_results_*threads_${cns}_cns.data | cut -d: -f 1 | tail -1)
		stime=$(grep start_time $time_file | cut -d: -f 2- | sed "s/ //g")
		etime=$(grep end_time $time_file | cut -d: -f 2- | sed "s/ //g")
		echo ${cns},${rsec_avg},${tfsec_avg},${stime},${etime} >> $results_file
	done
#	${TOOLS_BIN}/save_results --curdir $curdir --home_root $to_home_root --other_files "*_summary,run*log,test_results_report,${pcpdir},*data" --results $results_file --test_name $test_name --tuned_setting=$to_tuned_setting --version $nginx_version --user $to_user

}

ARGUMENT_LIST=(
	"connections"
	"tag_name"
	"threads"
	"time"
)

NO_ARGUMENTS=(
	"usage"
)

# read arguments
opts=$(getopt \
	--longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
	--longoptions "$(printf "%s," "${NO_ARGUMENTS[@]}")" \
	--name "$(basename "$0")" \
	--options "h" \
	-- "$@"
)

eval set -- "$opts"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--connections)
			connections=$2
			shift 2
		;;
		--tag_name)
			tag_name=$2
			shift 2
		;;
		--threads)
			threads=$2
			shift 2
		;;
		--time)
			run_time=$2
			shift 2
		;;
		--usage)
			usage $0
		;;
		-h)
			usage $0
		;;
		--)
			break
		;;
		*)
			echo option not found $1
			usage $0
		;;
	esac
done

if [[ $threads == "" ]]; then
	cpus=$(nproc)
	if [[ $cpus -lt 4 ]]; then
		intervals=$cpus
	else
		intervals=4
	fi
	threads=$(${TOOLS_BIN}/generate_intervals --interval $intervals --max_value $cpus)
fi

package_tool --no_packages $to_no_pkg_install --wrapper_config $curdir/../nginx.json

#
# Install nginx
#
nprocs=$(nproc)
git clone --depth 1 --branch $tag_name https://github.com/wg/wrk wrk
if [[ $? -ne 0 ]]; then
	exit_out "clone of  --branch $tag_name https://github.com/wg/wrk wrk failed" $E_GENERAL
fi
#git clone https://github.com/wg/wrk.git
pushd wrk > /dev/null
make -j $nprocs
if [[ $? -ne 0 ]]; then
	exit_out "make -j $nprocs failed to build." $E_GENERAL
fi
#
# We expect to be running as root
#
cp wrk /bin > /dev/null
popd > /dev/null
#
# Do not need the git repo anymore
#
rm -rf wrk

# Get PCP setup if we're using it
if [[ $to_use_pcp -eq 1 ]]; then
	source $TOOLS_BIN/pcp/pcp_commands.inc
	setup_pcp
	pcp_cfg=$TOOLS_BIN/pcp/default.cfg
	pcpdir=/tmp/pcp_`date "+%Y.%m.%d-%H.%M.%S"`
	start_pcp ${pcpdir}/ ${test_name} $pcp_cfg
fi

rm -rf *csv
if [[ ! -f /etc/nginx/nginx.conf_orig ]]; then
	systemctl stop nginx
	systemctl disable nginx
	mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf_orig
	sed "s/access_log  \/var\/log\/nginx\/access.log  main;/access_log off;/g" /etc/nginx/nginx.conf_orig > /etc/nginx/nginx.conf
	systemctl enable nginx
	systemctl start nginx
	if [[ $? -ne 0 ]]; then
		exit_out "Failed to start nginx" $E_GENERAL
	fi
	attempts=0
	while true
	do
		systemctl status nginx > /dev/null
		if [[ $? -eq 0 ]]; then
			break
		fi
		sleep 5
		if [[ $attempts -eq 12 ]]; then
			exit_out "nginx never entered the start state" $E_GENERAL
		fi
		let "attempts=${attempts}+1"
	done
fi

for iter in $(seq 1 1 $to_times_to_run); do
	execute_nginx $iter
done

# Shutdown PCP and clean up after ourselves
if [[ $to_use_pcp -eq 1 ]]; then
        shutdown_pcp
fi
create_summary_file
${TOOLS_BIN}/save_results --curdir $curdir --home_root $to_home_root --other_files "*_summary,run*log,test_results_report,${pcpdir},*data" --results $results_file --test_name $test_name --tuned_setting=$to_tuned_setting --version $nginx_version --user $to_user
exit $E_SUCCESS
