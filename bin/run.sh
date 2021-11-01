#!/bin/bash

prog=$0
cd $(dirname $0)/../

export TZ=Asia/Taipei

ts_begin=$(date +%s)

perl -Ilib bin/gather-feeds.pl --db var/db
perl -Ilib bin/gather.pl --db var/db --time-limit=3000
perl -Ilib bin/merge.pl --db var/db
perl -Ilib bin/deduplicate.pl --yes var/db/*.jsonl
perl -Ilib bin/build-atom-feed.pl --db var/db -o var/www
perl -Ilib bin/emit-hourly-stats.pl --db var/db

for f in $(ls -1 var/db/*.jsonl | grep -v $(date +%Y%m%d))
do
    pigz -11 $f
done

for yyyy in $(($(date +%Y)-1)) $(date +%Y)
do
    mkdir -p var/db/$yyyy/
    mv var/db/*$yyyy*.jsonl.gz var/db/$yyyy/
done

ts_end=$(date +%s)

echo "DONE:" $(( $ts_end - $ts_begin )) 'seconds'
