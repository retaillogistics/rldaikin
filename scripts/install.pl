sub now {
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
    sprintf("%04d%02d%02d%02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
}

$source = $ARGV[0];
($target = $ARGV[1]) =~ s/\\$//;
($sourcebase = $ARGV[0]) =~ s/.*\\//;

if (-d "$target") {
    $target = $target.'\\'.$sourcebase;
}

$newtarget = $target.'_'.now;

if (-f "$target") {
    rename($target, $newtarget) or die "rename: $!\n";
}

if (0 != system("copy $source $target")) {
    rename($newtarget, $target) or die "rename: $!\n";
}
else {
    unlink($newtarget) or print "Delete failed--In use (OK)\n";
}

exit 0;
