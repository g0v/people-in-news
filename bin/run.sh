#!/bin/bash

prog=$0
cd $(dirname $0)/../

ts_begin=$(date +%s)

export MOJO_CONNECT_TIMEOUT=15
perl bin/gather.pl -o var/people-in-news
perl bin/build-md.pl -i var/people-in-news -o var/people-in-news.wiki

cd var/people-in-news.wiki
git add '*.md'
git commit -m build
git pull --no-edit
git push
cd -

ts_end=$(date +%s)

echo "DONE:" $(( $ts_end - $ts_begin )) 'seconds'
t=$(( 3601 - $ts_end + $ts_begin ))

if [[ $t -gt 0 ]]; then
   sleep $t
fi

exec $0
