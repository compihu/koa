#!/bin/bash
set -e

function parse_userdir
{
  while [ $# != 0 ] ; do
    case $1 in
      -u | --user )
        USERDIR="$2"
        shift
        ;;
      -a  | --aurhelper | \
      -bs | --bootsize | \
      -c  | --cache | \
      -d  | --builddir | \
      -f  | --from | \
      -h  | --hostname | \
      -i  | --image | \
      -is | --imgsize | \
      -v  | --subvolume | \
      -wd | --workdir | \
      -ws | --wifi_ssid | \
      -wp | --wifi-passwd )
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
      -4 | --ext4 )
        USE_EXT4=1
        ;;
      -a | --aurhelper )
        IMG="$2"
        shift
        ;;
      -bs | --bootsize )
        BOOTSIZE="$2"
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
      -h | --hostname )
        TARGET_HOSTNAME="$2"
        shift
        ;;
      -i | --image )
        IMG="$2"
        shift
        ;;
      -is | --imgsize )
        IMGSIZE="$2"
        shift
        ;;
      -u | --user )
        # already set in parse_userdir
        shift
        ;;
      -v | --subvolume )
        SUBVOL="$2"
        shift
        ;;
      -wd | --workdir )
        WD="$2"
        shift
        ;;
      -ws | --wifi_ssid )
        WIFI_SSID="$2"
        shift
        ;;
      -wp | --wifi-passwd )
        WIFI_PASSWD="$2"
        shift
        ;;
      -f | --from )
        SNAPSHOT="$2"
        shift
        ;;
      * )
        echo "Unknown option $1."
        return 1
        ;;
    esac
    shift
  done

  if [ "${SNAPSHOT}" ]; then
    CHECKPOINT=${SNAPSHOTS[${SNAPSHOT}]}
    if [ -z "${CHECKPOINT}" ]; then
      echo "Unkonwn snapshot to start from"
      return 1
    fi
  else
    CHECKPOINT=0
  fi

  IMG="${IMG:-$SCRIPTDIR/koa.img}"
  WD="${WD:-$SCRIPTDIR/target}"
  CACHE="${CACHE:-$SCRIPTDIR/cache}"
  BUILDDIR="${BUILDDIR:-$SCRIPTDIR/build}"
  IMGSIZE="${IMGSIZE:-4GB}"
  BOOTSIZE="${BOOTSIZE:-64MiB}"
  TARGET_HOSTNAME="${TARGET_HOSTNAME:-koa}"
  SUBVOL="${SUBVOL:-@koa_root}"
  AURHELPER="${AURHELPER:-yay}"
  SNAPSHOTDIR="${SNAPSHOTDIR:-$SCRIPTDIR/snapshots}"
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
  echo "Start from:  ${SNAPSHOT}"
  echo "-------------------------------------------------"
  echo
}
