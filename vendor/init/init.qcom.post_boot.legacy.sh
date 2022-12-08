#! /vendor/bin/sh

# Copyright (c) 2012-2013, 2016-2020, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Changes from Qualcomm Innovation Center are provided under the following license:
# Copyright (c) 2022 Qualcomm Innovation Center, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#

function configure_zram_parameters() {
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    low_ram=`getprop ro.config.low_ram`

    # Zram disk - 75% for Go devices.
    # For 512MB Go device, size = 384MB, set same for Non-Go.
    # For 1GB Go device, size = 768MB, set same for Non-Go.
    # For 2GB Go device, size = 1536MB, set same for Non-Go.
    # For >2GB Non-Go devices, size = 50% of RAM size. Limit the size to 4GB.
    # And enable lz4 zram compression for Go targets.

    let RamSizeGB="( $MemTotal / 1048576 ) + 1"
    diskSizeUnit=M
    if [ $RamSizeGB -le 2 ]; then
        let zRamSizeMB="( $RamSizeGB * 1024 ) * 3 / 4"
    else
        let zRamSizeMB="( $RamSizeGB * 1024 ) / 2"
    fi

    # use MB avoid 32 bit overflow
    if [ $zRamSizeMB -gt 4096 ]; then
        let zRamSizeMB=4096
    fi

    if [ "$low_ram" == "true" ]; then
        echo lz4 > /sys/block/zram0/comp_algorithm
    fi

    if [ -f /sys/block/zram0/disksize ]; then
        if [ -f /sys/block/zram0/use_dedup ]; then
            echo 1 > /sys/block/zram0/use_dedup
        fi
        echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize

        # ZRAM may use more memory than it saves if SLAB_STORE_USER
        # debug option is enabled.
        if [ -e /sys/kernel/slab/zs_handle ]; then
            echo 0 > /sys/kernel/slab/zs_handle/store_user
        fi
        if [ -e /sys/kernel/slab/zspage ]; then
            echo 0 > /sys/kernel/slab/zspage/store_user
        fi

        mkswap /dev/block/zram0
        swapon /dev/block/zram0 -p 32758
    fi
}

function configure_read_ahead_kb_values() {
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    dmpts=$(ls /sys/block/*/queue/read_ahead_kb | grep -e dm -e mmc)

    # Set 128 for <= 3GB &
    # set 512 for >= 4GB targets.
    if [ $MemTotal -le 3145728 ]; then
        echo 128 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 128 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        for dm in $dmpts; do
            echo 128 > $dm
        done
    else
        echo 512 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 512 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        for dm in $dmpts; do
            echo 512 > $dm
        done
    fi
}

function configure_memory_parameters() {

# Enable ZRAM
configure_zram_parameters
configure_read_ahead_kb_values
echo 0 > /proc/sys/vm/page-cluster
echo 100 > /proc/sys/vm/swappiness

}

function start_hbtp()
{
        # Start the Host based Touch processing but not in the power off mode.
        bootmode=`getprop ro.bootmode`
        if [ "charger" != $bootmode ]; then
                start vendor.hbtp
        fi
}

case "$target" in
    "msmnile")
	# cpuset parameters
		# Core control parameters for gold
		echo 2 > /sys/devices/system/cpu/cpu4/core_ctl/min_cpus
		echo 60 > /sys/devices/system/cpu/cpu4/core_ctl/busy_up_thres
		echo 30 > /sys/devices/system/cpu/cpu4/core_ctl/busy_down_thres
		echo 100 > /sys/devices/system/cpu/cpu4/core_ctl/offline_delay_ms
		echo 3 > /sys/devices/system/cpu/cpu4/core_ctl/task_thres

		# Core control parameters for gold+
		echo 0 > /sys/devices/system/cpu/cpu7/core_ctl/min_cpus
		echo 60 > /sys/devices/system/cpu/cpu7/core_ctl/busy_up_thres
		echo 30 > /sys/devices/system/cpu/cpu7/core_ctl/busy_down_thres
		echo 100 > /sys/devices/system/cpu/cpu7/core_ctl/offline_delay_ms
		echo 1 > /sys/devices/system/cpu/cpu7/core_ctl/task_thres
		# Controls how many more tasks should be eligible to run on gold CPUs
		# w.r.t number of gold CPUs available to trigger assist (max number of
		# tasks eligible to run on previous cluster minus number of CPUs in
		# the previous cluster).
		#
		# Setting to 1 by default which means there should be at least
		# 4 tasks eligible to run on gold cluster (tasks running on gold cores
		# plus misfit tasks on silver cores) to trigger assitance from gold+.
		echo 1 > /sys/devices/system/cpu/cpu7/core_ctl/nr_prev_assist_thresh

		# Disable Core control on silver
		echo 0 > /sys/devices/system/cpu/cpu0/core_ctl/enable

		# Setting b.L scheduler parameters
		echo 95 95 > /proc/sys/kernel/sched_upmigrate
		echo 85 85 > /proc/sys/kernel/sched_downmigrate
		echo 100 > /proc/sys/kernel/sched_group_upmigrate
		echo 10 > /proc/sys/kernel/sched_group_downmigrate
		echo 1 > /proc/sys/kernel/sched_walt_rotate_big_tasks

		echo 0-3 > /dev/cpuset/background/cpus
		echo 0-3 > /dev/cpuset/system-background/cpus


		# Turn off scheduler boost at the end
		echo 0 > /proc/sys/kernel/sched_boost

		# configure governor settings for silver cluster
		echo "schedutil" > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
		echo 0 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/up_rate_limit_us
        	echo 0 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/down_rate_limit_us
		echo 1209600 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/hispeed_freq
		echo 576000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
		echo 1 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/pl

		# configure governor settings for gold cluster
		echo "schedutil" > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor
		echo 0 > /sys/devices/system/cpu/cpufreq/policy4/schedutil/up_rate_limit_us
	        echo 0 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/down_rate_limit_us
		echo 1612800 > /sys/devices/system/cpu/cpufreq/policy4/schedutil/hispeed_freq
		echo 1 > /sys/devices/system/cpu/cpufreq/policy4/schedutil/pl

		# configure governor settings for gold+ cluster
		echo "schedutil" > /sys/devices/system/cpu/cpufreq/policy7/scaling_governor
		echo 0 > /sys/devices/system/cpu/cpufreq/policy7/schedutil/up_rate_limit_us
	        echo 0 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/down_rate_limit_us
		echo 1612800 > /sys/devices/system/cpu/cpufreq/policy7/schedutil/hispeed_freq
		echo 1 > /sys/devices/system/cpu/cpufreq/policy7/schedutil/pl

		# configure input boost settings
		echo "0:1324800" > /sys/module/cpu_boost/parameters/input_boost_freq
		echo 120 > /sys/module/cpu_boost/parameters/input_boost_ms

		# Disable wsf, beacause we are using efk.
		# wsf Range : 1..1000 So set to bare minimum value 1.
	        echo 1 > /proc/sys/vm/watermark_scale_factor

        	# Enable oom_reaper
		if [ -f /sys/module/lowmemorykiller/parameters/oom_reaper ]; then
			echo 1 > /sys/module/lowmemorykiller/parameters/oom_reaper
		else
			echo 1 > /proc/sys/vm/reap_mem_on_sigkill
		fi

		# Enable bus-dcvs
		for device in /sys/devices/platform/soc
		do
		    for cpubw in $device/*cpu-cpu-llcc-bw/devfreq/*cpu-cpu-llcc-bw
		    do
			cat $cpubw/available_frequencies | cut -d " " -f 1 > $cpubw/min_freq
			echo "2288 4577 7110 9155 12298 14236 15258" > $cpubw/bw_hwmon/mbps_zones
			echo 4 > $cpubw/bw_hwmon/sample_ms
			echo 50 > $cpubw/bw_hwmon/io_percent
			echo 20 > $cpubw/bw_hwmon/hist_memory
			echo 10 > $cpubw/bw_hwmon/hyst_length
			echo 30 > $cpubw/bw_hwmon/down_thres
			echo 0 > $cpubw/bw_hwmon/guard_band_mbps
			echo 250 > $cpubw/bw_hwmon/up_scale
			echo 1600 > $cpubw/bw_hwmon/idle_mbps
			echo 14236 > $cpubw/max_freq
	                echo 40 > $cpubw/polling_interval
		    done

		    for llccbw in $device/*cpu-llcc-ddr-bw/devfreq/*cpu-llcc-ddr-bw
		    do
			cat $llccbw/available_frequencies | cut -d " " -f 1 > $llccbw/min_freq
			echo "1720 2929 3879 5931 6881 7980" > $llccbw/bw_hwmon/mbps_zones
			echo 4 > $llccbw/bw_hwmon/sample_ms
			echo 80 > $llccbw/bw_hwmon/io_percent
			echo 20 > $llccbw/bw_hwmon/hist_memory
			echo 10 > $llccbw/bw_hwmon/hyst_length
			echo 30 > $llccbw/bw_hwmon/down_thres
			echo 0 > $llccbw/bw_hwmon/guard_band_mbps
			echo 250 > $llccbw/bw_hwmon/up_scale
			echo 1600 > $llccbw/bw_hwmon/idle_mbps
			echo 6881 > $llccbw/max_freq
	                echo 40 > $llccbw/polling_interval
		    done

		    for npubw in $device/*npu-npu-ddr-bw/devfreq/*npu-npu-ddr-bw
		    do
			echo 1 > /sys/devices/virtual/npu/msm_npu/pwr
			cat $npubw/available_frequencies | cut -d " " -f 1 > $npubw/min_freq
			echo "1720 2929 3879 5931 6881 7980" > $npubw/bw_hwmon/mbps_zones
			echo 4 > $npubw/bw_hwmon/sample_ms
			echo 80 > $npubw/bw_hwmon/io_percent
			echo 20 > $npubw/bw_hwmon/hist_memory
			echo 6  > $npubw/bw_hwmon/hyst_length
			echo 30 > $npubw/bw_hwmon/down_thres
			echo 0 > $npubw/bw_hwmon/guard_band_mbps
			echo 250 > $npubw/bw_hwmon/up_scale
			echo 0 > $npubw/bw_hwmon/idle_mbps
	                echo 40 > $npubw/polling_interval
			echo 0 > /sys/devices/virtual/npu/msm_npu/pwr
		    done

		    #Enable mem_latency governor for L3, LLCC, and DDR scaling
		    for memlat in $device/*cpu*-lat/devfreq/*cpu*-lat
		    do
			cat $memlat/available_frequencies | cut -d " " -f 1 > $memlat/min_freq
		    done

		    #Enable compute governor for gold latfloor
		    for latfloor in $device/*cpu-ddr-latfloor*/devfreq/*cpu-ddr-latfloor*
		    do
			cat $latfloor/available_frequencies | cut -d " " -f 1 > $latfloor/min_freq
		    done

		    #Gold L3 ratio ceil
		    for l3silver in $device/*cpu0-cpu-l3-lat/devfreq/*cpu0-cpu-l3-lat
		    do
			cat $l3silver/available_frequencies | cut -d " " -f 1 > $l3silver/min_freq
		    done

		    #Gold L3 ratio ceil
		    for l3gold in $device/*cpu4-cpu-l3-lat/devfreq/*cpu4-cpu-l3-lat
		    do
			cat $l3gold/available_frequencies | cut -d " " -f 1 > $l3gold/min_freq
		    done

		    #Prime L3 ratio ceil
		    for l3prime in $device/*cpu7-cpu-l3-lat/devfreq/*cpu7-cpu-l3-lat
		    do
			cat $l3prime/available_frequencies | cut -d " " -f 1 > $l3prime/min_freq
		    done

		done

	# memlat specific settings are moved to seperate file under
	# device/target specific folder
	setprop vendor.dcvs.prop 1

	if [ -f /sys/devices/soc0/hw_platform ]; then
		hw_platform=`cat /sys/devices/soc0/hw_platform`
	else
        	hw_platform=`cat /sys/devices/system/soc/soc0/hw_platform`
	fi

	if [ -f /sys/devices/soc0/platform_subtype_id ]; then
	   	platform_subtype_id=`cat /sys/devices/soc0/platform_subtype_id`
   	fi

	case "$hw_platform" in
		"MTP" | "Surf" | "RCM" )
	            # Start Host based Touch processing
		case "$platform_subtype_id" in
			"0" | "1" | "2" | "3" | "4")
			start_hbtp
			;;
		esac
		;;
	        "HDK" )
		if [ -d /sys/kernel/hbtpsensor ] ; then
                	start_hbtp
		fi
		;;
	esac

	    echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled
	    configure_memory_parameters
    ;;
esac
