#!/bin/sh
# vim: se et ts=2 sw=2 sts=2 : \
exec tclsh "$0" "$@"

#-----------------------------------------------------------------------------
# photos_import.tcl --
#
#   Helper script for importing tranformed (resized, etc...) photo albums 
#   (directories with images) into Photos.app on MacOS.
#
#-----------------------------------------------------------------------------

package require cmdline

set DEBUG 0

set C_IMGDIM_MAX  3840
set C_PREFIX      "/tmp/photos-import"

#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------

proc usage {} {
  global C_PREFIX

  set prog [cmdline::getArgv0]

  return "usage: $prog <folders...> \[options\]

Imports each folder into Photos.app as it's own album. By default, images are
reduced in size to around 1.5MB. If 'sz_max' < 0, resizing is disabled.

Also works as an OSX Finder.app Service 

options:
    -help                  Print this message
    -skip_import           Only create reduced size album, do not import to Photos.app
    -prefix                Directory to stage album before upload (Default: $C_PREFIX)
    -sz_max                Size to limit images (in pixels)
"
}

#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------

# Helper Functions --

proc perr {msg} {
  puts stderr "--ERROR-- $msg"
}

proc debug {msg} {
  global DEBUG
  if { $DEBUG } {
    puts stderr "--Debug-- $msg"
  }
}

proc getopts { args opts optlist } {

  upvar $args a
  upvar $opts o

  while { [ set rc [cmdline::getopt a $optlist opt val] ] != 0 } {
    if { $rc < 0 } {
      perr $val
      exit -1
    }
    set o($opt) $val
  }

  return 0
}

#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------

# Ensure SIPS is available
set err [catch {exec which sips} C_SIPS]
if { $err } {
  perr "'sips' image processing is not found. This script is intended\
  for use on MacOS"
  exit -1
}

#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------

# Business Functions --

# photos_import::stage_album -- 
#
#   Copy all images from an album into a temporary
#   directory, possibly applying specified 
#   transformations
#
# Arguments:
#   opts        (required) This should be more like a "this pointer" TODO
#   src_dir     (required) Specifies the source directory for the album
#   album_root  (required) Path to temporary directory to place staged album
#
# Results:
#   A successful staging will return an empty message. Upon any errors
#   a message of the error is returned. TODO: Make this programitc
proc stage_album {opts src_dir album_root} {
  upvar $opts o

  # Get list of images in the album
  set files [lsort [glob -directory $src_dir -type f * ]]

  if { [llength $files] < 1 } {
    return ""
  }

  puts "file mkdir $o(album_root)"
    
  foreach f $files {

    set nf [string map "\"$src_dir\" \"$album_root\"" $f]

    if { [is_image $f] && $o(sz_max) > 0 } {
      resize_image $f $nf $o(sz_max)
    } else {
      copy_backup_existing $f $nf
    }

  }

  return ""
}

proc resize_image {in out sz_max} {
  set rc [catch "exec sips -Z $sz_max $in --out $out >/dev/null" ]
}

#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------

# START HERE --

proc &main {argc argv} {

  global C_PREFIX
  global C_IMGDIM_MAX

  # Save this off into var to be modified by getopts
  set args $argv

  array set opts [ list      \
    prefix ${C_PREFIX}       \
    sz_max ${C_IMGDIM_MAX}   \
    skip_import 0            \
    help 0                   \
  ]
  
  set optlist [ list  \
    prefix.arg        \
    sz_max.arg        \
    skip_import       \
    help              \
  ]

  getopts args opts $optlist

  if { $opts(help) || [llength $args] < 1 } {
    puts [usage]
    exit 0
  }
  
  debug "prefix: $opts(prefix)"
  debug "sz_max: $opts(sz_max)"
  debug "skip_import: $opts(skip_import)"
  debug "folders: $args"

  # Stage the possibly resized images
  set staged_dirs ""

  foreach src_dir $args {
    set album_name [file tail $src_dir]
    set album_root [file join $opts(prefix) $album_name]

    set err [stage_album opts $src_dir $album_root]

    if { $err ne "" } {
      perr $err
    }

    lappend staged_dirs $album_root
  }

  # Import each album from its staged directory
  if { ! $opts(skip_import) } {
    foreach staged_dir $staged_dirs {
      debug $staged_dir
    }
  }

}

#-----------------------------------------------------------------------------
exit [&main $::argc $::argv]

# == Sample AppleScript
# osascript <<'END'
# try
#     set userHome to (short user name of (system info))
#     set SelectFolder to choose folder with prompt "choose folder" default location userHome
# on error number -128
#     set SelectFolder to ""
# end try

# if SelectFolder is "" then
#     display alert "user did not select a folder"
# else
#     display alert "User selection is " & SelectFolder
# end if
# END
