#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>

#include <string.h>

/* Remember the effective and real UIDs. */

static uid_t euid, ruid;


/* Restore the effective UID to its original value. */

	void
do_setuid (void)
{
	int status;

#ifdef _POSIX_SAVED_IDS
	status = seteuid (euid);
#else
	status = setreuid (ruid, euid);
#endif
	if (status < 0) {
		fprintf (stderr, "Couldn't set uid.\n");
		exit (status);
	}
}


/* Set the effective UID to the real UID. */

	void
undo_setuid (void)
{
	int status;

#ifdef _POSIX_SAVED_IDS
	status = seteuid (ruid);
#else
	status = setreuid (euid, ruid);
#endif
	if (status < 0) {
		fprintf (stderr, "Couldn't set uid.\n");
		exit (status);
	}
}
char three[3] = "3\n";

int main(int argc, char** argv) {
	ruid = getuid ();
	euid = geteuid ();
	undo_setuid ();

	do_setuid();
	sync();
	
	//echo 3 | sudo tee /proc/sys/vm/drop_caches
	int fdc = open("/proc/sys/vm/drop_caches", O_WRONLY);
	int ret = write(fdc, three, 3);
	if ( ret < 2 ) {
		printf( "Drop cache failed!\n" );
		exit(1);
	}
	close (fdc);
	undo_setuid ();
	printf( "Cached dropped!\n" );
	exit(0);
}
