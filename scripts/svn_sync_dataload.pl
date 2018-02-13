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
use FindBin;

my $product;
my @product_list = ("mcs", "sal", "wmd");

my $tmp;

my $usage = <<"_EOF_USAGE_";
Synchronize .ctl and .csv dataload files for ENV from Subversion repository.

Usage:
perl $0 [-h] [-p prod_list] [-r revision] [-a]
    -h    Show help (this message)
    -p    Product list to synchronize, default "mcs,sal,wmd"
    -r    ENV revision (trunk, tags/2007.2.0, branches/2007.1-dev etc)
    -a    Do "svn add" on new files

NOTES: 
- You need to run this file from the live Subversion ENV checkout.
- The script automatically determines the currently checked-out version
- The modifications are local, so you need to manually check-in any changes.
_EOF_USAGE_

getopts('hp:r:a') or exit(print $usage);

if($Getopt::Std::opt_h)
{
    print $usage;
    exit 0;
}

if($Getopt::Std::opt_p)
{
    @product_list = split(/,/, $Getopt::Std::opt_p);
}

my $command;
my $output;
my @lines;
my $line;
my $tag;


if($Getopt::Std::opt_r)
{
    $tag = $Getopt::Std::opt_r;
}
else
{
    # GET THE CURRENT SUBVERSION TAG
    $command = "svn info $0";
    print "${command}\n";
    $output = `${command}`;
    @lines = split ('\n', $output);

    foreach $line (@lines)
    {
        chomp $line;
        if( $line =~ /URL:/)
        {
            $line =~ s/^.*\/svn\/prod\/env\/((branches\/[^\/]+)|(tags\/[^\/]+)|(trunk))\/.*$/$1/;
            $tag = $line;
            print "USING SVN TAG [${tag}]\n";
            last;
        }
    }
}

if($tag eq "")
{
   print "ERROR DETERMINING SVN TAG, QUITTING\n";
   exit 2;
}

foreach  $product (@product_list)
#foreach  $product ('mcs')
{
    my $subdir;

    print "PROCESSING PRODUCT ${product}\n";

    foreach $subdir ('bootstraponly', 'safetoload')
    {
        $command = "svn ls https://athena.redprairie.com/svn/prod/${product}/${tag}/db/data/load/base/${subdir}";
        $output = `${command}`;
        my @lines = split ('\n', $output);

        foreach $line (@lines)
        {
            chomp $line;

            if( $line =~ /dbversion/)
            {
                # IGNORE *_dbversion, because those are product-specific
                print "SKIPPING ${line}\n";
                next;
            }
            elsif( $line =~ /^.*\.ctl$/)
            {
                # PROCESS CONTROL FILES
                my $file = $line;
                my $newfile = 0;
                my $filename = "$FindBin::Bin/../db/data/load/base/${subdir}/${file}";
                print "CONTROL FILE: [${file}]\n";

                if( ! -f "${filename}")
                {
                    $newfile = 1;
                }

                $command = "svn export https://athena.redprairie.com/svn/prod/${product}/${tag}/db/data/load/base/${subdir}/${file}  ${filename}";
                print "${command}\n";
                system($command);

                if($newfile && $Getopt::Std::opt_a)
                {
                    $command = "svn add ${filename}";
                    print "${command}\n";
                    system($command);
                }
            }
            else
            {
                # PROCESS DIRECTORIES
                my $folder = $line;
                $folder =~ s/\///;
                print "FOLDER: [${folder}]\n";


                if(! -d "$FindBin::Bin/../db/data/load/base/${subdir}/${folder}")
                {
                    print "NEW DIRECTORY: ${subdir}/${folder}\n";
                    mkdir("$FindBin::Bin/../db/data/load/base/${subdir}/${folder}");

                    if($Getopt::Std::opt_a)
                    {
                        $command = "svn add $FindBin::Bin/../db/data/load/base/${subdir}/${folder}";
                        print "${command}\n";
                        system($command);
                    }
                }

                #PROCESS DATA FILES
                $command = "svn ls https://athena.redprairie.com/svn/prod/${product}/${tag}/db/data/load/base/${subdir}/${folder}";

                $output = `${command}`;
                my @files = split ('\n', $output);
                # Default to the 1st file
                # But check if can find file ${folder}.csv

                my $file;
                my $csvfile = $files[0];

                foreach $file (@files)
                {
                    chomp $file;
                    if($file eq "${folder}.csv")
                    {
                        $csvfile = $file;
                        last;
                    }
                }

                if($csvfile eq "")
                {
                    next;
                }

                $command = "svn cat https://athena.redprairie.com/svn/prod/${product}/${tag}/db/data/load/base/${subdir}/${folder}/${csvfile}";
                $output = `${command}`;
                my @textlines = split ('\n', $output);
                my $text;
                foreach $text (@textlines)
                {
                    chomp $text;
                    if( ($text =~ /#/) || ($text eq ""))
                    {
                        next;
                    }

                    # Got a valid line
                    print "File ${csvfile} :[${text}]\n";

                    # Now update all files in the dataload directory
                    my $found = 0;

                    foreach $file (<$FindBin::Bin/../db/data/load/base/${subdir}/${folder}/*.csv>)
                    {
                        $found = 1;
                        open(CSVFILE, ">${file}");
                        print CSVFILE "${text}\n";
                        close(CSVFILE);

                    }

                    if(! $found)
                    {
                        my $newfile = 0;
                        my $filename = "$FindBin::Bin/../db/data/load/base/${subdir}/${folder}/${folder}.csv";

                        if(! -f "${filename}")
                        {
                            $newfile = 1;
                        }

                        open(CSVFILE, ">${filename}");
                        print CSVFILE "${text}\n";
                        close(CSVFILE);

                        if($newfile && $Getopt::Std::opt_a)
                        {
                            $command = "svn add ${filename}";
                            print "${command}\n";
                            system($command);
                        }
                    }

                    last;
                }
            }
        }
    }
}


