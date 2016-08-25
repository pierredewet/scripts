#!/bin/bash
shopt -s nullglob
for f in *.{mkv,mp4,m4v,avi}; do 
	newname=`echo "$f" | sed -e 's/\(S[0-9][0-9]E[0-9][0-9]\).*\.\([am][4kpv][4iv]\)/\1.\2/'` 
	mv "$f" "$newname"; 
done
