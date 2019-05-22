#!/bin/bash

prog=$0
cd $(dirname $0)/../

ts_begin=$(date +%s)
perl -Ilib bin/post-to-wayback-machine.pl --atom var/www/articles-links.atom &

perl -Ilib bin/gather-feeds.pl --db var/db
perl -Ilib bin/gather.pl --db var/db
perl -Ilib bin/build-daily-md.pl --db var/db -o var/www
perl -Ilib bin/build-www.pl -i var/www -o var/www
perl -Ilib bin/merge.pl --db var/db 

perl -Ilib bin/build-atom-feed.pl --db var/db -o var/www
perl -Ilib bin/atom2rss.pl var/www/articles-full.atom var/www/articles-full.rss
perl -Ilib bin/atom2rss.pl var/www/articles-links.atom var/www/articles-links.rss
perl -Ilib bin/atom2rss.pl var/www/articles-summarized.atom var/www/articles-summarized.rss

perl -Ilib bin/build-dailystats.pl --db var/db -o var/db
perl -Ilib bin/emit-hourly-stats.pl --db var/db

wait
ts_end=$(date +%s)

echo "DONE:" $(( $ts_end - $ts_begin )) 'seconds'
