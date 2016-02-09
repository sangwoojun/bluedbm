BlueDBM v2

Compilation Guide:
NOTE: Development was done in vivado 2015.4

"git clone https://github.com/sangwoojun/bluespecpcie"
go to project directory (e.g. projects/flash)
just once, generate required cores. Namely, run "make core"
run "make"
copy build/c.tgz to deployment server

in software directory(e.g., projects/flash/cpp/flash, run "make"
Copy software binary to deployment server

Distribution Guide:
copy driver, bdbm_dist.tgz to deployment server
extract bdbm_dist.tgz and modify the two scripts to point to correct bitfile, etc
run programall.sh
if this is the first time programming, reboot
if rebooted, in drivers, run "sudo make configbackup"
in drivers, run "sudo make insmod"

Now you are ready to run the software binary

BSIM Guide:
in projects directory, run "make bsim"
in software directory, run "make bsim"
run "./run.sh"
(run.sh sets up env, runs bsim and software, and cleans up afterward)


Development Guide:
(Files to fix)

requires https://github.com/sangwoojun/bluespecpcie
