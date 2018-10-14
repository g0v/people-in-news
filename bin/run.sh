#!/bin/bash

prog=$0
cd $(dirname $0)/../

ts_begin=$(date +%s)

perl -Ilib bin/gather.pl --db var/db
perl -Ilib bin/extract.pl --db var/db
perl -Ilib bin/build-daily-md.pl --db var/db -o var/people-in-news.wiki

cd var/people-in-news.wiki
git add '*.md'
git commit -m build
git pull --no-edit
git push
cd -

ts_end=$(date +%s)

echo "DONE:" $(( $ts_end - $ts_begin )) 'seconds'

sleep 600;

exec $0
