#!perl
# $Id$
################################################################################
#
# $URL$
# $Revision$
# $Author$
#
# Description: 
# $Id: - Utility to add new LESDIR data load files from MCS and SAL
#
# This script will automatically add new csv files in $LESDIR/db/data/load/base directory
# from MCS and SAL.
#
#  RedPrairie
#  Copyright 2006
#  Waukesha, Wisconsin,  U.S.A.
#  All rights reserved.
#
################################################################################
#
#

use strict;

use English;
use Env;
use IO::Handle;
use FileHandle;
use Getopt::Std;
use File::Path;
use File::Find;
use File::Copy;

my $lesdir = $ENV{LESDIR};
my $mcsdir = $ENV{MCSDIR};
my $saldir = $ENV{SALDIR};

my $curdir;
my $ctldir;

my $csvfile;
my $ctlfile;
my $lescsvfile;
my $lesctlfile;
my ($line, $curline);
my $answer;
my $product;
my @product_list = ("MCS", "SAL");

my $tmp;

my $usage = <<"_EOF_USAGE_";
Synchronize .ctl and .csv dataload files for LESDIR
Usage:
perl $ARGV[0] [-h] [-d] [-p prod_list]
    -h    Show help
    -d    Destroy original .ctl and .csv files
          Default: only new files are added
    -p    Product list to synchronize
          Default: "MCS,SAL"
_EOF_USAGE_

getopts('hadp:') or exit(print $usage);

if($Getopt::Std::opt_h)
{
    print $usage;
    exit 0;
}

if($Getopt::Std::opt_p)
{
    @product_list = split(/,/, $Getopt::Std::opt_p);
}


if(($lesdir eq "") || !(-d $lesdir)) {die "LESDIR [${lesdir}] not defined or invalid!\n"};

if($Getopt::Std::opt_d)
{
    print "\nWARNING: this script will synchronize dataload csv and control files\n";
    print "in LESDIR dataload directory (${lesdir}/db/data/load/base) with @product_list\n";
    print "WARNING: any existing LESDIR custom dataload data will be completely lost.\n";
    print "Do you want to continue? (Y/N):\n";

    $answer = <STDIN>;

    chomp $answer;

    if(!($answer eq "Y"))
    {
        exit 0;
    }

    # Cleanup the original LES files first:

    foreach $curdir ("bootstraponly", "safetoload")
    {
        chdir("$ENV{LESDIR}/db/data/load/base/${curdir}");
        system("del *.ctl");
        system("del /S *.csv");
    }
}


# Note, might add additional products here
# First do MCS, then SAL
foreach $product (@product_list)
{
    my $productdir = $ENV{"${product}DIR"};

    print "Processing product ${product}\n";

    if(($productdir eq "") || !(-d $productdir)) {die "${product}DIR [${productdir}] not defined or invalid!\n"};

    foreach $curdir ("bootstraponly", "safetoload")
    {
        my @ctldirs;
        
        chdir("${productdir}/db/data/load/base/${curdir}");
        print "Processing directory ${productdir}/db/data/load/base/${curdir}\n";

        @ctldirs = (<*>);

        print "Found directories @ctldirs\n";

        foreach $ctldir ( @ctldirs )
        {
            $csvfile = "";
            $ctlfile = "";

            print "Checking directory ${ctldir}\n";
            chdir("${productdir}/db/data/load/base/${curdir}");

            if((-d $ctldir)&& !($ctldir eq "CVS"))
            {
                my $csvexists = 0;
                my $srcdir = "${productdir}/db/data/load/base/${curdir}/${ctldir}";
                my $srcctl = "${srcdir}.ctl";
                my $destdir = "$ENV{lesdir}/db/data/load/base/${curdir}/${ctldir}";
                my $destctl = "${destdir}.ctl";

                # Don't bother if .ctl file is not present
                if(! -f $srcctl)
                {
                    print "SKIP: no .ctl file for ${srcdir}\n";
                    next;
                }

                # Don't bother if there are no .csv files
                $csvexists = 0;
                foreach $tmp ( <${srcdir}/*.csv > )
                {
                    $csvexists = 1;
                    last;
                }

                if( !$csvexists)
                {
                    print "SKIP: no .csv files in ${srcdir}\n";
                    next;
                }

                print "Found control directory ${ctldir}\n";

                # Check if LESDIR has the same 

                if(! -f $destctl)
                {
                    print "MISSING: ${destctl}\n";

                    # NOTE: we cannot update existing data.  This is because the
                    # .ctl files might be different for MCS and SAL.
                    # So if we already copied .ctl and .csv files from MCS,
                    # then we don't want to copy additional files from SAL.

                    # Need to:
                    # - create the directory if it does not exist
                    # - copy the .ctl file
                    # - copy all .csv files, but keep only the 1st line.
                    
                    if( ! -d ${destdir})
                    {
                        mkdir("${destdir}") or die "Cannot create directory ${destdir}: $!\n";
                    }

                    print "Copying control file ${srcctl}\n";
                    print "                  to ${destctl}\n";
                    copy($srcctl, $destctl) 
                        or die "Error copying file ${srcctl} to ${destctl}: $!\n";

                    # Now copy each csv file
                    chdir($srcdir);

                    foreach $tmp ( <*.csv > )
                    {
                        copy_csv_file("${srcdir}/${tmp}", "${destdir}/${tmp}");
                    }
                }
            }
        }
    }
}

sub copy_csv_file
{
    my ($csvfile, $lescsvfile) = @_;
    my $curline;

    print "Copying ${csvfile} to ${lescsvfile}\n";

    open( FH_SRC, $csvfile ) || die "Cannot open ${csvfile}: $!\n";
    while( $curline = <FH_SRC> )
    {
        $line = $curline;
        last;
    }
    close(FH_SRC);

    if(! ($line eq ""))
    {
        print "Updating cvs file ${lescsvfile}\n";
        print "             from ${csvfile}\n";

        open(FH_DST, ">${lescsvfile}") || die "Cannot open ${lescsvfile}: $!\n";
        printf FH_DST $line;
        close(FH_DST);
    }
}

