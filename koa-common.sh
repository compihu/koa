#!/bin/bash
set -ex

function parse_params
{
  IMG="${SCRIPTDIR}/koa.img"
  WD="${SCRIPTDIR}/koa"
  CACHE="${SCRIPTDIR}/cache"
  BUILDDIR="${SCRIPTDIR}/build"
  USERDIR="${SCRIPTDIR}/user"
  IMGSIZE="1000MB"
  BOOTSIZE="64MiB"
  USE_BTRFS=1
  SUBVOL="@koa_root"

  while [ $# != 0 ] ; do
    case $1 in
      -i | --image )
        IMG="$2"
        shift
        ;;
      -w | --workdir )
        WD="$2"
        shift
        ;;
      -c | --cache )
        CACHE="$2"
        shift
        ;;
      -d | --builddir )
        BUILDDIR="$2"
        shift
        ;;
      -s | --imgsize )
        IMGSIZE="$2"
        shift
        ;;
      -b | --bootsize )
        BOOTSIZE="$2"
        shift
        ;;
      -v | --subvolume )
        SUBVOL="$2"
        shift
        ;;
      -u | --user )
        USERDIR="$2"
        shift
        ;;
      -4 | --ext4 )
        unset USE_BTRFS
        ;;
      * )
        echo "Unknown option $1."
        return 1
        ;;
    esac
    shift
  done
}


show_environment()
{
  echo "-------------------------------------------------"
  echo "Image:       ${IMG}"
  echo "Workdir:     ${WD}"
  echo "Cache:       ${CACHE}"
  echo "Builddir:    ${BUILDDIR}"
  echo "Userdir:     ${USERDIR}"
  echo "Wifi SSID:   ${WIFI_SSID}"
  echo "Wifi passwd: ${WIFI_PASSWD}"
  echo "Trusted net: ${TRUSTED_NET}"
  echo "-------------------------------------------------"
  echo
}

