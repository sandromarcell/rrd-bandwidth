# Bandwidth measurement with RRDtool
Shell bash script that using RRDTool generates daily, weekly, monthly and annual statistical graphs of network traffic on the monitored interfaces, all in a very simple way.
## Development
### This project was developed and tested in the following environment:
```
- GNU/Linux 4.18.0-147.5.1.el8_1.x86_64 - CentOS Linux release 8.1.1911 (Core)
- GNU bash, version 4.4.19(1)-release (x86_64-redhat-linux-gnu)
- GNU coreutils 8.30
- RRDtool 1.7.0
- lighttpd/1.4.55
```
## Setup
### 1 - Edit "rrd-bandwidth.sh" and change GLOBAL VARIABLES as needed
### 2 - Grant permission to execute the script
```
chmod 755 rrd-bandwidth.sh
```
### 3 - Run the script to generate the databases
```
./rrd-bandwidth.sh
```
### 4 - Run again, to generate the html pages
```
./rrd-bandwidth.sh --html
```
### 5 - Schedule the update task in crontab
```
*/5 * * * * /path/to/rrd-bandwidth.sh >&- 2>&-
```
Finally, access the generated html pages through a web browser.

![img](screenshot.png)

*P.S. Sorry for the bad translation...*  :bow:
