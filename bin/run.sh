#!/bin/bash

PEOPLE_IN_NEWS_DB_DIR=${PEOPLE_IN_NEWS_DB_DIR:-var/db}
PEOPLE_IN_NEWS_WWW_DIR=${PEOPLE_IN_NEWS_WWW_DIR:-var/www}
PEOPLE_IN_NEWS_GATHER_TIME_LIMIT=${PEOPLE_IN_NEWS_GATHER_TIME_LIMIT:-3000}

prog=$0
cd $(dirname $0)/../

export TZ=Asia/Taipei

ts_begin=$(date +%s)

perl -Ilib bin/gather-feeds.pl --db $PEOPLE_IN_NEWS_DB_DIR
perl -Ilib bin/gather.pl --db $PEOPLE_IN_NEWS_DB_DIR --time-limit=$PEOPLE_IN_NEWS_GATHER_TIME_LIMIT
perl -Ilib bin/merge.pl --db $PEOPLE_IN_NEWS_DB_DIR
perl -Ilib bin/deduplicate.pl --yes --db $PEOPLE_IN_NEWS_DB_DIR $PEOPLE_IN_NEWS_DB_DIR/*.jsonl
perl -Ilib bin/build-atom-feed.pl --db $PEOPLE_IN_NEWS_DB_DIR -o $PEOPLE_IN_NEWS_WWW_DIR
perl -Ilib bin/emit-hourly-stats.pl --db $PEOPLE_IN_NEWS_DB_DIR

for f in $(ls -1 $PEOPLE_IN_NEWS_DB_DIR/*.jsonl | grep -v $(date +%Y%m%d))
do
    pigz -11 $f
done

for yyyy in $(($(date +%Y)-1)) $(date +%Y)
do
    mkdir -p $PEOPLE_IN_NEWS_DB_DIR/$yyyy/
    mv $PEOPLE_IN_NEWS_DB_DIR/*$yyyy*.jsonl.gz $PEOPLE_IN_NEWS_DB_DIR/$yyyy/
done

ts_end=$(date +%s)

echo "DONE:" $(( $ts_end - $ts_begin )) 'seconds'
