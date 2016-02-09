BlueDBM v2

Compilation Guide:
"git clone https://github.com/sangwoojun/bluespecpcie"
go to project directory (e.g. projects/flash)
just once, generate required cores. Namely, run "make core"
run "make"
copy build/c.tgz to deployment server

Distribution Guide:
copy driver, bdbm_dist.tgz to deployment server
extract bdbm_dist.tgz and modify the two scripts to point to correct bitfile, etc
run programall.sh
if this is the first time programming, reboot
if rebooted, in drivers, run "sudo make configbackup"
in drivers, run "sudo make insmod"

Now you are ready to run the software binary


Development Guide:
(Files to fix)

requires https://github.com/sangwoojun/bluespecpcie
