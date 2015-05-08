mysql-backup
============

This is a MySQL backup script, which I've built to address my (paranoid)
backup schedule. It's designed to be run on a daily schedule, and preserve
previous backup sets (in the style of logrotate) on the principle of:

* save daily backup sets for 1 week
* save weekly backup sets for 1 month
* save monthly backup sets for 1 year
* save yearly backup sets in perpetuity

On the basis that I'm probably not the only one writing a script to do this,
I've decided to release it into the wild. 

On the basis that not everybody will want to use exactly the same schedule
as me, I've made it moderately configurable.

