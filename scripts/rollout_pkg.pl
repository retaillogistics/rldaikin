#
################################################################################
#
# $URL$
# $Revision$
# $Author$
#
# Description: 
#
# rollout_pkg.pl - Rollout packaging script.  This script is similar to 
#                  hfpkg in that it will package up the rollouts built 
#                  by project teams.
#
#  $Copyright-Start$
#
#  Copyright (c) 2000 - 2009
#  RedPrairie Corporation
#  All Rights Reserved
#
#  This software is furnished under a corporate license for use on a
#  single computer system and can be copied (with inclusion of the
#  above copyright) only for use on such a system.
#
#  The information in this document is subject to change without notice
#  and should not be construed as a commitment by RedPrairie Corporation.
#
#  RedPrairie Corporation assumes no responsibility for the use of the
#  software described in this document on equipment which has not been
#  supplied or approved by RedPrairie Corporation.
#
#  $Copyright-End$
#
################################################################################

require 5.005;

use strict;
use Cwd;
use English;
use Archive::Tar;
use File::Basename;
use File::Find;
use File::stat;
use FindBin;
use IO::Handle;
use POSIX;
use Getopt::Std;

# ------------------------------------------------------------------------------
# Global Variables
# ------------------------------------------------------------------------------

my ($HotFix, $MyDir);

# ------------------------------------------------------------------------------
#
# FUNCTION: CheckPrereqs
#
# PURPOSE:  Check rollout packaging prerequisites.
#
# ------------------------------------------------------------------------------

sub CheckPrereqs
{
    # Check for the rollout utility.
    if (! -f "rollout.pl")
    {
        print STDERR "ERROR: The rollout utility (rollout.pl) does not exist.\n";
        return 1;
    }

    # Check for the rollout script.
    if (! -f "$HotFix")
    {
        print STDERR "ERROR: The rollout script ($HotFix) does not exist.\n";
        return 1;
    }

    # Check for the release notes file.
    if (! -f "README.txt")
    {
        print STDERR "ERROR: The release notes file (README.txt) does not exist.\n";
        return 1;
    }
}

# ------------------------------------------------------------------------------
#
# FUNCTION: CreateFileList
#
# PURPOSE:  Create the rollout file list for Win32 platforms.
#
# ------------------------------------------------------------------------------

sub CreateFileList
{
    # Add this file to the file list.
    sub AddFile
    {
	# We don't want to package everything into the rollout.
        if (-f basename($File::Find::name)                            and 
	       basename($File::Find::name) ne "$HotFix.tgz" and
	       basename($File::Find::name) ne "$HotFix.input"         and
	       basename($File::Find::name) ne "$HotFix.filelist")
	{
	    print OUTFILE "$File::Find::name\n";
	}
    }

    # Change to the directory we're being ran from.
    chdir("$MyDir");

    # Open the file list.
    open(OUTFILE, ">$HotFix.filelist");

    # Set autoflushing on the file list.
    OUTFILE->autoflush(1);

    # Find every file under the given directory.
    find(\&AddFile, ".");

    # Close the file list.
    close(FILELIST);

    return ("$HotFix.filelist");
}

# ------------------------------------------------------------------------------
#
# FUNCTION: PackageHotFix
#
# PURPOSE:  Package the rollout in the current directory.
#
# ------------------------------------------------------------------------------

sub PackageHotFix
{
    my $status = 0; 
    my $tar;
    my($filename, $filelist);

    print "Creating the rollout distribution file... \n";

    # Create the file list
    $filelist = CreateFileList();

    # Next, create the tar file.
    $filename = "$HotFix.tgz";
    $tar = Archive::Tar->new();

    # Now, open the filelist file and loop through and add the files
    # to the archive.
    open(FILELIST, "<$filelist") || die "Could not open filelist file $filelist.\n";

    while (<FILELIST>)
    {
        chomp;
        print "Adding file $_.\n";
        $tar->add_files($_);
    }

    $tar->write($filename,1);

    return;
}

# ------------------------------------------------------------------------------
#
# Start of Execution.
#
# ------------------------------------------------------------------------------

# Define local variables.
my ($status, $usage);

# Handle command line arguments.
$HotFix = $ARGV[0];
shift @ARGV;
$usage = 0;
getopts("h") || $usage++;

if (! $HotFix || $HotFix eq "-h" || $usage || $Getopt::Std::opt_h)
{
  printf STDERR "Usage: perl rollout_pkg.pl <rollout #> [-h]\n";
  printf STDERR " -h          - Help (Print this message) \n";
  exit 1;
}

# Get the current directory.
$MyDir = cwd;

# Check rollout packaging prerequisites.
$status = CheckPrereqs( );
if ($status != 0)
{
    exit 1;
}

# Display a message for the user.
print "\n";
print "Packaging rollout $HotFix...\n";

# Package the rollout files.
$status = PackageHotFix( );
if ($status != 0)
{
    print STDERR "ERROR: Could not package the rollout.\n";
    exit 1;
}

exit 0;
