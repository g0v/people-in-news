#!/bin/bash

export TZ=Asia/Taipei

prog=$0
cd $(dirname $0)/../

ts_begin=$(date +%s)

perl -Ilib bin/gather-feeds.pl --db var/db
perl -Ilib bin/gather.pl --db var/db
perl -Ilib bin/build-atom-feed.pl --db var/db -o var/www
perl -Ilib bin/build-daily-md.pl --db var/db -o var/www
perl -Ilib bin/build-www.pl -i var/www -o var/www
perl -Ilib bin/merge.pl --db var/db 

ts_end=$(date +%s)

echo "DONE:" $(( $ts_end - $ts_begin )) 'seconds'

