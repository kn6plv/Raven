#!/bin/sh
printf "Status: 307 Temporary Redirect\r\n"
printf "Cache-Control: no-store\r\n"
printf "Access-Control-Allow-Origin: *\r\n"
printf "Location: /apps/raven/index.html\r\n"
printf "\n"
