gearhub_check_image() {
	local diskdev part2 p2_line p2_size dest_sectors

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}
	export_partdevice part2 2 || {
		echo "Unable to determine partition 2 device"
		return 1
	}

	get_image "$@" | dd of=/tmp/image.bs count=1 bs=512b 2>/dev/null
	get_partitions /tmp/image.bs image
	p2_line="$(awk '$1 == 2 {print}' /tmp/partmap.image)"
	p2_size="$(awk '$1 == 2 {print $3}' /tmp/partmap.image)"
	rm -f /tmp/image.bs /tmp/partmap.image

	[ -n "$p2_line" ] && [ -n "$p2_size" ] || {
		echo "Invalid image: missing partition 2"
		return 1
	}

	if [ -r "/sys/class/block/$part2/size" ]; then
		dest_sectors="$(cat "/sys/class/block/$part2/size")"
		if [ "$p2_size" -gt "$dest_sectors" ]; then
			echo "Image partition 2 ($p2_size sectors) exceeds /dev/$part2 ($dest_sectors sectors)"
			return 1
		fi
	fi

	return 0
}

gearhub_do_upgrade() {
	local diskdev part1 part2
	local p1_start p1_size p2_start p2_size

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		exit 1
	}
	export_partdevice part1 1 || { echo "Missing p1"; exit 1; }
	export_partdevice part2 2 || { echo "Missing p2"; exit 1; }

	sync

	get_image "$@" | dd of=/tmp/image.bs count=1 bs=512b 2>/dev/null || exit 1
	get_partitions /tmp/image.bs image || exit 1
	rm -f /tmp/image.bs

	p1_start="$(awk '$1 == 1 {print $2}' /tmp/partmap.image)"
	p1_size="$(awk '$1 == 1 {print $3}' /tmp/partmap.image)"
	p2_start="$(awk '$1 == 2 {print $2}' /tmp/partmap.image)"
	p2_size="$(awk '$1 == 2 {print $3}' /tmp/partmap.image)"
	rm -f /tmp/partmap.image

	[ -n "$p1_start" ] && [ -n "$p1_size" ] && [ -n "$p2_start" ] && [ -n "$p2_size" ] || {
		echo "Invalid partition map in image"
		exit 1
	}

	# Preserve raw eMMC sectors 0..2047 (factory SPL/U-Boot/env) and p1:/uboot24.bin + /boot.scr
	get_image "$@" | dd of=/tmp/img-p1.vfat ibs=512 obs=1M skip="$p1_start" count="$p1_size" 2>/dev/null || {
		rm -f /tmp/img-p1.vfat
		exit 1
	}
	mkdir -p /tmp/img-p1 /tmp/emmc-p1
	mount -t vfat -o ro,loop /tmp/img-p1.vfat /tmp/img-p1 || {
		rm -f /tmp/img-p1.vfat
		exit 1
	}
	mount -t vfat -o rw,noatime "/dev/$part1" /tmp/emmc-p1 || {
		umount /tmp/img-p1
		rm -f /tmp/img-p1.vfat
		exit 1
	}

	if [ -f /tmp/img-p1/uImage ]; then
		cp -af /tmp/img-p1/uImage /tmp/emmc-p1/uImage || {
			umount /tmp/emmc-p1
			umount /tmp/img-p1
			rm -f /tmp/img-p1.vfat
			exit 1
		}
		if [ -d /tmp/emmc-p1/boot ]; then
			cp -af /tmp/img-p1/uImage /tmp/emmc-p1/boot/uImage || {
				umount /tmp/emmc-p1
				umount /tmp/img-p1
				rm -f /tmp/img-p1.vfat
				exit 1
			}
		fi
	fi

	sync
	umount /tmp/emmc-p1
	umount /tmp/img-p1
	rm -f /tmp/img-p1.vfat

	get_image "$@" | dd of="/dev/$part2" ibs=512 obs=1M skip="$p2_start" count="$p2_size" conv=fsync || exit 1
	sync
}

platform_check_image() {
	case "$(board_name)" in
	focalcrest,gearhub)
		gearhub_check_image "$1"
		;;
	*)
		legacy_sdcard_check_image "$1"
		;;
	esac
}

platform_copy_config() {
	local partdev

	if export_partdevice partdev 1; then
		mount -t vfat -o rw,noatime "/dev/$partdev" /mnt
		cp -af "$UPGRADE_BACKUP" "/mnt/$BACKUP_FILE"
		umount /mnt
	fi
}

platform_do_upgrade() {
	case "$(board_name)" in
	focalcrest,gearhub)
		gearhub_do_upgrade "$1"
		;;
	*)
		legacy_sdcard_do_upgrade "$1"
		;;
	esac
}
