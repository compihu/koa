#!/bin/bash
set -ex

function parse_params
{
  IMG="koa.img"
  WD="koa"
  CACHE="cache"
  BUILD="build"
  IMGSIZE="2500M"
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
      -b | --build )
        BUILD="$2"
        shift
        ;;
      -s | --imgsize )
        IMGSIZE="$2"
        shift
        ;;
      -v | --subvolume )
        SUBVOL="$2"
        shift
        ;;
      * )
        echo "Unknown option $1."
        return 1
        ;;
    esac
    shift
  done
}
