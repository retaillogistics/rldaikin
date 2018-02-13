################################################################################
#
# $URL$
# $Revision$
# $Author$
#
# Description: 
# rollout_unpkg.pl - Utility to unpackage a rollout package in the desintation
#                    environment.
#
# This script uncompresses the files compressed and "tarred" while creating
# a hotfix-style rollout using rollout_pkg.pl.  These files can also be 
# uncompressed through WINZIP on a Windows system or using gunzip/tar on
# a UNIX system.
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
use Archive::Tar;
use strict;

my $file_name;
my $file;
my $dir;
my $result;
my $LESDIR;
my $tar;

#
# Verify command line arguments
#

$file_name = $ARGV[0];
if ($file_name eq "")
{
    print STDERR "ERROR: Archive filename not specified!\n";
    usage();
}

if (!(-f $file_name))
{
    print STDERR "ERROR: Can not find archive file: $file_name\n";
    usage();
}

print "This program will uncompress the archive file: $file_name\n";
print "to the current directory.  Are you sure you want to do this? ";
read (STDIN,$result,1);

if ( uc(substr($result, 0, 1)) eq "Y" )
{
    $tar = Archive::Tar->new($file_name,1);

    foreach $file ($tar->list_files)
    {
        print "$file\n";
        $tar->extract($file);
    }
}
else
{
    print "Uncompress aborted.\n";
}

# ------------------------------------------------------------------------------
#
# FUNCTION: usage
#
# PURPOSE: Display program usage
#
# ------------------------------------------------------------------------------

sub usage
{
   print STDERR "usage: perl rollout_unpkg.pl <archive file>\n";
   exit(-1);
}
