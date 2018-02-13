#
################################################################################
#
# $URL$
# $Revision$
# $Author$
#
# Description: 
# build_rollout.pl - Utility to build a rollout for a project fix.
#
# This script will automatically build a "rollout" ready for packaging.  It 
# is primarily designed to work with the GNATS database on HOMEBREW, but will
# work given only a CVS repository with tagged values.
#
#  RedPrairie
#  Copyright 2001,2003
#  Waukesha, Wisconsin,  U.S.A.
#  All rights reserved.
#
################################################################################
# GNATS interaction based on GNATSWEB, information below...
#
# Copyright 1998-1999 - Matt Gerassimoff
# and Ken Cox <kenstir@senteinc.com>
#
# $Id$
#
#

use English;
use Env;
use Socket;
use IO::Handle;
use FileHandle;
use Getopt::Std;
use File::Path;
use File::Find;
use File::Copy;

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------
my $usage = "USAGE:\nperl build_rollout.pl [options] "
           ."<PR Number to Build From>\n"
           ."\tOptions:\n"
           ."\t-d <CVS Root>\n"
           ."\t-m <Module>\n "
           ."\t-A <Application (WMP/WMD, default is WMD)>\n "
           ."\t[-h] Show this information\n"
           ."\t[-H] Always distribute the most recent version (HEAD)\n"
           ."\t[-P] Always distribute the version committed to the PR\n"
           ."\t[-B] CVS Branch Tag\n"
           ."\t[-t] Test\n"
           ."\t[-r <Rollout Number>]\n"
           ."\t[-p] DLx Process mode\n"
           ."\t[-n] Do not tag files, use existing tags\n";

# Info about your gnats host.
# TODO - make these a passable parameter
$site_gnats_host = 'homebrew.mfa.com';
$site_gnats_port = 1529;

$DATABASE = 'default';
$USER = 'gnats-admin';
$PASSWORD = 'blahblah';

$PR_PRE = 'PR-';
$PKG_DIR = 'pkg';
$NUMBER_FILE = "ExtensionNumber";

my($cvsroot,$module,$tagvalue,$rolloutnum,$testmode);
my($always_head,$always_committed);
my($branch_tag);
my($gnatsavailable);
my(%files, @removed_files, %pr_release_note, %pr_synopsis);

# ************************START Code stolen from GNATSWEB *********************
# bits in fieldinfo(field, flags) has (set=yes not-set=no)
$SENDINCLUDE  = 1;   # whether the send command should include the field
$REASONCHANGE = 2;   # whether change to a field requires reason
$READONLY  = 4;      # if set, can't be edited
$AUDITINCLUDE = 8;   # if set, save changes in Audit-Trail

# The possible values of a server reply type.  $REPLY_CONT means that there
# are more reply lines that will follow; $REPLY_END Is the final line.
$REPLY_CONT = 1;
$REPLY_END = 2;

#
# Various PR field names that should probably not be referenced in here.
#
# Actually, the majority of uses are probably OK--but we need to map
# internal names to external ones.  (All of these field names correspond
# to internal fields that are likely to be around for a long time.)
#
$CATEGORY_FIELD = 'Category';
$SYNOPSIS_FIELD = 'Synopsis';
$SUBMITTER_ID_FIELD = 'Submitter-Id';
$ORIGINATOR_FIELD = 'Originator';
$AUDIT_TRAIL_FIELD = 'Audit-Trail';
$RESPONSIBLE_FIELD = 'Responsible';
$LAST_MODIFIED_FIELD = 'Last-Modified';
$NUMBER_FIELD = 'builtinfield:Number';
$STATE_FIELD = 'State';
$UNFORMATTED_FIELD = 'Unformatted';
$RELEASE_FIELD = 'Release';

$CODE_GREETING = 200;
$CODE_CLOSING = 201;
$CODE_OK = 210;
$CODE_SEND_PR = 211;
$CODE_SEND_TEXT = 212;
$CODE_NO_PRS_MATCHED = 220;
$CODE_NO_ADM_ENTRY = 221;
$CODE_PR_READY = 300;
$CODE_TEXT_READY = 301;
$CODE_INFORMATION = 350;
$CODE_INFORMATION_FILLER = 351;
$CODE_NONEXISTENT_PR = 400;
$CODE_EOF_PR = 401;
$CODE_UNREADABLE_PR = 402;
$CODE_INVALID_PR_CONTENTS = 403;
$CODE_INVALID_FIELD_NAME = 410;
$CODE_INVALID_ENUM = 411;
$CODE_INVALID_DATE = 412;
$CODE_INVALID_FIELD_CONTENTS = 413;
$CODE_INVALID_SEARCH_TYPE = 414;
$CODE_INVALID_EXPR = 415;
$CODE_INVALID_LIST = 416;
$CODE_INVALID_DATABASE = 417;
$CODE_INVALID_QUERY_FORMAT = 418;
$CODE_NO_KERBEROS = 420;
$CODE_AUTH_TYPE_UNSUP = 421;
$CODE_NO_ACCESS = 422;
$CODE_LOCKED_PR = 430;
$CODE_GNATS_LOCKED = 431;
$CODE_GNATS_NOT_LOCKED = 432;
$CODE_PR_NOT_LOCKED = 433;
$CODE_CMD_ERROR = 440;
$CODE_WRITE_PR_FAILED = 450;
$CODE_ERROR = 600;
$CODE_TIMEOUT = 610;
$CODE_NO_GLOBAL_CONFIG = 620;
$CODE_INVALID_GLOBAL_CONFIG = 621;
$CODE_NO_INDEX = 630;
$CODE_FILE_ERROR = 640;

$| = 1; # flush output after each print

sub gerror
{
  my($text) = @_;
  my $prog = $0;
  $prog =~ s@.*/@@;
  #print "<pre>$prog: $text\n</pre>\n";
  print "Error: $text\n";
}

# Close the client socket and exit.  The exit can be suppressed by:
#     local($suppress_client_exit) = 1;
sub client_exit
{
  close(SOCK);
}

sub server_reply
{
  my($state, $text, $type);
  $_ = <SOCK>;
  print "<tt>server_reply: $_</tt><br>\n" if defined($reply_debug);
  if(/(\d+)([- ]?)(.*$)/)
  {
    $state = $1;
    $text = $3;
    if($2 eq '-')
    {
      $type = $REPLY_CONT;
    }
    else
    {
      if($2 && $2 ne ' ')
      {
        gerror("bad type of reply from server: ".hex $2."!");
      }
      $type = $REPLY_END;
    }
    return ($state, $text, $type);
  }
  return (undef, undef, undef);
}

sub read_server
{
  my(@text);

  while(<SOCK>)
  {
    print "<tt>read_server: $_</tt><br>\n" if defined($reply_debug);
    if(/^\.\r/)
    {
      return @text;
    }
    $_ =~ s/[\r\n]//g;
    # Lines which begin with a '.' are escaped by gnatsd with another '.'
    $_ =~ s/^\.\././;
    push(@text, $_);
  }
}

sub get_reply
{
  my @rettext = ();
  my $state;
  my $text;
  my $type;

  do {
    ($state, $text, $type) = server_reply();
    if($state == $CODE_GREETING)
    {
      push(@rettext, $text);
      # nothing
    }
    elsif($state == $CODE_OK || $state == $CODE_GREETING 
	  || $state == $CODE_CLOSING)
    {
      push(@rettext, $text);
      # nothing
    }
    elsif($state == $CODE_PR_READY || $state == $CODE_TEXT_READY)
    {
      @rettext = read_server();
    }
    elsif($state == $CODE_SEND_PR || $state == $CODE_SEND_TEXT)
    {
      # nothing, tho it would be better...
    }
    elsif($state == $CODE_INFORMATION_FILLER)
    {
      # nothing
    }
    elsif($state == $CODE_INFORMATION)
    {
      push(@rettext, $text);
    }
    elsif($state == $CODE_NO_PRS_MATCHED)
    {
      # nothing
    }
    elsif($state >= 400 && $state <= 799)
    {
      if ($state == $CODE_NO_ACCESS) 
      {
	$text = "Access denied";
      }
      gerror("HCPRUN".$state ."E ". $text);
      client_exit();
      push(@rettext, $text);
    }
    elsif ($status ne "")
    {
      push(@rettext, $text);
      gerror("cannot understand $state '$text'");
    }
  } until ($type != $REPLY_CONT);
  return @rettext;
}

sub fieldinfo
{
  my $fieldname = shift;
  my $member = $_[0];
  
  return $fielddata{$fieldname}{$member};
}

sub isvalidfield
{
  return exists($fielddata{$_[0]}{'fieldtype'});
}

sub init_fieldinfo
{
  my $debug = 0;
  my $field;

  @fieldnames = client_cmd("list FieldNames");
  my @type = client_cmd ("ftyp ". join(" ",@fieldnames));
  my @desc = client_cmd ("fdsc ". join(" ",@fieldnames));
  my @flgs = client_cmd ("fieldflags ". join(" ",@fieldnames));
  my @fdflt = client_cmd ("inputdefault ". join(" ",@fieldnames));
  foreach $field (@fieldnames) {
    $fielddata{$field}{'flags'} = 0;
    $fielddata{$field}{'fieldtype'} = lc(shift @type);
    $fielddata{$field}{'fieldflags'} = lc(shift @flgs);
    if ($fielddata{$field}{'fieldflags'} =~ /requirechangereason/)
    {
      $fielddata{$field}{'flags'} |= $REASONCHANGE;
    }
    if ($fielddata{$field}{'fieldflags'} =~ /readonly/)
    {
      $fielddata{$field}{'flags'} |= $READONLY;
    }
    my @values = client_cmd ("fvld $field");
    $fielddata{$field}{'values'} = [@values];
    $fielddata{$field}{'default'} = shift (@fdflt);
    $fielddata{$field}{'default'} =~ s/\\n/\n/g;
    $fielddata{$field}{'default'} =~ s/\s$//;
  }
  foreach $field (client_cmd ("list InitialInputFields")) {
    $fielddata{$field}{flags} |= $SENDINCLUDE;
  }
  if ($debug)
  {
    foreach $field (@fieldnames) {
      warn "name = $field\n";
      warn "  type   = $fielddata{$field}{'fieldtype'}\n";
      warn "  flags  = $fielddata{$field}{'flags'}\n";
      warn "  values = $fielddata{$field}{'values'}\n";
      warn "\n";
    }
  }
}

sub client_init
{
  my($iaddr, $paddr, $proto, $line, $length);

  $iaddr = inet_aton($site_gnats_host);
  $paddr = sockaddr_in($site_gnats_port, $iaddr);

  $proto = getprotobyname('tcp');
  if(!socket(SOCK, PF_INET, SOCK_STREAM, $proto))
  {
    gerror("socket: $!");
    exit();
  }
  if(!connect(SOCK, $paddr))
  {
    $gnatsavailable = 0;
  }
  else
  {
    $gnatsavailable = 1;
    SOCK->autoflush(1);
    get_reply();
  }
}

# to debug:
#     local($client_cmd_debug) = 1;
#     client_cmd(...);
sub client_cmd
{
  my($cmd) = @_;
  my $debug = 0;
  print SOCK "$cmd\n";
  warn "client_cmd: $cmd" if $debug;
  print "<tt>client_cmd: <pre>$cmd</pre></tt><br>\n"
        if defined($client_cmd_debug);
  return get_reply();
}

# initialize -
#     Initialize gnatsd-related globals and login to gnatsd.
#
sub initialize
{
  my $regression_testing = shift;

  my($debug) = 0;

  my(@lines);
  my $response;

  # Get gnatsd version from initial server connection text.
  ($response) = client_init();
  $GNATS_VERS = 999.0;
  if (!$gnatsavailable)
  {
      return;
  }

  if ($response =~ /GNATS server (.*) ready/)
  {
    $GNATS_VERS = $1;
    print "GNATS Version is $GNATS_VERS.\n" if ($testmode);
  }

  # Suppress fatal exit while issuing CHDB and USER commands.  Otherwise
  # an error in the user or database cookie values can cause a user to
  # get in a bad state.
  LOGIN:
  {
    local($suppress_client_exit) = 1
          unless $regression_testing;

    # Issue CHDB command; revert to login page if it fails.
    ($response) = client_cmd("chdb $DATABASE");
    if (!$response)
    {
      print "Error changing database...";
      exit();
    }
    
    # Get user permission level from USER command.  Revert to the
    # login page if the command fails.
    ($response) = client_cmd("user $USER $PASSWORD");
    if (!$response)
    {
      print "Error logging in...";
      exit();
    }
    $access_level = 'edit';
    if ($response =~ /User access level set to (\w*)/)
    {
      $access_level = $1;
    }

    # Now initialize our metadata from the database.
    init_fieldinfo ();
  }
}

sub parsepr
{
  my $debug = 0;

  my($hdrmulti) = "envelope";
  my(%fields);
  foreach (@_)
  {
    chomp($_);
    $_ .= "\n";
    if(!/^([>\w\-]+):\s*(.*)\s*$/)
    {
      if($hdrmulti ne "")
      {
        $fields{$hdrmulti} .= $_;
      }
      next;
    }
    local($hdr, $arg, $ghdr) = ($1, $2, "*not valid*");
    if($hdr =~ /^>(.*)$/)
    {
      $ghdr = $1;
    }

    $cleanhdr = $ghdr;
    $cleanhdr =~ s/^>([^:]*).*$/$1/;

    if(isvalidfield ($cleanhdr))
    {
      if(fieldinfo($cleanhdr, 'fieldtype') eq 'multitext')
      {
        $hdrmulti = $ghdr;
	$fields{$ghdr} = "";
      }
      else
      {
        $hdrmulti = "";
        $fields{$ghdr} = $arg;
      }
    }
    elsif($hdrmulti ne "")
    {
      $fields{$hdrmulti} .= $_;
    }
  }

  # 5/8/99 kenstir: To get the reporter's email address, only
  # $fields{'Reply-to'} is consulted.  Initialized it from the 'From'
  # header if it's not set, then discard the 'From' header.
  $fields{'Reply-To'} = $fields{'Reply-To'} || $fields{'From'};
  delete $fields{'From'};

  # Ensure that the pseudo-fields are initialized to avoid perl warnings.
  $fields{'X-GNATS-Notify'} ||= '';

  # 3/30/99 kenstir: For some reason Unformatted always ends up with an
  # extra newline here.
  $fields{$UNFORMATTED_FIELD} =~ s/\n$//;

  if ($debug) {
    warn "--- parsepr fields ----\n";
    my %fields_copy = %fields;
    foreach (@fieldnames)
    {
      warn "$_ =>$fields_copy{$_}<=\n";
      delete $fields_copy{$_}
    }
    warn "--- parsepr pseudo-fields ----\n";
    foreach (sort keys %fields_copy) {
      warn "$_ =>$fields_copy{$_}<=\n";
    }
    warn "--- parsepr attachments ---\n";
    my $aref = $fields{'attachments'} || [];
    foreach $href (@$aref) {
      warn "    ----\n";
      while (($k,$v) = each %$href) {
        warn "    $k =>$v<=\n";
      }
    }
  }

  return %fields;
}

sub lockpr
{
  my($pr, $user) = @_;
  #print "<pre>locking $pr $user\n</pre>";
  return parsepr(client_cmd("lock $pr $user"));
}

sub unlockpr
{
  my($pr) = @_;
#  print "<pre>unlocking $pr\n</pre>";
  client_cmd("unlk $pr");
}

sub readpr
{
  my($pr) = @_;

  # Not sure if we want to do a RSET here but it probably won't hurt.
  client_cmd ("rset");
  client_cmd ("QFMT full");
  return parsepr(client_cmd("quer $pr"));
}
# ************************END Code stolen from GNATSWEB ***********************

# -----------------------------------------------------------------------------
# exec_cvs
#
# Executes a CVS command against the root and returns the results.
# -----------------------------------------------------------------------------
sub exec_cvs
{
  my($cmd) = @_;
  my($results);

  open(CVS, "cvs -Qd $cvsroot $cmd |") || die "Unable to run CVS command";

  while (<CVS>)
  {
    $results .= $_;
  }

  close CVS;

  return $results;
}

# -----------------------------------------------------------------------------
# get_affected_objects
#
# Goes through a PR and finds the affected objects and their versions.
# -----------------------------------------------------------------------------
sub get_affected_objects
{
  my($pr) = @_;
  
  my($file,$file_ver,$object,%objects);

  my(%fields) = readpr($pr);
  my($fix) = $fields{'Fix'};
  $pr_release_note{$pr} = $fields{'Release-Note'};
  $pr_synopsis{$pr} = $fields{'Synopsis'};

  my(@affected) = split /CVS_WEB_LINK/, $fix;

  foreach $object (@affected)
  {
    if ($object =~ /^\/(.*)CVS_WEB_SEP/)
    {
      $file = $1;
      if ($object =~ /Rev:(\s*)(\S*)CVS_WEB_END/)
      {
        $file_ver = $2;
      }

      # First see if there is a hash for this file out there already
      if (exists $objects{$file})
      {
        # If this version is greater than the one stored, store it.
        # Otherwise, leave it alone.
        if ($file_ver eq "Removed" || $file_ver > $objects{$file})
        {
          $objects{$file} = $file_ver;
        }
      }
      else
      {
        # It doesn't exist, so add it
        $objects{$file} = $file_ver;
      }
    }
  }

  return %objects;
}

# -----------------------------------------------------------------------------
# get_current_version
#
# Gets the current version from the head of the file.
# -----------------------------------------------------------------------------
sub get_current_version
{
  my($file) = @_;

  my($results,$version);

  # First, checkout the file.

  if ($branch_tag eq "" )
  {
    $results = exec_cvs("checkout $file");
  }
  else
  {
    # we are building code for a branch in CVS so 
    # check out the branch tag of the code

    $results = exec_cvs("checkout -r $branch_tag $file");
  }

  # Now, get the current version of the file
  $results = exec_cvs("stat $file");

  if ($results ne "")
  {
    if ($results =~ /Working revision:(\s*)(\S*)(.*)/)
    {
      $version = $2;
    }
    else
    {
      $version = "0.0";
    }
  }

  return $version;

}

# -----------------------------------------------------------------------------
# get_tagged_version
#
# Will only return a version if it is already tagged at this level.  Otherwise
# it will return 0.
# -----------------------------------------------------------------------------
sub get_tagged_version
{
  my($pr, $file) = @_;
  my($tag_version);

  # Check to see if this has been tagged already, and return the version.
  my($response) = exec_cvs("log -h $file");

  if ($response ne "")
  {
    if ($response =~ /(\s*)$PR_PRE$pr:(\s*)(\S*)/)
    {
      $tag_version = $3;
    }
    else
    {
      $tag_version = 0;
    }
  }
  else
  {
    $tag_version = 0;
  }

  return $tag_version;
}

# -----------------------------------------------------------------------------
# operate_on_pr
#    this tags the files with the PR-number tag
#    we also want to tag the files with the rollout number!
# -----------------------------------------------------------------------------
sub operate_on_pr
{
  my($pr) = @_;
  my($cur_version,$tag_version,$com_version,$results,$result);
  my($tag_head);

  if ($testmode)
  {
    print "**Operating on PR $pr\n";
    print "**Affected Objects-\n";
    print "\tFile - Affected Version - Head Version - Tagged Version\n";
  }

  my (%objects) = get_affected_objects($pr);
  foreach $file (keys (%objects))
  {
    if ($objects{$file} ne "Removed")
    {
      # Get the relevent versions of the file
      $cur_version = get_current_version($file);
      $tag_version = get_tagged_version($pr, $file);
      $com_version = $objects{$file};

      print "\t$file - "
           ."$com_version - "
           ."$cur_version - "
           ."$tag_version\n" if ($testmode);

      # There are basically two scenarios.  One where the current version
      # is the head, and one where the current version is not the head.
      # If it is not the head, we will prompt the user to see which one 
      # to distribute, regardless of the tagged version.
      if ($com_version < $cur_version)
      {
        if ($always_head)
        {
          $tag_head = 1;
        }
        elsif ($always_committed)
        {
          $tag_head = 0;
        }
        else
        {
          # Prompt to see what they want to do
          print "\n";
          print "A newer version of $file has been committed since\n";
          print "the version committed for this PR.\n";
          print "  Current Tag version: $tag_version\n";
          print "  Committed version:   $com_version\n";
          print "  Head version:        $cur_version\n";
          print "Do you wish to distribute the most recent version?\n";
          print "(No will distribute the version committed for this PR): ";
          read (STDIN,$result,2);
          print "\n";
          if (uc(substr($result, 0, 1)) eq "N")
          {
            $tag_head = 0;
          }
          else
          {
            $tag_head = 1;
          }
        }
        if ($tag_head)
        {
          print "\t\t***Creating tag $PR_PRE$pr on $file at version "
               ."$cur_version (HEAD).\n" if ($testmode);

          print "Tagging file $file with tag $PR_PRE$pr" if (!$testmode);
          $results = exec_cvs "tag -F $PR_PRE$pr $file";
          print " and tag $rolloutnum" if ($tag_file_with_rollout_number);
          $results = exec_cvs "tag -F $rolloutnum $file" if ($tag_file_with_rollout_number); 
          print "... done\n" if (!$testmode);
        }
        else
        {
          print "\t\t***Creating tag $PR_PRE$pr on $file at version "
               ."$com_version (PR Committed).\n" if ($testmode);

          print "Tagging file $file, revision $com_version with tag $PR_PRE$pr" if (!$testmode);
          $results = exec_cvs "tag -r $com_version -F $PR_PRE$pr $file";
          print " and tag $rolloutnum" if ($tag_file_with_rollout_number);
          $results = exec_cvs "tag -r $com_version -F $rolloutnum $file" if ($tag_file_with_rollout_number); 
          print "... done\n" if (!$testmode);
        }
      }
      else # Committed version IS the head.
      {
        if ($tag_version > 0 && $tag_version < $com_version)
        {
          # Only need to warn if this will not match their expectations.
          if (!$always_head && !$always_committed)
          {
            print "\n";
            print "A prior version of $file\n";
            print "has already been tagged.  However, since the HEAD version\n";
            print "matches the version committed for the PR, it will be \n";
            print "distributed.\n";
            print "  Current Tag version: $tag_version\n";
            print "  Committed version:   $com_version\n";
            print "  Head version:        $cur_version\n";
          }
        }
        print "\t\t***Creating tag $PR_PRE$pr on $file at version "
             ."$cur_version (HEAD).\n" if ($testmode);

        print "Tagging file $file with tag $PR_PRE$pr" if (!$testmode);
        $results = exec_cvs "tag -F $PR_PRE$pr $file";
        print " and tag $rolloutnum" if ($tag_file_with_rollout_number);
        $results = exec_cvs "tag -F $rolloutnum $file" if ($tag_file_with_rollout_number);
        print "... done\n" if (!$testmode);
      }
    }
    else
    {
      print "\t***$file has been removed.\n" if ($testmode);
      print "Found a file that needs to be removed $file\n" if (!$testmode);
      $removed_files[$#removed_files + 1] = $file;
    }
  } # foreach affected object

  return;
}

# -----------------------------------------------------------------------------
# get_children
#
# Returns any PR that is related to this PR through the Controlling-PR field.
# -----------------------------------------------------------------------------
sub get_children
{
  my($pr) = @_;

  my(@child_prs,$child,@return_prs,$count,@line);

  # Not sure if we want to do a RSET here but it probably won't hurt.
  client_cmd ("rset");
  client_cmd ("QFMT sql2");
  client_cmd ("expr Controlling-PR=\"$pr\"");

  @child_prs = client_cmd("quer");
  $count = 0;

  foreach $child (@child_prs)
  {
    @line = split /\|/, $child;
    $return_prs[$count++] = $line[0];
  }

  return @return_prs;
}

# -----------------------------------------------------------------------------
# go_forth_and_tag
#
# This routine will go through the PR sent in, find the objects that 
# were affected and tag them with the PR number and extension number.
# It will also do this for all of the child PRs associated with the PR.
# -----------------------------------------------------------------------------
sub go_forth_and_tag
{
  my($pr) = @_;
  my($child,@children);

  print "\nTagging for Parent PR $pr.\n";

  operate_on_pr($pr);
  @children = get_children($pr);
  foreach $child (@children)
  {
    print "\nTagging for Child PR $child.\n"; 
    operate_on_pr($child);
  }

  # Remove the directory created by the tag operation
  if (!$testmode)
  {
    rmtree($module, 0, 0);
  }

  return @children;
}

# -----------------------------------------------------------------------------
# get_next_number
#
# Gets the next extension number, and increments it if we aren't testing.
# -----------------------------------------------------------------------------
sub get_next_number
{
  my($response,$number,$length,$new_number);

  my($prefix,$num);

  print "Getting next number for extension number.\n" if ($testmode);
  $response = exec_cvs("co $module/config/$NUMBER_FILE");

  open EXT, "<$module/config/$NUMBER_FILE";

  $number = <EXT>;
  chomp($number);

  exit (print STDERR "Could not get number from environment.\n"
                    ."Please ensure that the $NUMBER_FILE file exists "
                    ."in $module.\n") if ($number eq "");

  close EXT;

  print "\tWe will use extension number: $number\n" if ($testmode);

  # Split the number into the prefix and numeric portion.
  if ($number =~ /(\D*)(\d*)/)
  {
    $pre = $1;
    $num = $2;
  }

  print "\tPrefix: $pre - $Numeric: $num\n" if ($testmode);

  $length = length($num);

  $new_number = sprintf "$pre%0${length}d", $num + 1;

  if (!$testmode)
  {
    # Increment the number and put it back in the file, then check it in.
    open EXT, ">$module/config/$NUMBER_FILE";
    print EXT "$new_number";
    close EXT;
    $response = exec_cvs("commit -m \"PR NONE\" $module/config/$NUMBER_FILE");
  }
  else
  {
    print "\tNext number would be $new_number\n";
  }

  # Remove the checked out tree so we can work in a new directory.
  rmtree($module, 0, 0);

  return $number;
}

# -----------------------------------------------------------------------------
# create_extension_directory
# -----------------------------------------------------------------------------
sub create_extension_directory
{
  my($rolloutnum) = @_;

  if (-d "$rolloutnum")
  {
    rmtree("$rolloutnum", 0, 0);
  }
  print "Creating directory $rolloutnum.\n" if ($testmode);
  mkdir ("$rolloutnum", 0775);

  print "Copying file rollout.pl to package directory.\n" if ($testmode);
  copy("${LESDIR}/scripts/rollout.pl", "$rolloutnum");

  print "Copying file create_c_makefiles.pl to package directory.\n" if ($testmode);
  copy("${LESDIR}/scripts/create_c_makefiles.pl", "$rolloutnum");
}

# -----------------------------------------------------------------------------
# create_readme
# -----------------------------------------------------------------------------
sub create_readme
{
  my($rolloutnum, $tagvalue, @children) = @_;

  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year += 1900;
  $mon++;

  my($child, $all_child, $all_release_notes, $file, $all_files, $removed_file, $removed, $today);

  # not used anymore
  # foreach $child(@children)
  # {
  #   $all_child .= "\t$child\n";
  # }
  
  # get a list of all the PRs and all the synopsises 
  foreach $file (keys (%pr_synopsis))
  {
    # print PR XXXX - Synopsis
    $all_child .= "\tPR $file - $pr_synopsis{$file}\n";
  }

  foreach $file (sort keys %files)
  {
    if ($file =~ /$PKG_DIR\/(.*)/)
    {
      $all_files .= "\t$1\n";
    }
  }

  foreach $file (sort @removed_files)
  {
    # the problem here is $file = $LESDIR/dir/filename and we need
    # to strip out the $LESDIR so we will do it in more lines of Perl
    # than necessary to make it readable to us non-Perl Wizards
    $removed_file = $file;
    $removed_file =~ s/\$LESDIR\///;
    $removed .= "\t$removed_file\n";
  }

  # get all the release notes $file is the pr and $pr_release_note{$file} is the the release note
  foreach $file (keys (%pr_release_note))
  {
    $all_release_notes .= "PR $file - $pr_synopsis{$file}\n\n$pr_release_note{$file}\n\n";
  }

  # now all the release notes are in one big string $all_release_notes and will
  # be formatted and printed later 

  $today = $year."-".$mon."-".$mday;

  open README, ">README.txt";

  # First write out the header
format README_TOP =
================================================================================
Extension: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<@>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
           $rolloutnum,                   $today
================================================================================
.

  README->format_name("README_TOP");
  write (README);

  # Now, write the rest of the file.
  print README <<EOF;

PR(s): 
$all_child

Affected Files:
$all_files

Removed Files:
$removed

Release Notes:

EOF

  # print the release notes from the big string

  # split the string into an array of lines

  @LINES = split/\n/,$all_release_notes;

  foreach $line (@LINES){

    # split the lines into words
    @WORDS = split/\s/,$line;
    $len = 0;
    foreach $word (@WORDS){
      $len += length ($word);
      # if we have gone over 60 chars print a new line and reset the ctr
      if ($len > 60) {
        print README "\n";
        $len = 0;
      }
      print README "$word ";
    }
    print README "\n";
  }

  # Finally, write the rest of the file.
  print README <<NEWEOF;

================================================================================
                   N T   I N S T A L L A T I O N   N O T E S             
================================================================================

    1.  Verify that all assumptions stated in the "Assumptions" section of the
        "Logistics Suite Hot Fix Utility" document are true.  The document can
        be downloaded from http://sputnik.mfa.com/hotfixes.  Contact your  
        RedPrairie project team or RedPrairie Customer Support for a copy of
        this document.

    2.  Set Visual C++ environment variables.

        You will first have to change to the Visual C++ bin directory if it 
        isn't in your search path.

        vcvars32.bat

    3.  Set Logistics Suite environment variables.

        cd %LESDIR%
        ..\\moca\\bin\\servicemgr /env=<environment name> /dump
        env.bat

        Note: If you know your env.bat file is current you can omit this step,
              if you are not sure then rebuild one.

    4.  Shutdown the Logistics Suite environment.  

        NON-CLUSTERED Environment

        *** IMPORTANT ***
        If you are on a production system, make sure the development system 
        whose drive has been mapped to the system being modified has also been 
        shutdown to avoid sharing violations.

        mocaregedit

        Select the Logistics Suite environment and click on the 'Edit' button.
        Select the 'Service' tab and click on the 'Stop Service' button.

        CLUSTERED Environment
       
        If you are running under a NT or Win2K Cluster, you must use the
        Microsoft Cluster Administrator to stop the LES Service.

    5.  Copy the rollout distribution file into the environment's temporary 
        directory.

        cd -d %LESDIR%\\temp
        copy <SOURCE_DIR>\\$rolloutnum.zip .

    6.  Uncompress the distribution file using WinZip.  

        winzip $rolloutnum.zip

        Make sure you extract all the files to a folder called $rolloutnum.

    7.  Install the rollout.

        perl rollout.pl $rolloutnum

    8.  Start up the Logistics Suite environment.

        NON-CLUSTERED Environment
       
        mocaregedit

        Select the Logistics Suite environment and click on the 'Edit' button.
        Select the 'Service' tab and click on the 'Start Service' button.

        CLUSTERED Environment

        If you are running under a NT or Win2K Cluster, you must use the
        Microsoft Cluster Administrator to start the LES Service.


================================================================================
                 U N I X   I N S T A L L A T I O N   N O T E S             
================================================================================

    1.  Verify that all assumptions stated in the "Assumptions" section of the
        "Logistics Suite Hot Fix Utility" document are true.  The document can
        be downloaded from http://sputnik.mfa.com/hotfixes.  Contact your  
        RedPrairie project team or RedPrairie Customer Support for a copy of
        this document.

    2.  Login as the Logistics Suite environment's administrator.

        telnet <hostname>

    3.  Shutdown the Logistics Suite environment.

        DLx Warehouse/D command:	rp stop
  
    4.  Copy the rollout distribution file into the environment's temporary 
        directory.

        cd \$LESDIR/temp
        cp <SOURCE_DIR>/$rolloutnum.tar .

    5.  Uncompress and untar the rollout archive file using tar.

        tar -xvf $rolloutnum.tar 

    6.  Install the rollout.

        perl rollout.pl $rolloutnum

    7.  If installing in DLx Warehouse/P, run clean_invalid.sql:
    	DLx Warehouse/D command:	<not required>
	DLx Warehouse/P command:	sql @$DMP_UNISQL/clean_invalid.sql ALL

    8.  Start up the Logistics Suite environment.

        DLx Warehouse/D command:	rp start
	DLx Warehouse/P command:	dmplus_start -l 0

================================================================================

NEWEOF

  close README;

}

# -----------------------------------------------------------------------------
# accum_files
#
# This is called from the FIND routine to accumulate files into the
# global %files hash.
# -----------------------------------------------------------------------------
sub accum_files
{
  print "$File::Find::name will be packaged.\n" if (!-d $_ && $testmode);
  $files{$File::Find::name} = $File::Find::dir if (!-d $_);
}


# -----------------------------------------------------------------------------
# get_files_to_package
#
# Retrieve the files that need to be packaged and move them to the 
# newly created extension directory.
# -----------------------------------------------------------------------------
sub get_files_to_package
{
  my($pr,@children) = @_;

  my($results,$child,$file);

  # Get the pkg directory out of the way first.
  rmtree("$PKG_DIR", 0, 0);

  # First, export the parent files needed.
  print "Exporting files for controlling pr $pr.\n" if ($testmode);
  # to be safe we should test if we are in BRANCH mode or not - but
  # because we do a cvs tag -F (force) this code is probably ok for now
  $results = exec_cvs("-Q export -d $PKG_DIR -r $PR_PRE$pr $module");

  # Next, export all of the child files needed.
  foreach $child (@children)
  {
    print "Exporting files for child pr $child.\n" if ($testmode);
    $results = exec_cvs("-Q export -d $PKG_DIR -r $PR_PRE$child $module");
  }

  print "---Finding files to package---\n" if ($testmode);
  my(@dirs) = ("$PKG_DIR");
  find(\&accum_files, @dirs);

  # print "---Copying files to package directory---\n" if ($testmode);
  # foreach $file (keys (%files))
  # {
  #  print "Copying file $file to package directory.\n" if ($testmode);
  #  copy($file, ".");
  # }

  # if (!$testmode)
  # {
  #   rmtree("$PKG_DIR", 0, 0);
  # }

  # %files is global, so no need to return it here.

}

# -----------------------------------------------------------------------------
# create_install_script
#
# Creates a best guess for an install script for the affected objects.
#
# A RedPrairie engineer must review the script before using it or sending it
# to a customer.  Since the order of files in this script may not be the
# order necessary to install.  
#
# Possible commands are described below along with the criteria that 
# the script uses to determine if we should invoke that command.
#
# ADD 
#       this script will never use.  We'll always use REPLACE.
#
#
# IMPORTSLDATA filename
#       will import (insert only) any file affected with the .slexp extension
#       using this slimp command: slImp -v -f filename -i
#
# UPDATESLDATA filename
#       will import (update mode) any file affected with the .slexp extension
#       using this slimp command: slImp -v -f filename
#
# LOADDATA
#       any file affected with the .ctl extension
#
# LOADTRX
#       any file affected with the .trx extension - Uniface
#
# MBUILD
#       if /cmdsrc/ is in the full path for the file
#
# REBUILD
#       if /incsrc/, /appsrc/, or /libsrc/ is in the full path for the file
#
# RECONFIGURE
#       if /config/ or /makefiles/ is in the full path for the file
#
# REMOVE
#       if the file was removed (only available when connected to GNATS)
#
# REPLACE
#       uses for all files distributed
#
# RUNMSQL
#       any file affected with the .msql extension
#
# RUNSQL
#       any file affected with the .sql, .tbl, .pck, .bdy, .hdr, .prc, .trg, .seq, .idx extensions
#
# COMPSQL
#       any file affected with the .sql, .tbl, .pck, .bdy, .hdr, .prc, .trg, .seq, .idx extensions in Process Mode
#
# RUNSQLIGNOREERRORS
#       any file affected with the .iesql exension
#
# RUNSCRIPT
#       any file affected with the .pl, .cmd, or .bat extension
# -----------------------------------------------------------------------------
sub create_install_script
{
  my($rolloutnum) = @_;

  my($reconfig) = 0;
  my($mbuild) = 0;
  my($rebuild) = 0;
  my($appsrc) = 0;
  my($libsrc) = 0;
  my($rfsrc) = 0;
  my($incsrc) = 0;
  my($ddlsrc) = 0;

  # These are the hashes to the tables where we will be rebuilding 
  # makefiles.
  my(%c_makefiles);

  my($file,$short_file,$install_path,$base_file_name,$ctl_file,$csv_file);

  my($dbload,$msqlrun,$sqlrun,$iesqlrun,$scriptrun,$trxrun);
 
  my($slimport);

  # Open a file for output
  open INSTALL, ">$rolloutnum";

  # Print the header and disclaimer
  print INSTALL <<EOF;
# Extension: $rolloutnum
#
# This script has been built automatically using build_rollout.pl.  Please
# check the actions taken by the script as they may not be entirely correct.
# Also check the order of the actions taken if any dependencies might be
# encountered.
#

EOF

  # OK, now let's start operating on the affected objects.
  print INSTALL "# Replacing files affected by extension.\n";

  foreach $file (sort keys %files)
  {
    # Get the base filename
    if ($file =~ /$files{$file}\/(.*)/)
    {
      $base_file_name = $1;
    }

    $short_file = $file;

    # Get the install location
    if ($files{$file} =~ /$PKG_DIR\/(.*)/)
    {
      $install_path = "\$LESDIR\/$1";
    }
    else
    {
      # We get to this because the file we are attempting to replace is in the LESDIR
      # so want to make sure the update path is correct.
      $install_path = "\$LESDIR";
    }

    print "Making install for file ($file) at install_path ($install_path) short_file_name ($short_file)\n";

    # Replace the file
    print INSTALL "REPLACE $short_file $install_path\n";

    # Now decide what to do at the end, if anything
    if (!$mbuild && $file =~ /\/cmdsrc\//)
    {
      $mbuild = 1;
    }

    if (!$appsrc &&
         $file =~ /\/appsrc\// )
    {
        $rebuild = 1;
        $appsrc =1;
        $c_makefiles{$install_path} = 1;
        # print "Found a appsrc C file ($file)... $install_path \n";
    } 
   
    if ($file =~ /\/libsrc\// )
    { 
       $rebuild = 1;
       $libsrc = 1;
       $c_makefiles{$install_path} = 1;
       # print "Found a libsrc C file ($file)... $install_path \n";
    }
      
    if (!$incsrc &&
        $file =~ /\/incsrc\// )
    { 
       $rebuild = 1;
       $incsrc = 1;
# Still need to figure out how to create the makefile for incsrc
# no standard one exists for this 
#       $c_makefiles{$install_path} = 1;
    }

    # Java or MTF changes - need to rebuild.
    if ($short_file =~ /(.*)\.java/)
    {
        $rebuild = 1;
    }

    if (!$ddlsrc &&
        $file =~ /\/ddl\// )
    { 
       $ddlsrc = 1;
       print "Found a ddl file... $file (ddlsrc = $ddlsrc)\n";
    }

    if (!$reconfig &&
        ($file =~ /\/config\// ||
         $file =~ /\/makefiles\//))
    {
      $reconfig = 1;
    }

    # See if we have to do any data loads or script runs.
    if ($short_file =~ /(.*)\.csv/)
    {
      # this needs rework  
      $dbload .= "LOADDATA $install_path.ctl $base_file_name\n";
    }

    # Check for .iesql scripts (ignore errors)
    if ($short_file =~ /(.*)\.iesql/)
    {
      $iesqlrun .= "RUNSQLIGNOREERRORS $short_file\n";
    }

    # Check for .trx scripts
    if ($short_file =~ /(.*)\.trx/)
    {
      $trxrun .= "LOADTRX $short_file\n";
    }

    if ($application eq "WMP")
    {
       # Check for .sql scripts
       if ($short_file =~ /(.*)\.sql/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }

       # Check for .tbl scripts
       if ($short_file =~ /(.*)\.tbl/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }

       # Check for .idx scripts
       if ($short_file =~ /(.*)\.idx/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }

       # Check for .trg scripts
       if ($short_file =~ /(.*)\.trg/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }

       # Check for .prc scripts
       if ($short_file =~ /(.*)\.prc/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }

       # Check for .hdr scripts
       if ($short_file =~ /(.*)\.hdr/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }

       # Check for .pck scripts
       if ($short_file =~ /(.*)\.pck/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }

       # Check for .seq scripts
       if ($short_file =~ /(.*)\.seq/)
       {
	 $sqlrun .= "COMPSQL $short_file\n";
       }
    }
    else
    {
       # Check for .sql scripts
       if ($short_file =~ /(.*)\.sql/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .tbl scripts
       if ($short_file =~ /(.*)\.tbl/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .idx scripts
       if ($short_file =~ /(.*)\.idx/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .trg scripts
       if ($short_file =~ /(.*)\.trg/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .hdr scripts
       if ($short_file =~ /(.*)\.hdr/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .prc scripts
       if ($short_file =~ /(.*)\.prc/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .hdr scripts
       if ($short_file =~ /(.*)\.hdr/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .pck scripts
       if ($short_file =~ /(.*)\.pck/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }

       # Check for .seq scripts
       if ($short_file =~ /(.*)\.seq/)
       {
	 $sqlrun .= "RUNSQL $short_file\n";
       }
    }


    # Check for .msql scripts
    if ($short_file =~ /(.*)\.msql/)
    {
      $msqlrun .= "RUNMSQL $short_file\n";
    }

    # Check for .slexp scripts (insert only mode)
    if ($short_file =~ /(.*)\.slexp/)
    {
      $slimport .= "IMPORTSLDATA $short_file\n";
    }

    # Check for .uslexp scripts (update mode)
    if ($short_file =~ /(.*)\.uslexp/)
    {
      $slimport .= "UPDATESLDATA $short_file\n";
    }

    # Check for other scripts
    if ($short_file =~ /(.*)\.pl/ ||
        $short_file =~ /(.*)\.bat/ ||
        $short_file =~ /(.*)\.cmd/)
    {
      $scriptrun .= "RUNSCRIPT $short_file\n";
    }

  }

  print INSTALL "\n# Removing files removed by extension.\n";
  foreach $file (sort @removed_files)
  {
    $file =~ s/$module\//\$LESDIR\//;

    print INSTALL "REMOVE $file\n";

    # Now decide what to do at the end, if anything
    if (!$mbuild && $file =~ /\/cmdsrc\//)
    {
      $mbuild = 1;
    }

    if (!$rebuild && 
        ($file =~ /\/libsrc\// ||
         $file =~ /\/appsrc\// ||
         $file =~ /\/incsrc\//))
    {
      $rebuild = 1;
    }

    if (!$reconfig &&
        ($file =~ /\/config\// ||
         $file =~ /\/makefiles\//))
    {
      $reconfig = 1;
    }
  }

  # if we have any new DDL scripts we need to do a make install in incsrc first

  if ($ddlsrc == 1){
    # todo - can we just rebuild incsrc?
    print INSTALL "\n# We found a DDL script so rebuild les just in case incsrc changed.\n";
    print INSTALL "REBUILD LES\n";
  }

  # Run any scripts that were affected
  print INSTALL "\n# Run any SQL, MSQL, and other scripts.\n";
  print INSTALL "$sqlrun";
  print INSTALL "$msqlrun";
  print INSTALL "$scriptrun";

  print INSTALL "$iesqlrun";

  # Import and Compile Uniface objects
  print INSTALL "\n# Import and compile Uniface objects.\n";
  print INSTALL "$trxrun";

  # Load any data needed.
  print INSTALL "\n# Load any data affected.  NOTE the assumption is that\n";
  print INSTALL "# the control file will be in the db/data/load directory.\n";
  print INSTALL "$dbload";

  # Import any sl data as needed.
  print INSTALL "\n# Import any seamles data affected. \n";
  print INSTALL "$slimport";

  # Before we rebuild, we need to create the makefiles if needed
  print INSTALL "\n# Rebuilding C makefiles if necessary\n";
  foreach $file (sort keys %c_makefiles)
  {
    # Build the makefile in that directory.
    if ($file ne "\$LESDIR/src/libsrc")  # do not make a makefile for libsrc dir
    {
      print INSTALL "RUNSCRIPT perl create_c_makefiles.pl $file\n";
    }
  }

  # Finally, issue the appropriate rebuild commands
  print INSTALL "\n# Perform any environment rebuilds if necessary.\n";
  if ($mbuild)
  {
    print INSTALL "MBUILD\n";
  }

  if ($reconfig)
  {
    print INSTALL "RECONFIGURE LES\n";
  }

  if ($rebuild)
  {
    print INSTALL "REBUILD LES\n";
  }

  print INSTALL "\n# END OF AUTO-GENERATED SCRIPT.\n";
  
}

# -----------------------------------------------------------------------------
# checkPreReqa
#
# Checks that all of the requisite parameters are passed in and that the
# required files are present.
# -----------------------------------------------------------------------------
sub checkPreReqs
{
  my($tagvalue,$notag,$rolloutnum) = @_;

  if ($tagvalue eq "")
  {
    print STDERR "Please supply a PR number\n";
    print $usage;
    return (0);
  }

  if ($notag && $rolloutnum eq "")
  {
    print STDERR "Rollout number (-r) is required if not tagging.\n";
    print $usage;
    return (0);
  }

  # Check to see that the rollout.pl script is available in 
  # $LESDIR/scripts.

  if (!-e "${LESDIR}/scripts/rollout.pl")
  {
    print STDERR "${LESDIR}/scripts/rollout.pl does not exist.  Please copy\n";
    print STDERR "this file to \$LESDIR/scripts/.\n";
    return (0);
  }

  if (!-e "${LESDIR}/scripts/create_c_makefiles.pl")
  {
    print STDERR "${LESDIR}/scripts/create_c_makefiles.pl does not exist.\n";
    print STDERR "Please copy this file to \$LESDIR/scripts/.\n";
    return (0);
  }

  return (1);
}

# -----------------------------------------------------------------------------
# remove_tags
#
# Removes tags created during a test run of the rollout.
# -----------------------------------------------------------------------------
sub remove_tags
{
  my($main_pr, @children) = @_;
  my($child, $results);

  # Issue a remove tag command for each PR that was affected.
  # First remove the parent PR number
  print "Removing tags...\n";
  print "\tRemoving tag $PR_PRE$main_pr.\n";
  $results = exec_cvs("rtag -d $PR_PRE$main_pr $module");

  # Now, go through each child and remove the tags created for it.
  foreach $child (@children)
  {
    print "\tRemoving tag $PR_PRE$child.\n";
    $results = exec_cvs("rtag -d $PR_PRE$child $module");
  }
  return;
}

# -----------------------------------------------------------------------------
# MAIN starts here:
# -----------------------------------------------------------------------------
sub main
{
  my(@children,$help,$notag,$result,$child);

  $testmode = 0;
  $notag = 0;

  STDOUT->autoflush(1);
  STDERR->autoflush(1);

  # Handle the command line options
  getopts('hnd:m:tHPr:B:A:') or exit(print $usage);

  $help = $opt_h if defined ($opt_h);
  $cvsroot = $opt_d if defined ($opt_d);
  $module = $opt_m if defined ($opt_m);
  $testmode = $opt_t if defined ($opt_t);
  $rolloutnum = $opt_r if defined ($opt_r);
  $notag = $opt_n if defined ($opt_n);
  $always_head = $opt_H if defined ($opt_H);
  $always_committed = $opt_P if defined ($opt_P);
  $tagvalue = join(' ', @ARGV);
  $branch_tag = $opt_B if defined ($opt_B);
  $application = $opt_A if defined ($opt_A);

  if (!$notag or $testmode)
  {
    # tag files with rollout number too
    $tag_file_with_rollout_number = 1;
  }

  exit(print $usage) if ($cvsroot eq "" || $module eq "") || $help;

  if ($always_head && $always_committed)
  {
    print STDERR "Cannot use both H and P options.  It is not possible\n";
    print STDERR "to always distribute the HEAD and to always distribute\n";
    print STDERR "the PR version. If working on a CVS branch include the \n";
    print STDERR "B option with the branch tag value\n";
    exit (print $usage);
  }

  if (!checkPreReqs($tagvalue,$notag,$rolloutnum))
  {
    exit();
  }
  
  # todo - add more applications like RPTSRV, MOCARPT, LENS, etc

  if ($application eq "WMP")
  {
    print "\n";
    print "Building Rollout for DLx Warehouse Process\n";
  }
  else
  {
    print "\n";
    print "Building Rollout for DLx Warehouse Discrete\n";
  }
 
  if ($testmode)
  {
    # Warn the user that existing tags will be lost and prompt to see
    # if they will continue.
    print "\n";
    print "WARNING!!!  You are running in TEST MODE.  At the end of the the\n";
    print "script, any existing tags that match tags created by this script\n";
    print "will be lost.\n";
    print "Do you wish to continue? ";
    read (STDIN, $result, 2);

    if (uc(substr($result, 0, 1)) eq "N")
    {
      exit(print "\nScript Aborted.\n");
    }

    print "\n";
    print "Arguments:\n";
    print "\tCVS Root: $cvsroot\n";
    print "\tModule: $module\n";
    print "\tRollout Number: $rolloutnum\n";
    print "\tTag Value: $tagvalue\n";
    print "\tNo Tag: $notag\n";
    print "\tAlways Tag HEAD: $always_head\n";
    print "\tAlways Tag PR Version: $always_committed\n";
    print "\tBranch Tag: $branch_tag\n";
    print "\tApplication: $application\n";
    print "\n";
  }

  # Initialize the connection to the GNATS daemon.
  initialize();

  if ($rolloutnum eq "")
  {
    $rolloutnum = get_next_number();
  }

  print "Building rollout $rolloutnum.\n";

  create_extension_directory($rolloutnum);
  chdir "$rolloutnum";

  print "Tagging files with TAG: PR-$tagvalue";
  print " and with rollout TAG: $rolloutnum\n" if ($tag_file_with_rollout_number);
  print "\n";

  if ($gnatsavailable && !$notag)
  {
    @children = go_forth_and_tag($tagvalue);
  }

  # %files = get_files_to_package(@children);
  get_files_to_package($tagvalue, @children);

  print "Creating Install Script $rolloutnum\n";
  create_install_script($rolloutnum);

  print "Creating README.txt $rolloutnum, $tagvalue\n";
  create_readme($rolloutnum, $tagvalue, @children);

  client_exit();

  print "\n";
  print "Rollout created in the $rolloutnum directory.\n";
  print "Please review the install script prior to packaging.\n";

  if ($testmode)
  {
    print "\n";
    print "** Script was run in TESTMODE.  Temporary directories have not \n";
    print "** been removed so that they may be perused.\n";
    print "**\n";
    print "** The following tags will be cleaned up.  NOTE: even if these\n";
    print "** tags existed before running this script, they will still be\n";
    print "** removed at this time:\n";
    print "** \t$PR_PRE$tagvalue\n";
    foreach $child (@children)
    {
      print "** \t$PR_PRE$child\n";
    }
    print "\n";
    remove_tags($tagvalue, @children);
  }

  exit();
}

main();
