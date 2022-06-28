#!/bin/bash
set -ex


function parse_userdir
{
  while [ $# != 0 ] ; do
    case $1 in
      -u | --user )
        USERDIR="$2"
        shift
        ;;
      -i | --image | \
      -w | --workdir | \
      -c | --cache | \
      -d | --builddir | \
      -s | --imgsize | \
      -b | --bootsize | \
      -v | --subvolume | \
      -h | --hostname | \
      -i | --wifi_ssid | \
      -o | --wifi-passwd )
        shift
        ;;
      -4 | --ext4 )
        ;;
      * )
        echo "Unknown option $1."
        return 1
        ;;
    esac
    shift
  done

  USERDIR="${USERDIR:-$SCRIPTDIR/user}"
}


function parse_params
{
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
        # already set in parse_userdir
        shift
        ;;
      -4 | --ext4 )
        USE_EXT4=1
        ;;
      -h | --hostname )
        TARGET_HOSTNAME="$2"
        shift
        ;;
      -i | --wifi_ssid )
        WIFI_SSID="$2"
        shift
        ;;
      -o | --wifi-passwd )
        WIFI_PASSWD="$2"
        shift
        ;;
      * )
        echo "Unknown option $1."
        return 1
        ;;
    esac
    shift
  done

  IMG="${IMG:-$SCRIPTDIR/koa.img}"
  WD="${WD:-$SCRIPTDIR/koa}"
  CACHE="${CACHE:-$SCRIPTDIR/cache}"
  BUILDDIR="${BUILDDIR:-$SCRIPTDIR/build}"
  IMGSIZE="${IMGSIZE:-2500MB}"
  BOOTSIZE="${BOOTSIZE:-64MiB}"
  TARGET_HOSTNAME="${TARGET_HOSTNAME:-koa}"
  SUBVOL="${SUBVOL:-@koa_root}"
}


show_environment()
{
  echo "-------------------------------------------------"
  echo "Image:       ${IMG}"
  echo "Image size:  ${IMGSIZE}"
  echo "Workdir:     ${WD}"
  echo "Cache:       ${CACHE}"
  echo "Builddir:    ${BUILDDIR}"
  echo "Userdir:     ${USERDIR}"
  echo "Wifi SSID:   ${WIFI_SSID}"
  echo "Wifi passwd: ${WIFI_PASSWD}"
  echo "Hostname:    ${TARGET_HOSTNAME}"
  echo "Trusted net: ${TRUSTED_NET}"
  echo "-------------------------------------------------"
  echo
}

