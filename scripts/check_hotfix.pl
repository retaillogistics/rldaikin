########################################################################
#
# $URL$
# $Revision$
# $Author$
#
# Description: Hot fix check utility.
# Usage: check_hotfix.pl <hot fix name> 
#  For example: check_hotfix.pl VAR00012
#
########################################################################

$HotFix = $ARGV[0];
#my $HotFixDirectory = "$ENV{LESDIR}/hotfixes/$HotFix";
#$HotFixDirectory=~s/\\/\//g;
my $HotFixDirectory = "c:/src/hotfixes/$HotFix";

my $HotFixScript;
my @line;


# Set the hot fix script and make sure it exists.
$HotFixScript = "$HotFixDirectory/$HotFix";
if (! -r $HotFixScript)
{

    print "ERROR: The hot fix script does not exist.\n";
    print "       $!\n";
    print "       Script: $HotFixScript\n";
    exit 1;
}
print "The file differences for the hutfix $HotFix are:\n\n\n";


# Open the hot fix script.
$status = open(INFILE, "$HotFixScript");
if ($status == 0)
{
    
    print "ERROR: Could not open hotfix script.\n";
    print "       $!\n";
    print "       Script: $HotFixScript\n";
    exit 1;
}


# Cycle through each line in the hot fix script.
while (<INFILE>) {
chomp;

# Skip comment lines.
next if (/^#/);                                 # Comment

# Parse the line and pick out the command.
@line = split(' ');
$command = shift @line;

# Pick out each argument.
if ($command =~ /^add$/i)                       # Add               
{
  print "$command instruction\n";
  print "Comparing $line[0].\n";
  print "with $line[1]\\$line[0].\n\n\n";
  system("diff $HotFixDirectory/$line[0] $line[1]/$line[0]");
}
elsif ($command =~ /^replace$/i)                # Replace
{
  print "$command instruction\n";
  print "Comparing $line[0].\n";
  print "with $line[1]\\$line[0].\n\n\n";
  system("diff $HotFixDirectory/$line[0] $line[1]/$line[0]");
}
}

# Close the hot fix script.
close(INFILE);
