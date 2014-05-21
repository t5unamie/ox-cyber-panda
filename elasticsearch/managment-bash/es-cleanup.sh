#!/bin/bash
#
# Delete logstash format indices from elasticsearch maintaining only a
# specified number.
#   http://logstash.net
#   http://www.elasticsearch.org
#
#   reference:
#     http://tech.superhappykittymeow.com/?p=296
#
# Must have access to the specified elasticsearch node.
# Author - Johnathan Phan - 03-12-2013
# johnp@cc-g.co.uk

usage()
{
cat << EOF


Compares the current list of indices to a configured value and deletes any
indices surpassing that value. Sort is lexicographical; the first n of a 'sort
-r' list are kept, all others are deleted.


USAGE: ./es-cleanup.sh [OPTIONS]

OPTIONS:
  -h    Show this message
  -i    Indices to keep (default: 30)
  -e    Elasticsearch URL (default: http://localhost:9200)
  -g    Consistent index name (default: logstash)
  -o    Output actions to a specified file
  -t    Used for debuggin this switch means no data will be deleted. It will simply indicate which indices would have been deleted.
  -l    Sets logging to be on and logging to default log location

EXAMPLES:

  ./es-cleanup.sh

    Connect to http://localhost:9200 and get a list of indices matching
    'logstash'. Keep the top lexicographical 14 indices, delete any others.

  ./es-cleanup.sh -e "http://es.example.com:9200" \
  -i 28 -g my-logs -o /mnt/es/logfile.log

    Connect to http://es.example.com:9200 and get a list of indices matching
    'my-logs'. Keep the last 28 days worth of indicies, delete any others.
    Output index deletes to /var/log/es-cleanup.log by default. However -o turns logging on
    and allows you to specify the location.

   ./es-cleanup.sh -e "http://es.example.com:9200" \
  -i 28 -g my-logs -t -l

   Connect to http://es.example.com:9200 and get a list of indices matching
    'my-logs'. Keep the last 28 days worth of indicies, delete any others.
    Output index deletes to /mnt/es/logfile.log. The -l sets logging to true and will log
    things to default location /var/log/es-cleanup.log. -t turns on debugging, this
    will not delete anything and show you what index's will be left along and which ones will be deleted.

EOF
}

# Defaults
ELASTICSEARCH="http://localhost:9200"
KEEP=30
GREP="logstash"
LOG=false
LOGFILE="/var/log/es-cleanup.log"
DEBUG=false

# Validate numeric values
RE_D="^[0-9]+$"

while getopts ":i:e:g:o:htl" flag
do
  case "$flag" in
    h)
      usage
      exit 0
      ;;
    i)
      if [[ $OPTARG =~ $RE_D ]]; then
        KEEP=$OPTARG
      else
        ERROR="${ERROR}Indexes to keep must be an integer.\n"
      fi
      ;;
    e)
      ELASTICSEARCH=$OPTARG
      ;;
    g)
      GREP=$OPTARG
      ;;
    o)
      LOG=true
      LOGFILE=$OPTARG
      ;;
    t)
      DEBUG=true
      ;;
    l)
      LOG=true
      ;;
    ?)
      usage
      exit 1
      ;;
  esac
done

# If we have errors, show the errors with usage data and exit.
if [ -n "$ERROR" ]; then
  echo -e "$ERROR"
  usage
  exit 1
fi

# Get the indices from elasticsearch
INDICES_TEXT=$(curl -s "$ELASTICSEARCH/_status?pretty=true" | grep "$GREP" | grep -v \"index\" | sort -r | awk -F\" {'print $2'})

if [ -z "$INDICES_TEXT" ]; then
  echo "No indices returned containing '$GREP' from $ELASTICSEARCH."
  exit 1
fi

# If we are logging, make sure we have a logfile TODO - handle errors here
if [ -n "$LOGFILE" ] && ! [ -e "$LOGFILE" ]; then
  touch "$LOGFILE"
fi

# Delete indices
declare -a INDEX=($INDICES_TEXT)

# Set date for comparison

DDATE=$(date +%Y.%m.%d -d "$KEEP days ago")

  for index in "${INDEX[@]}";do
    # We don't want to accidentally delete everything
    if [ -n "$index" ]; then
        INDEXDATE="${index##*-}"
        echo "logging $LOG"
        echo "debugging $DEBUG"
        if [ "$LOG" = true ] ; then
                if [ ! "$INDEXDATE" \> "$DDATE" ]; then
                        if [ "$DEBUG" = true ] ; then
                                echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") "I would have deleted" $index" ", I am logging, however I am set to debug so I won't delete anything"
                                echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") "I would have deleted" $index" ", I am logging, however I am set to debug so I won't delete anything" >> "$LOGFILE"
                                else
                                # echo ""I am set to log and will delete this index" $index "Debugging set to false" "
                                curl -s -XDELETE "$ELASTICSEARCH/$index/" >> "$LOGFILE"
                        fi
                else
                        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") "I am set to log this and I would not delete this index" $index ", As this index is too new""
                        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") "I am set to log this and I would not delete this index" $index" >> "$LOGFILE"
                fi
        else
                if [ ! "$INDEXDATE" \> "$DDATE" ]; then
                        if [ "$DEBUG" = true ] ; then
                                echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") "I would have deleted" $index" ", I am setup not to log this, however I am set to debug so I won't delete anything"
                        else
                                # echo ""I am set to not to log and will delete this index" $index "Debugging set to false" "
                                curl -s -XDELETE "$ELASTICSEARCH/$index/" > /dev/null
                        fi
                else
                        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") "I am set not to log this and I would not delete this index" $index ", As this index is too new""
                fi

        fi

    fi
  done

exit 0

