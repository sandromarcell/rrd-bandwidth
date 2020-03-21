#!/bin/bash --norc
#
# Copyright 2016 Sandro Marcell <smarcell@mail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
PATH='/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin'
export LC_ALL=POSIX

# Start of GLOBAL VARIABLES
#
# Directory where rrdtool databases will be stored
RRD_DB='/var/db/rrd/rrd-bandwidth'

# Directory on the web server where the generated html/png files will be stored
HTML_DIR='/srv/http/lighttpd/htdocs/rrd-bandwidth'

# Generate charts for the following periods
PERIODS='day week month year'

# Resolution time in seconds of RRD bases (default 5 minutes)
# Note: change this value only if you really know what you are doing!
INTERVAL=$((60 * 5))

# Network interfaces to be monitored
# This array must be defined as follows:
# <interface1> <description> <interface2> <description> <interface3> <description> ...
# Eg: assuming your server has three network interfaces, where
# enp1s0 = Link to the Internet
# enp2s0 = LAN link
# enp3s0 = Link to the DMZ
# so do it:
INTERFACES=('enp1s0' 'WAN interface' 'enp2s0' 'LAN interface' 'enp3s0' 'DMZ interface')
#
# End of GLOBAL VARIABLES

# Creating work directories if they do not exist
[ ! -d "$RRD_DB" ] && { mkdir -p "$RRD_DB" || exit 1; }
[ ! -d "$HTML_DIR" ] && { mkdir -p "$HTML_DIR" || exit 1; }

# Function responsible for data collection and graph generation
generateGraphs() {
        declare -a args=("${INTERFACES[@]}")
        declare iface=''
        declare desc=''
        declare rx_bytes=0
        declare tx_bytes=0

        while [ ${#args[@]} -ne 0 ]; do
                iface="${args[0]}"
                desc="${args[1]}"
                args=("${args[@]:2}")

                # Collecting the values received/sent by the interface
                rx_bytes=$(</sys/class/net/$iface/statistics/rx_bytes)
                tx_bytes=$(</sys/class/net/$iface/statistics/tx_bytes)

                # If the rrd bases do not exist, they will be created and each will have the same name as the monitored interface
                if [ ! -e "${RRD_DB}/${iface}.rrd" ]; then
                        # Resolution = Number of seconds in the period / (Resolution interval * Resolution multiplication factor)
                        v1hr=$((604800 / (INTERVAL * 12))) # Value of 1 week (1h resolution)
                        v6hrs=$((2629800 / (INTERVAL * 72))) # Value of 1 month (6h resolution)
                        v24hrs=$((31557600 / (INTERVAL * 288))) # Value of 1 year (24h resolution)

                        echo "Creating rrd base: ${RRD_DB}/${iface}.rrd"
                        rrdtool create ${RRD_DB}/${iface}.rrd --start $(date '+%s') --step $INTERVAL \
                                DS:in:DERIVE:$((INTERVAL * 2)):0:U \
                                DS:out:DERIVE:$((INTERVAL * 2)):0:U \
                                RRA:MIN:0.5:1:288 \
                                RRA:MIN:0.5:12:$v1hr \
                                RRA:MIN:0.5:72:$v6hrs \
                                RRA:MIN:0.5:288:$v24hrs \
                                RRA:AVERAGE:0.5:1:288 \
                                RRA:AVERAGE:0.5:12:$v1hr \
                                RRA:AVERAGE:0.5:72:$v6hrs \
                                RRA:AVERAGE:0.5:288:$v24hrs \
                                RRA:MAX:0.5:1:288 \
                                RRA:MAX:0.5:12:$v1hr \
                                RRA:MAX:0.5:72:$v6hrs \
                                RRA:MAX:0.5:288:$v24hrs
                        [ $? -gt 0 ] && return 1
                fi

                # If the bases already exist, update them...
                echo "Updating base: ${RRD_DB}/${iface}.rrd"
                rrdtool update ${RRD_DB}/${iface}.rrd --template in:out N:${rx_bytes}:$tx_bytes
                [ $? -gt 0 ] && return 1

                # and create the charts
                for i in $PERIODS; do
                        case $i in
                                        'day') inf='Daily graph (5 min average)'; p='1day'  ;;
                                        'week') inf='Weekly graph (1 hr average)'; p='1week' ;;
                                        'month') inf='Monthly graph (6 hrs average)'; p='1month' ;;
                                        'year') inf='Annual graph (24 hrs average)'; p='1year'
                        esac

                        rrdtool graph ${HTML_DIR}/${iface}_${i}.png --start end-$p --end now --step $INTERVAL --font 'TITLE:0:Bold' --title "$desc / $inf" \
                                --lazy --watermark "$(date '+%^c')" --vertical-label 'Bits per second' --slope-mode --interlaced --alt-y-grid --alt-autoscale \
                                --rigid --lower-limit 0 --base 1000 --imgformat PNG --height 124 --width 550  \
                                --color 'BACK#FFFFFF' --color 'SHADEA#FFFFFF' --color 'SHADEB#FFFFFF' \
                                --color 'MGRID#AAAAAA' --color 'GRID#CCCCCC' --color 'ARROW#333333' \
                                --color 'FONT#333333' --color 'AXIS#333333' --color 'FRAME#333333' \
                                DEF:rx_bytes=${RRD_DB}/${iface}.rrd:in:AVERAGE \
                                DEF:tx_bytes=${RRD_DB}/${iface}.rrd:out:AVERAGE \
                                CDEF:upload=tx_bytes,8,* \
                                CDEF:download=rx_bytes,8,* \
                                VDEF:min_upload=upload,MINIMUM \
                                VDEF:avg_upload=upload,AVERAGE \
                                VDEF:max_upload=upload,MAXIMUM \
                                VDEF:last_upload=upload,LAST \
                                VDEF:min_download=download,MINIMUM \
                                VDEF:avg_download=download,AVERAGE \
                                VDEF:max_download=download,MAXIMUM \
                                VDEF:last_download=download,LAST \
                                "COMMENT:$(printf "%21s")" \
                                "COMMENT:Minimun$(printf "%4s")" \
                                "COMMENT:Maximun$(printf "%4s")" \
                                "COMMENT:Average$(printf "%4s")" \
                                COMMENT:"Current\l" \
                                "COMMENT:$(printf "%5s")" \
                                "AREA:upload#FE2E2E95:Upload$(printf "%4s")" \
                                LINE:upload#FE2E2E95 \
                                "GPRINT:min_upload:%5.1lf %sbps$(printf "%1s")" \
                                "GPRINT:max_upload:%5.1lf %sbps$(printf "%1s")" \
                                "GPRINT:avg_upload:%5.1lf %sbps$(printf "%1s")" \
                                "GPRINT:last_upload:%5.1lf %sbps$(printf "%1s")\l" \
                                "COMMENT:$(printf "%5s")" \
                                "AREA:download#2E64FE95:Download$(printf "%2s")" \
                                LINE:download#2E64FE95 \
                                "GPRINT:min_download:%5.1lf %sbps$(printf "%1s")" \
                                "GPRINT:max_download:%5.1lf %sbps$(printf "%1s")" \
                                "GPRINT:avg_download:%5.1lf %sbps$(printf "%1s")" \
                                "GPRINT:last_download:%5.1lf %sbps$(printf "%1s")\l" 1> /dev/null
                        [ $? -gt 0 ] && return 1
                done
        done
        return 0
}

# Function that will create html pages
generateHTML() {
        declare -a ifaces
        local title='Statistical graphs of network traffic'

        # Filtering the $INTERFACES array to return only the network interfaces
        for ((i = 0; i <= ${#INTERFACES[@]}; i++)); do
                ((i % 2 == 0)) && ifaces+=("${INTERFACES[$i]}")
        done

        echo 'Creating HTML pages...'

        # 1 - Create the index page
        cat <<- FIM > ${HTML_DIR}/index.html
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
        <head>
        <title>${0##*/}</title>
        <meta http-equiv="content-type" content="text/html;charset=utf-8" />
        <meta name="author" content="Sandro Marcell" />
        <style type="text/css">
                body { margin: 0; padding: 0; background-color: #AFBFCB; width: 100%; height: 100%; font: 20px/1.5em Helvetica, Arial, sans-serif; }
                a:link, a:visited, a:hover, a:active { text-decoration: none; }
                #header { text-align: center; }
                #content { position: relative; text-align: center; margin: auto; }
                #footer { font-size: 10px; text-align: center; }
                .zoom { transition: transform .2s; margin: 0 auto; }
                .zoom:hover { transform: scale(1.1); }
        </style>
        <script type="text/javascript">
                var refresh = setTimeout(function() {
                                window.location.reload(true);
                }, $((INTERVAL * 1000)));
        </script>
        </head>
        <body>
                <div id="header">
                        <p>$title<br /><small>($(hostname))</small></p>
                </div>
                <div id="content">
                        <script type="text/javascript">
                                $(for i in ${ifaces[@]}; do
                                        echo "document.write('<div><a href="\"${i}.html\"" title="\"Click to see more details.\""><img class="\"zoom\"" src="\"${i}_day.png?nocache=\' + \(Math.floor\(Math.random\(\) \* 1e20\)\).toString\(36\) + \'\"" alt="\"${0##*/} --html\"" /></a></div>');"
                                done)
                        </script>
                </div>
                <div id="footer">
                        <p>${0##*/} &copy; 2016-$(date '+%Y') <a href="https://gitlab.com/smarcell"><u>Sandro Marcell</u></a></p>
                </div>
        </body>
        </html>
FIM

        #2 - Create a specific page for each interface with the defined periods
        for i in ${ifaces[@]}; do
                cat <<- FIM > ${HTML_DIR}/${i}.html
                <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
                "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
                <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
                <head>
                <title>${0##*/}</title>
                <meta http-equiv="content-type" content="text/html;charset=utf-8" />
                <meta name="author" content="Sandro Marcell" />
                <style type="text/css">
                        body { margin: 0; padding: 0; background-color: #AFBFCB; width: 100%; height: 100%; font: 20px/1.5em Helvetica, Arial, sans-serif; }
                        a:link, a:visited, a:hover, a:active { text-decoration: none; }
                        #header { text-align: center; }
                        #content { position: relative; text-align: center; margin: auto; }
                        #footer { font-size: 10px; text-align: center; }
                </style>
                <script type="text/javascript">
                                var refresh = setTimeout(function() {
                                        window.location.reload(true);
                                }, $((INTERVAL * 1000)));
                </script>
                </head>
                <body>
                        <div id="header">
                                <p>$title<br /><small>($(hostname))</small></p>
                        </div>
                        <div id="content">
                                <script type="text/javascript">
                                        $(for p in $PERIODS; do
                                                echo "document.write('<div><img src="\"${i}_${p}.png?nocache=\' + \(Math.floor\(Math.random\(\) \* 1e20\)\).toString\(36\) + \'\"" alt="\"${0##*/} --html\"" /></div>');"
                                        done)
                                </script>
                        </div>
                        <div id="footer">
                                <a href="index.html">[Return]</a>
                                <p>${0##*/} &copy; 2016-$(date '+%Y') <a href="https://gitlab.com/smarcell"><u>Sandro Marcell</u></p>
                        </div>
                </body>
                </html>
FIM
        done
        return 0
}

# Create the html files
# Script call: ./rrd-bandwidth.sh --html
if [ "$1" == '--html' ]; then
        generateHTML
        exit 0
fi

# Collecting data and generating charts
# Script call: ./rrd-bandwidth.sh
generateGraphs
