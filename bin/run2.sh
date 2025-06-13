#!/bin/bash

PEOPLE_IN_NEWS_DB_DIR=${PEOPLE_IN_NEWS_DB_DIR:-var/db}
PEOPLE_IN_NEWS_WWW_DIR=${PEOPLE_IN_NEWS_WWW_DIR:-var/www}

export TZ=Asia/Taipei

prog=$0
cd $(dirname $0)/../

ts_begin=$(date +%s)

perl -Ilib bin/gather-feeds.pl --db $PEOPLE_IN_NEWS_DB_DIR
perl -Ilib bin/gather.pl --db $PEOPLE_IN_NEWS_DB_DIR
perl -Ilib bin/build-atom-feed.pl --db $PEOPLE_IN_NEWS_DB_DIR -o $PEOPLE_IN_NEWS_WWW_DIR
perl -Ilib bin/build-daily-md.pl --db $PEOPLE_IN_NEWS_DB_DIR -o $PEOPLE_IN_NEWS_WWW_DIR
perl -Ilib bin/build-www.pl -i $PEOPLE_IN_NEWS_WWW_DIR -o $PEOPLE_IN_NEWS_WWW_DIR
perl -Ilib bin/merge.pl --db $PEOPLE_IN_NEWS_DB_DIR

ts_end=$(date +%s)

echo "DONE:" $(( $ts_end - $ts_begin )) 'seconds'

